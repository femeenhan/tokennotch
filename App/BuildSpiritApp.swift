import AppKit
import SwiftUI
import SpiritCore

@main
@MainActor
final class BuildSpiritApp: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let model = CompanionModel()
    private var companion: CompanionPanel!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var motionReviewWindow: NSWindow?
    private var dashboardWindow: NSWindow?
    private var quotaPanel: NSPanel?
    private var quotaLocalClickMonitor: Any?
    private var quotaGlobalClickMonitor: Any?
    private var quotaAnchorFrame: CGRect?
    private var alertPanel: NSPanel?
    private var presentedAlertID: UUID?
    private var heartbeat: Timer?
    private var sleeping = false
    private var screensAsleep = false
    private var sessionInactive = false
    private var screenLocked = false
    private var fullscreenLikely = false
    private var hookServer: SpiritSocketServer?
    private var completionPresentationTimer: Timer?
    private var presentedCompletionID: UUID?
    private var greetingPresentationTimer: Timer?
    private var presentedGreetingID: UUID?

    static func main() {
        let app = NSApplication.shared
        let delegate = BuildSpiritApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--light-appearance") { NSApplication.shared.appearance = NSAppearance(named: .aqua) }
        DashboardTheme.registerFonts()
        companion = CompanionPanel(size: model.size)
        companion.positionChanged = { [weak self] in self?.model.saveOrigin($0) }
        companion.clicked = { [weak self] in self?.openUsageQuickLook() }
        companion.contextMenuRequested = { [weak self] in self?.showCompanionMenu() }
        if let saved = model.savedOrigin { companion.correctPosition(saved) }
        else { companion.correctPosition(CGPoint(x: CGFloat.greatestFiniteMagnitude, y: 0)) }
        companion.spiritScene.render(state: .idle, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        model.onAppearanceChange = { [weak self] in self?.updateAppearance() }
        model.onAlertChange = { [weak self] in self?.updateAlertPresentation() }
        var socketURL = SpiritSocketLocation.defaultURL
        if let index = CommandLine.arguments.firstIndex(of: "--socket"), index + 1 < CommandLine.arguments.count {
            socketURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        }
        model.configureDashboard(at: socketURL.deletingLastPathComponent().appendingPathComponent("dashboard.sqlite"))
        if let index = CommandLine.arguments.firstIndex(of: "--quota-executable"), index + 1 < CommandLine.arguments.count {
            model.quotaExecutableOverride = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        }
        model.quotaAutomaticAllowed = !CommandLine.arguments.contains("--diagnostics") || model.quotaExecutableOverride != nil
        model.configureQuotaHistory(at: socketURL.deletingLastPathComponent().appendingPathComponent("quota-history.json"))
        do {
            hookServer = try SpiritSocketServer(url: socketURL) { [weak self] event in
                Task { @MainActor in self?.model.receiveHook(event) }
            }
            model.hookStatus = "수신 준비 완료. CLI 설정과 /hooks 신뢰 승인이 필요합니다."
        } catch {
            model.hookStatus = "이벤트 수신을 시작하지 못했습니다. 다른 빌드정령 실행 여부와 폴더 권한을 확인해 주세요."
        }
        Task { await model.detectCodex() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "flame", accessibilityDescription: "빌드정령")
        statusItem.button?.toolTip = "빌드정령"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu(menu)
        observeWorkspace()
        heartbeat = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        if let heartbeat { RunLoop.main.add(heartbeat, forMode: .common) }
        updateAppearance()
        tick()
        if CommandLine.arguments.contains("--motion-review") { openMotionReview() }
        if CommandLine.arguments.contains("--dashboard") { openDashboard() }
        if CommandLine.arguments.contains("--usage") { openUsageQuickLook() }
        if CommandLine.arguments.contains("--diagnostics") {
            perform(#selector(printDiagnostics), with: nil, afterDelay: 2)
        }
    }

    private var suspended: Bool { sleeping || screensAsleep || sessionInactive || screenLocked }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification,
                     NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.accessibilityDisplayOptionsDidChangeNotification] {
            center.addObserver(self, selector: #selector(workspaceChanged(_:)), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // macOS has no documented lock-only NSWorkspace notification. These system notifications
        // supplement public session/screen-sleep events; their names are not a stable API contract.
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(lockChanged(_:)),
                name: Notification.Name(name), object: nil)
        }
    }

    @objc private func workspaceChanged(_ notification: Notification) {
        switch notification.name {
        case NSWorkspace.willSleepNotification: sleeping = true
        case NSWorkspace.didWakeNotification: sleeping = false
        case NSWorkspace.screensDidSleepNotification: screensAsleep = true
        case NSWorkspace.screensDidWakeNotification: screensAsleep = false
        case NSWorkspace.sessionDidResignActiveNotification: sessionInactive = true
        case NSWorkspace.sessionDidBecomeActiveNotification: sessionInactive = false
        case NSWorkspace.accessibilityDisplayOptionsDidChangeNotification:
            companion.spiritScene.render(state: model.spiritState, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        default: break
        }
        tick()
    }

    @objc private func lockChanged(_ notification: Notification) {
        screenLocked = notification.name.rawValue == "com.apple.screenIsLocked"
        tick()
    }

    @objc private func screensChanged() { companion.correctPosition(); tick() }

    @objc private func tick() {
        if !suspended { fullscreenLikely = frontmostWindowCoversScreen(); model.checkDeadlines(); model.pollUsage(); model.refreshQuota() }
        let weekly = [model.generalQuotaBucket?.primary, model.generalQuotaBucket?.secondary].compactMap { $0 }.first { $0.windowDurationMins == 10080 }
        let freshQuota = model.quotaIsFresh(at: Date())
        statusItem.button?.title = weekly?.remainingPercent.map { " " + $0.formatted(.number.precision(.fractionLength(0))) + "%" + (freshQuota ? "" : "*") } ?? ""
        statusItem.button?.toolTip = "빌드정령 · 주간 계정 한도" + (freshQuota ? "" : " · * 이전 관측값 또는 조회 대기")
        updateAppearance()
    }

    private func updateAppearance() {
        guard companion != nil else { return }
        if companion.spiritScene.spiritState != model.spiritState {
            companion.spiritScene.render(state: model.spiritState,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
        if presentedCompletionID != model.eventStream.completionPresentationID {
            completionPresentationTimer?.invalidate()
            completionPresentationTimer = nil
            presentedCompletionID = model.eventStream.completionPresentationID
            if let id = presentedCompletionID {
                // The prototype presents completion for one second; future sprite clips can
                // call the same token-checked finish path when their animation ends.
                let timer = Timer(timeInterval: 1, target: self,
                    selector: #selector(completionPresentationFinished(_:)), userInfo: id, repeats: false)
                completionPresentationTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        }
        if presentedGreetingID != model.eventStream.greetingPresentationID {
            greetingPresentationTimer?.invalidate()
            greetingPresentationTimer = nil
            presentedGreetingID = model.eventStream.greetingPresentationID
            if let id = presentedGreetingID {
                let timer = Timer(timeInterval: 0.9, target: self,
                    selector: #selector(greetingPresentationFinished(_:)), userInfo: id, repeats: false)
                greetingPresentationTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        }
        if companion.frame.width != model.size {
            companion.resize(to: CompanionGeometry.clampedSize(model.size))
            companion.correctPosition()
        }
        let visible = model.isShown && !suspended && !(model.hideInFullScreen && fullscreenLikely)
        if !visible { dismissUsageBubble() }
        else if quotaPanel != nil && quotaAnchorFrame != companion.frame { positionUsageBubble() }
        if companion.isVisible != visible || companion.interactionPanel.isVisible != visible
            || companion.spiritView.isPaused == visible {
            companion.setRendering(active: visible)
        }
        updateAlertPresentation()
    }

    @objc private func completionPresentationFinished(_ timer: Timer) {
        guard let id = timer.userInfo as? UUID else { return }
        model.finishCompletionPresentation(id: id)
    }

    @objc private func greetingPresentationFinished(_ timer: Timer) {
        guard let id = timer.userInfo as? UUID else { return }
        model.finishGreetingPresentation(id: id)
    }

    /// Public window metadata heuristic; maximized borderless windows can be false positives.
    private func frontmostWindowCoversScreen() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              pid != ProcessInfo.processInfo.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let displayBounds = NSScreen.screens.compactMap { screen -> CGRect? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CGDisplayBounds(number.uint32Value)
        }
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let dictionary = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return false }
            return displayBounds.contains { screen in
                abs(bounds.minX - screen.minX) <= 2 && abs(bounds.minY - screen.minY) <= 2 &&
                abs(bounds.width - screen.width) <= 2 && abs(bounds.height - screen.height) <= 2
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) { rebuildMenu(menu) }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: "빌드정령", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        let presentation = SpiritPresentation(state: model.spiritState)
        let state = NSMenuItem(title: "상태: \(presentation.label)", action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        let hint = NSMenuItem(title: presentation.hint, action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        addItem("사용량 바로 보기…", action: #selector(openUsageQuickLook), key: "u", to: menu)
        addItem(model.isShown ? "캐릭터 숨기기" : "캐릭터 표시", action: #selector(toggleShown), to: menu)
        let sizeMenu = NSMenu()
        for size in [80, 96, 128, 160, 192] {
            let item = addItem("\(size) pt", action: #selector(changeSize(_:)), to: sizeMenu)
            item.tag = size
            item.state = Int(model.size) == size ? .on : .off
        }
        let sizes = NSMenuItem(title: "캐릭터 크기", action: nil, keyEquivalent: "")
        sizes.submenu = sizeMenu
        menu.addItem(sizes)
        menu.addItem(.separator())
        if let timer = model.focusTimer, timer.deliveredAt == nil {
            let remaining = max(0, Int(ceil(timer.deadline.timeIntervalSinceNow / 60)))
            addItem("집중 타이머 취소 (약 \(remaining)분 남음)", action: #selector(cancelFocus), to: menu)
        } else { addItem("25분 집중 시작", action: #selector(startFocus), to: menu) }
        addItem("설정 및 리마인더…", action: #selector(openSettings), key: ",", to: menu)
        addItem("대시보드 열기…", action: #selector(openDashboard), key: "d", to: menu)
        addItem("기본 동작 확인…", action: #selector(openMotionReview), to: menu)
        menu.addItem(.separator())
        addItem("빌드정령 종료", action: #selector(quit), key: "q", to: menu)
    }

    @discardableResult private func addItem(_ title: String, action: Selector, key: String = "", to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    private func showCompanionMenu() {
        dismissUsageBubble()
        let menu = NSMenu()
        rebuildMenu(menu)
        let inputView = companion.interactionPanel.interactionView
        menu.popUp(positioning: nil, at: CGPoint(x: inputView.bounds.midX, y: inputView.bounds.midY),
                   in: inputView)
    }

    @objc private func toggleShown() { model.isShown.toggle() }
    @objc private func changeSize(_ sender: NSMenuItem) { model.size = Double(sender.tag) }
    @objc private func startFocus() { model.startFocus(minutes: 25) }
    @objc private func cancelFocus() { model.cancelFocus() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    @objc private func openMotionReview() {
        if motionReviewWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 670),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "빌드정령 기본 동작"
            window.delegate = self
            window.contentView = NSHostingView(rootView: MotionReviewView())
            window.isReleasedWhenClosed = false
            window.center()
            motionReviewWindow = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        motionReviewWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === motionReviewWindow { window.contentView = nil; motionReviewWindow = nil }
        if window === dashboardWindow { window.contentView = nil; dashboardWindow = nil }
        if window === quotaPanel {
            removeUsageBubbleMonitors()
            window.contentView = nil
            quotaPanel = nil
            quotaAnchorFrame = nil
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === quotaPanel {
            dismissUsageBubble()
        }
    }

    @objc private func openUsageQuickLook() {
        if quotaPanel != nil { dismissUsageBubble(); return }
        if quotaPanel == nil {
            let panel = UsageBubblePanel(contentRect: CGRect(origin: .zero, size: QuotaQuickView.size),
                styleMask: [.borderless], backing: .buffered, defer: false)
            panel.title = "빌드정령 사용량"
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.delegate = self
            panel.isReleasedWhenClosed = false
            panel.dismiss = { [weak self] in self?.dismissUsageBubble() }
            quotaPanel = panel
            positionUsageBubble()
            installUsageBubbleMonitors()
        }
        model.refreshQuota(force: true)
        NSApplication.shared.activate(ignoringOtherApps: true)
        quotaPanel?.makeKeyAndOrderFront(nil)
    }

    private func positionUsageBubble() {
        guard let panel = quotaPanel else { return }
        let placement = UsageBubblePlacement.place(characterFrame: companion.frame,
            visibleFrames: NSScreen.screens.map(\.visibleFrame), size: QuotaQuickView.size)
        panel.setFrame(placement.frame, display: true)
        panel.contentView = NSHostingView(rootView: QuotaQuickView(model: model,
            openDashboard: { [weak self] in self?.dismissUsageBubble(); self?.openDashboard() },
            tailOnLeft: placement.tailOnLeft, tailY: CGFloat(placement.tailYFromTop)))
        quotaAnchorFrame = companion.frame
    }

    private func dismissUsageBubble() { quotaPanel?.close() }

    private func installUsageBubbleMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        quotaLocalClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let panel = self.quotaPanel else { return }
                if event.window !== panel && event.window !== self.companion.interactionPanel {
                    self.dismissUsageBubble()
                }
            }
            return event // Never swallow another app/window's click.
        }
        quotaGlobalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in self?.dismissUsageBubble() }
        }
    }

    private func removeUsageBubbleMonitors() {
        if let quotaLocalClickMonitor { NSEvent.removeMonitor(quotaLocalClickMonitor) }
        if let quotaGlobalClickMonitor { NSEvent.removeMonitor(quotaGlobalClickMonitor) }
        quotaLocalClickMonitor = nil
        quotaGlobalClickMonitor = nil
    }

    @objc private func openDashboard() {
        if dashboardWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 960, height: 740),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "빌드정령 대시보드"
            window.minSize = NSSize(width: 880, height: 640)
            window.delegate = self
            window.contentView = NSHostingView(rootView: DashboardView(model: model, openSettings: { [weak self] in self?.openSettings() }))
            window.isReleasedWhenClosed = false
            window.center()
            dashboardWindow = window
        }
        model.refreshDashboard()
        model.refreshQuota(force: true)
        NSApplication.shared.activate(ignoringOtherApps: true)
        dashboardWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 460, height: 690),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "빌드정령 설정"
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func updateAlertPresentation() {
        if suspended { alertPanel?.orderOut(nil); return }
        guard let alert = model.currentAlert(isSuspended: suspended) else {
            alertPanel?.close()
            alertPanel = nil
            presentedAlertID = nil
            return
        }
        if presentedAlertID == alert.id, let alertPanel {
            if !alertPanel.isVisible { alertPanel.orderFrontRegardless() }
            return
        }
        presentAlert(alert)
    }

    private func presentAlert(_ alert: PendingAlert) {
        alertPanel?.close()
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 360, height: 150),
            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "빌드정령 알림"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView:
            VStack(alignment: .leading, spacing: 16) {
                ScrollView { Text(alert.message).frame(maxWidth: .infinity, alignment: .leading) }
                Button("확인") { [weak self] in self?.model.acknowledgeAlert(id: alert.id) }
            }.padding(20).frame(width: 360, height: 150))
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameTopLeftPoint(CGPoint(x: screen.maxX - 380, y: screen.maxY - 20))
        }
        alertPanel = panel
        presentedAlertID = alert.id
        panel.orderFrontRegardless()
    }

    @objc private func printDiagnostics() {
        let interaction = companion.interactionPanel
        let renderedBitmap = companion.spiritView.texture(from: companion.spiritScene, crop: companion.spiritView.bounds)
            .map { NSBitmapImageRep(cgImage: $0.cgImage()) }
        let values: [String: Any] = [
            "menuBarCreated": statusItem.button != nil,
            "menuItemCount": statusItem.menu?.items.count ?? 0,
            "panelVisible": companion.isVisible,
            "nonactivatingPanel": companion.styleMask.contains(.nonactivatingPanel),
            "transparent": !companion.isOpaque && companion.backgroundColor.alphaComponent == 0,
            "canBecomeKey": companion.canBecomeKey, "canBecomeMain": companion.canBecomeMain,
            "allSpaces": companion.collectionBehavior.contains(.canJoinAllSpaces),
            "size": companion.frame.width,
            "position": [companion.frame.origin.x, companion.frame.origin.y],
            "renderPaused": companion.spiritView.isPaused,
            "assetLoaded": companion.spiritScene.assetLoaded,
            "state": String(describing: companion.spiritScene.spiritState),
            "hookSocketListening": hookServer != nil,
            "hookSessionCount": model.eventStream.sessions.count,
            "dashboardEventCount": model.dashboard.events.count,
            "dashboardToolCount": model.dashboard.events.filter { $0.kind == .toolStarted }.count,
            "dashboardWorkingCount": model.dashboard.sessions.filter { $0.status == .working }.count,
            "dashboardUnknownCount": model.dashboard.sessions.filter { $0.status == .unknown }.count,
            "quotaBucketCount": model.quota?.buckets.count ?? 0,
            "quotaWeeklyRemaining": [model.generalQuotaBucket?.primary, model.generalQuotaBucket?.secondary].compactMap { $0 }.first { $0.windowDurationMins == 10080 }?.remainingPercent ?? -1,
            "quotaHasSuccessfulRead": model.quotaHasSuccessfulRead,
            "quotaHistoryCount": model.quotaHistory.count,
            "codexVersion": model.codexCLI?.version ?? "not detected",
            "reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "fullscreenLikely": fullscreenLikely,
            "appActive": NSApplication.shared.isActive,
            "pendingAlertCount": model.pendingAlertCount,
            "alertPanelVisible": alertPanel?.isVisible ?? false,
            "visualIgnoresMouseEvents": companion.ignoresMouseEvents,
            "interactionPanelVisible": interaction.isVisible,
            "interactionNonactivating": interaction.styleMask.contains(.nonactivatingPanel),
            "interactionCanBecomeKey": interaction.canBecomeKey,
            "interactionCanBecomeMain": interaction.canBecomeMain,
            "interactionAllSpaces": interaction.collectionBehavior.contains(.canJoinAllSpaces),
            "interactionIgnoresMouseEvents": interaction.ignoresMouseEvents,
            "interactionFrameWithinVisual": companion.frame.contains(interaction.frame),
            "interactionFrame": [interaction.frame.minX, interaction.frame.minY, interaction.frame.width, interaction.frame.height],
            "spriteViewAllowsTransparency": companion.spiritView.allowsTransparency,
            "spriteViewOpaque": companion.spiritView.isOpaque,
            "sceneBackgroundAlpha": companion.spiritScene.backgroundColor.alphaComponent,
            "renderedCornerAlpha": renderedBitmap?.colorAt(x: 1, y: 1)?.alphaComponent ?? -1,
            "renderedCenterAlpha": renderedBitmap.flatMap { $0.colorAt(x: $0.pixelsWide / 2, y: $0.pixelsHigh / 2)?.alphaComponent } ?? -1,
            "companionWindowNumber": companion.windowNumber,
            "interactionWindowNumber": interaction.windowNumber
        ]
        if let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            FileHandle.standardOutput.write(Data("BuildSpirit diagnostics: \(json)\n".utf8))
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeUsageBubbleMonitors()
        model.quotaTask?.cancel()
        completionPresentationTimer?.invalidate()
        greetingPresentationTimer?.invalidate()
        hookServer?.stop()
        heartbeat?.invalidate()
        companion.setRendering(active: false)
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }
}
