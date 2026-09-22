import AppKit
import SpriteKit
import SpiritCore

@MainActor
final class CompanionPanel: NSPanel {
    let spiritView: CompanionView
    let spiritScene: SpiritScene
    private(set) lazy var interactionPanel = InteractionPanel()
    private(set) lazy var speechPanel = SpeechPanel()
    private(set) lazy var flameTrailPanel = FlameTrailPanel()
    private(set) lazy var hammerFlightPanel = HammerFlightPanel()
    private var speechState: SpiritState?
    private var speechExpiry: Timer?
    private var speechIsCharge = false

    @objc private func expireSpeech() { dismissSpeech() }

    private func showSpeech(_ message: String?, charging: Bool = false) {
        speechExpiry?.invalidate()
        speechExpiry = nil
        speechIsCharge = charging
        speechPanel.speechView.message = message
        positionSpeech()
        if message != nil && renderingActive { speechPanel.orderFrontRegardless() }
        else { speechPanel.orderOut(nil) }
        // Long-running states should not leave dialogue pinned over the desktop.
        if message != nil && !charging {
            let timer = Timer(timeInterval: 3, target: self, selector: #selector(expireSpeech),
                              userInfo: nil, repeats: false)
            speechExpiry = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    private var renderingActive = false
    var positionChanged: ((CGPoint) -> Void)?
    var clicked: (() -> Void)?
    var transformed: (() -> Void)?
    var contextMenuRequested: (() -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(size: Double) {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        spiritView = CompanionView(frame: rect)
        spiritScene = SpiritScene(size: rect.size)
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        // The entire visual surface passes clicks through, independent of rendered alpha.
        ignoresMouseEvents = true
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        setAccessibilityElement(false)
        spiritView.allowsTransparency = true
        spiritView.preferredFramesPerSecond = 60
        spiritView.presentScene(spiritScene)
        spiritView.setAccessibilityElement(false)
        contentView = spiritView
        speechPanel.speechView.dismiss = { [weak self] in self?.dismissSpeech() }
        interactionPanel.interactionView.companion = self
        spiritScene.onTransform = { [weak self] in
            guard let self else { return }
            self.transformed?()
            self.showSpeech("으아아! 불꽃 충전!", charging: true)
        }
        spiritScene.onChargeEnded = { [weak self] in
            guard let self, self.speechIsCharge else { return }
            self.dismissSpeech()
        }
        spiritScene.onHammerFlight = { [weak self] flight in
            guard let self else { return }
            guard self.renderingActive, let flight else {
                self.hammerFlightPanel.clear()
                return
            }
            let viewPoint = self.spiritScene.convertPoint(toView: flight.position)
            let windowPoint = self.spiritView.convert(viewPoint, to: nil)
            let screenPoint = self.convertPoint(toScreen: windowPoint)
            self.hammerFlightPanel.show(flight, at: screenPoint, above: self)
        }
        syncInteractionFrame()
    }

    func resize(to size: Double) {
        interactionPanel.interactionView.cancelDrag()
        setContentSize(CGSize(width: size, height: size))
        syncInteractionFrame()
    }

    private func syncInteractionFrame() {
        interactionPanel.setFrame(CompanionGeometry.interactionFrame(
            visualOrigin: frame.origin, size: frame.width), display: true)
        positionSpeech()
        let visible = screen?.visibleFrame
            ?? NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        if let visible {
            let scale = max(0.1, spiritScene.characterScale)
            let grip = CGPoint(x: frame.midX - 8 * scale, y: frame.minY + frame.height * 0.46)
            let fromRight = visible.maxX - grip.x >= grip.x - visible.minX
            let endX = fromRight ? visible.maxX + 50 : visible.minX - 50
            let endY = min(visible.maxY - 24, grip.y + 65 * scale)
            let overhead = max(0, visible.maxY - frame.minY - frame.height * 0.65 - 28 * scale)
            spiritScene.hammerTossHeightScale = min(1, max(0, overhead / (55 * scale)))
            spiritScene.hammerRecallOffset = CGPoint(x: (endX - grip.x) / scale,
                                                     y: (endY - grip.y) / scale)
        }
    }

    func move(to point: CGPoint) {
        spiritScene.cancelHammerTrick()
        setFrameOrigin(point)
        syncInteractionFrame()
    }

    func correctPosition(_ origin: CGPoint? = nil) {
        guard let primary = NSScreen.screens.first else { return }
        let point = CompanionGeometry.safeOrigin(origin ?? frame.origin, size: frame.width,
            visibleFrames: NSScreen.screens.map(\.visibleFrame), primaryFrame: primary.visibleFrame)
        move(to: point)
        positionChanged?(point)
    }

    func updateSpeech(state: SpiritState) {
        guard speechState != state else { return }
        speechState = state
        showSpeech(SpeechPanel.message(for: state))
    }

    @discardableResult
    func dismissSpeech() -> Bool {
        speechExpiry?.invalidate()
        speechExpiry = nil
        speechIsCharge = false
        guard speechPanel.speechView.message != nil else { return false }
        speechPanel.speechView.message = nil
        speechPanel.orderOut(nil)
        return true
    }

    private func positionSpeech() {
        let bodyBounds = spiritScene.speechAnchorBounds
        let lower = spiritView.convert(spiritScene.convertPoint(toView: bodyBounds.origin), to: nil)
        let upper = spiritView.convert(spiritScene.convertPoint(toView: CGPoint(x: bodyBounds.maxX, y: bodyBounds.maxY)), to: nil)
        let anchor = convertToScreen(CGRect(x: min(lower.x, upper.x), y: min(lower.y, upper.y),
                                            width: abs(upper.x - lower.x), height: abs(upper.y - lower.y)))
        let placement = UsageBubblePlacement.place(characterFrame: anchor,
            visibleFrames: NSScreen.screens.map(\.visibleFrame), size: SpeechPanel.size)
        speechPanel.setFrame(placement.frame, display: true)
        speechPanel.speechView.tailOnLeft = placement.tailOnLeft
        speechPanel.speechView.tailY = placement.tailYFromTop
        speechPanel.speechView.needsDisplay = true
    }

    func setRendering(active: Bool) {
        renderingActive = active
        spiritView.isPaused = !active
        if active {
            syncInteractionFrame()
            orderFrontRegardless()
            interactionPanel.orderFrontRegardless()
            if speechPanel.speechView.message != nil { speechPanel.orderFrontRegardless() }
        } else {
            spiritScene.setProviderLabelVisible(false)
            spiritScene.cancelHammerTrick()
            hammerFlightPanel.clear()
            interactionPanel.interactionView.cancelDrag()
            flameTrailPanel.clear()
            interactionPanel.orderOut(nil)
            speechPanel.orderOut(nil)
            orderOut(nil)
        }
    }
}

@MainActor
final class CompanionView: SKView {
    override var isOpaque: Bool { false }
}

@MainActor
final class InteractionPanel: NSPanel {
    let interactionView = InteractionView(frame: .zero)
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "빌드정령 캐릭터 입력"
        // A faint fill makes the deliberate rig-sized input target reliable for WindowServer.
        // This includes small transparent gaps between parts; outer window corners pass through.
        backgroundColor = NSColor.black.withAlphaComponent(0.01)
        isOpaque = false
        ignoresMouseEvents = false
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        interactionView.setAccessibilityElement(true)
        interactionView.setAccessibilityRole(.button)
        interactionView.setAccessibilityLabel("빌드정령 캐릭터. 드래그로 이동, 반복 클릭 또는 길게 눌러 불꽃 충전, 클릭으로 요약 확인, 우클릭으로 메뉴 열기")
        contentView = interactionView
    }
}

@MainActor
final class InteractionView: NSView {
    weak var companion: CompanionPanel?
    private var dragStart: CGPoint?
    private var windowStart: CGPoint = .zero
    private var didDrag = false
    private var pressedHammer = false
    private var previousDragPoint: CGPoint?
    private var previousDragTime: TimeInterval = 0
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTrackingArea = area
        if let window, window.isVisible {
            companion?.spiritScene.setProviderLabelVisible(bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)))
        }
    }

    override func mouseEntered(with event: NSEvent) { companion?.spiritScene.setProviderLabelVisible(true) }
    override func mouseExited(with event: NSEvent) { companion?.spiritScene.setProviderLabelVisible(false) }

    override func mouseDown(with event: NSEvent) {
        dragStart = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        windowStart = companion?.frame.origin ?? .zero
        didDrag = false
        previousDragPoint = dragStart
        previousDragTime = event.timestamp
        if let panel = companion {
            let screenPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            let point = panel.spiritView.convert(panel.convertPoint(fromScreen: screenPoint), from: nil)
            pressedHammer = panel.spiritScene.hammerContains(panel.spiritScene.convertPoint(fromView: point))
                || panel.spiritScene.isHammerTrickPlaying
            if !pressedHammer { panel.spiritScene.beginPress() }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let mouse = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        if pressedHammer, let panel = companion {
            if hypot(mouse.x - start.x, mouse.y - start.y) > 3 { didDrag = true }
            if didDrag {
                panel.spiritScene.pullHammer(progress: Double((start.x - mouse.x) / max(18, panel.frame.width * 0.18)))
            }
            return
        }
        if !didDrag && hypot(mouse.x - start.x, mouse.y - start.y) > 3 {
            didDrag = true
            _ = companion?.spiritScene.endPress(registerTap: false)
            companion?.spiritScene.setDragging(true)
        }
        guard didDrag, let panel = companion else { return }
        let elapsed = max(1.0 / 120, min(0.1, event.timestamp - previousDragTime))
        let previous = previousDragPoint ?? mouse
        let velocity = CGPoint(x: max(-1800, min(1800, (mouse.x - previous.x) / elapsed)),
                               y: max(-1800, min(1800, (mouse.y - previous.y) / elapsed)))
        let oldCenter = CGPoint(x: panel.frame.midX, y: panel.frame.minY + panel.frame.height * 0.46)
        panel.move(to: CGPoint(x: windowStart.x + mouse.x - start.x,
                              y: windowStart.y + mouse.y - start.y))
        panel.spiritScene.setDragVelocity(x: Double(velocity.x), y: Double(velocity.y))
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.minY + panel.frame.height * 0.46)
        panel.flameTrailPanel.emit(from: oldCenter, to: center, velocity: velocity,
                                  texture: panel.spiritScene.effectTexture, companion: panel)
        previousDragPoint = mouse
        previousDragTime = event.timestamp
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil, let panel = companion else { return }
        let dragged = didDrag
        dragStart = nil
        previousDragPoint = nil
        if pressedHammer && dragged {
            pressedHammer = false
            panel.spiritScene.releaseHammerPull()
            return
        }
        panel.spiritScene.setDragVelocity(x: 0, y: 0)
        panel.spiritScene.setDragging(false)
        let wasHammer = pressedHammer
        pressedHammer = false
        let charged = panel.spiritScene.endPress(registerTap: !dragged && !wasHammer)
        if !dragged && wasHammer {
            if event.clickCount == 2 { _ = panel.spiritScene.requestHammerToss() }
            return
        }
        if dragged { panel.correctPosition() }
        if !dragged && !charged && !panel.dismissSpeech() { panel.clicked?() }
    }

    override func rightMouseDown(with event: NSEvent) {
        companion?.contextMenuRequested?()
    }

    func cancelDrag() {
        dragStart = nil
        didDrag = false
        pressedHammer = false
        previousDragPoint = nil
        companion?.spiritScene.cancelInteractions()
    }
}


/// A small nonactivating speech window keeps dialogue readable outside the sprite bounds.
@MainActor
final class SpeechPanel: NSPanel {
    static let size = CGSize(width: 188, height: 44)
    static func message(for state: SpiritState) -> String? {
        switch state {
        case .idle: return nil
        case .working: return "열심히 만드는 중…"
        case .attention: return "잠깐! 나 좀 봐줘"
        case .completed: return "다 만들었어!"
        case .greeting: return "안녕! 같이 만들자"
        case .error: return "앗, 연결을 확인해 줘"
        case .sleeping: return "잠깐 쉬고 올게…"
        }
    }
    let speechView = SpiritSpeechView(frame: CGRect(origin: .zero, size: SpeechPanel.size))
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: CGRect(origin: .zero, size: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "빌드정령 말풍선"
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        contentView = speechView
    }
}

@MainActor
final class SpiritSpeechView: NSView {
    var message: String? {
        didSet {
            dialogueImage = message.map(Self.renderDialogue)
            needsDisplay = true
            setAccessibilityLabel(message.map { "\($0). 눌러서 말풍선 닫기" })
        }
    }
    private var dialogueImage: NSImage?

    // This pixel font reports a zero global glyph bounding box to CoreText.
    // Rasterize via point drawing, as PixelText and the spirit nameplate do,
    // instead of relying on AppKit's rectangle-based text layout on screen.
    private static func renderDialogue(_ message: String) -> NSImage {
        let font = NSFont(name: "NeoDunggeunmo-Regular", size: 15)
            ?? .systemFont(ofSize: 14, weight: .semibold)
        let text = NSAttributedString(string: message, attributes: [
            .font: font,
            .foregroundColor: Self.ink
        ])
        let extent = text.size()
        let image = NSImage(size: CGSize(width: max(1, ceil(extent.width) + 4),
                                        height: max(1, ceil(extent.height) + 4)))
        image.lockFocus()
        text.draw(at: CGPoint(x: 2, y: 2))
        image.unlockFocus()
        return image
    }

    var tailOnLeft = true
    var tailY: Double = 35
    var dismiss: (() -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func accessibilityPerformPress() -> Bool { dismiss?(); return true }
    override func mouseUp(with event: NSEvent) { dismiss?() }

    static let ink = NSColor(calibratedRed: 0.29, green: 0.18, blue: 0.11, alpha: 1)
    static let fill = NSColor(calibratedRed: 1, green: 0.95, blue: 0.82, alpha: 1)
    static let outline = NSColor(calibratedRed: 0.46, green: 0.32, blue: 0.22, alpha: 1)

    static func bubblePath(size: CGSize, tailOnLeft: Bool, tailY: CGFloat) -> NSBezierPath {
        let width = size.width
        let height = size.height
        let tail = min(max(CGFloat(tailY), 17), height - 17)
        // One continuous outline keeps the small tail joined cleanly to the rounded body.
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: tailOnLeft ? x : width - x, y: y)
        }
        let path = NSBezierPath()
        let corner: CGFloat = 8
        let control = corner * 0.55228475
        let left: CGFloat = 10
        let right = width - 10
        let top: CGFloat = 2
        let bottom = height - 2
        path.move(to: point(left + corner, top))
        path.line(to: point(right - corner, top))
        path.curve(to: point(right, top + corner),
                   controlPoint1: point(right - corner + control, top),
                   controlPoint2: point(right, top + corner - control))
        path.line(to: point(right, bottom - corner))
        path.curve(to: point(right - corner, bottom),
                   controlPoint1: point(right, bottom - corner + control),
                   controlPoint2: point(right - corner + control, bottom))
        path.line(to: point(left + corner, bottom))
        path.curve(to: point(left, bottom - corner),
                   controlPoint1: point(left + corner - control, bottom),
                   controlPoint2: point(left, bottom - corner + control))
        path.line(to: point(left, tail + 5))
        path.line(to: point(3.5, tail + 0.8))
        path.curve(to: point(3.5, tail - 0.8),
                   controlPoint1: point(2.7, tail + 0.3),
                   controlPoint2: point(2.7, tail - 0.3))
        path.line(to: point(left, tail - 5))
        path.line(to: point(left, top + corner))
        path.curve(to: point(left + corner, top),
                   controlPoint1: point(left, top + corner - control),
                   controlPoint2: point(left + corner - control, top))
        path.close()
        return path
    }

    override func draw(_ dirtyRect: NSRect) {
        guard message != nil else { return }
        let width = bounds.width
        let height = bounds.height
        let path = Self.bubblePath(size: bounds.size, tailOnLeft: tailOnLeft, tailY: tailY)
        Self.fill.setFill()
        path.fill()
        Self.outline.setStroke()
        path.lineWidth = 1.5
        path.lineJoinStyle = .round
        path.stroke()
        if let dialogueImage {
            let scale = min(1, (width - 30) / dialogueImage.size.width)
            let size = CGSize(width: dialogueImage.size.width * scale,
                              height: dialogueImage.size.height * scale)
            dialogueImage.draw(in: CGRect(x: (width - size.width) / 2,
                                           y: (height - size.height) / 2,
                                           width: size.width, height: size.height),
                               from: .zero, operation: .sourceOver, fraction: 1,
                               respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
        }

    }
}


/// Screen-space embers retain their position while the companion window moves.
@MainActor
final class FlameTrailPanel: NSPanel {
    private let trailView = CompanionView(frame: CGRect(x: 0, y: 0, width: 384, height: 384))
    private let trailScene = FlameTrailScene(size: CGSize(width: 384, height: 384))
    private var distanceToNextEmber: CGFloat = 4
    private var expiryTimer: Timer?

    @objc private func expireTrail() { clear() }

    private func renewExpiry() {
        // SpriteKit may stop delivering frames to this nonactivating overlay.
        // Its longest particle lasts 0.85s; wall-clock cleanup must not depend on rendering.
        if let expiryTimer {
            expiryTimer.fireDate = Date().addingTimeInterval(1)
        } else {
            let timer = Timer(timeInterval: 1, target: self, selector: #selector(expireTrail),
                              userInfo: nil, repeats: false)
            expiryTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: trailView.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        ignoresMouseEvents = true
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        trailView.allowsTransparency = true
        trailView.preferredFramesPerSecond = 30
        trailView.isPaused = true
        trailView.presentScene(trailScene)
        contentView = trailView
        trailScene.finished = { [weak self] in self?.clear() }
    }

    func emit(from start: CGPoint, to end: CGPoint, velocity: CGPoint,
              texture: SKTexture, companion: CompanionPanel) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            clear()
            return
        }
        let origin = CGPoint(x: end.x - 192, y: end.y - 192)
        let shift = CGPoint(x: frame.minX - origin.x, y: frame.minY - origin.y)
        for ember in trailScene.children {
            ember.position.x += shift.x
            ember.position.y += shift.y
        }
        setFrameOrigin(origin)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        let speed = hypot(velocity.x, velocity.y)
        guard distance > 0.001, speed > 20 else { return }
        let unit = CGPoint(x: dx / distance, y: dy / distance)
        let normal = CGPoint(x: -unit.y, y: unit.x)
        let characterScale = companion.frame.width / 128
        let speedFactor = min(1, speed / 1200)
        var traveled: CGFloat = 0
        var emitted = 0
        // Carry the remaining spacing across input events so a high mouse polling
        // rate does not turn a slow drag into a dense stream of identical flames.
        while traveled + distanceToNextEmber <= distance, emitted < 96 {
            traveled += distanceToNextEmber
            distanceToNextEmber = CGFloat.random(in: 5...13) * characterScale * (1 - 0.22 * speedFactor)
            let spread = CGFloat.random(in: -1...1)
            let edgeDepth = sqrt(max(0, 1 - spread * spread))
            let radius = 16 * characterScale
            let position = CGPoint(
                x: start.x + unit.x * traveled - unit.x * radius * edgeDepth
                    + normal.x * radius * spread - origin.x,
                y: start.y + unit.y * traveled - unit.y * radius * edgeDepth
                    + normal.y * radius * spread - origin.y)
            let ember = SKSpriteNode(texture: emitted == 0 ? texture : companion.spiritScene.effectTexture)
            // Mostly small embers, with an occasional broader tongue of flame.
            let larger = Int.random(in: 0..<5) == 0
            let side = CGFloat.random(in: larger ? 5...8 : 1.8...4.2) * characterScale
            ember.size = CGSize(width: side, height: side * CGFloat.random(in: 1.15...2.1))
            ember.position = position
            ember.color = NSColor(calibratedRed: 1, green: CGFloat.random(in: 0.48...0.85),
                                  blue: CGFloat.random(in: 0.04...0.18), alpha: 1)
            ember.shader = companion.spiritScene.effectShader
            ember.colorBlendFactor = ember.shader == nil ? 0.35 : 0
            let angle = atan2(unit.y, unit.x) + .pi / 2 + CGFloat.random(in: -0.45...0.45)
            let launchAngle = atan2(sin(angle), cos(angle))
            ember.zRotation = launchAngle
            let initialAlpha = CGFloat.random(in: 0.48...0.92)
            ember.alpha = initialAlpha
            trailScene.addChild(ember)
            let lifetime = Double.random(in: larger ? 0.52...0.85 : 0.3...0.66)
            let inertia = CGFloat.random(in: 0.012...0.035)
            let lateral = CGFloat.random(in: -13...13) * characterScale
            let lift = CGFloat.random(in: 15...36) * characterScale
            let curl = CGFloat.random(in: -8...8) * characterScale
            let flickerPhase = CGFloat.random(in: 0...(2 * .pi))
            var lastOffset = CGPoint.zero
            // Apply relative deltas, preserving screen-space rebasing when the
            // transparent trail window moves during an unfinished animation.
            let motion = SKAction.customAction(withDuration: lifetime) { node, elapsed in
                let t = min(1, CGFloat(elapsed) / CGFloat(lifetime))
                let drag = 1 - pow(1 - t, 2)
                let sway = lateral * t + curl * sin(t * .pi)
                let offset = CGPoint(x: -velocity.x * inertia * drag + normal.x * sway,
                                     y: -velocity.y * inertia * drag + normal.y * sway + lift * t * t)
                node.position.x += offset.x - lastOffset.x
                node.position.y += offset.y - lastOffset.y
                lastOffset = offset
                node.zRotation = launchAngle * (1 - t * 0.75) + sin(t * .pi * 2 + flickerPhase) * 0.14
                node.alpha = initialAlpha * pow(1 - t, 1.25) * (0.92 + 0.08 * sin(t * 12 + flickerPhase))
                node.setScale(max(0.12, 1 - t * 0.88))
            }
            ember.run(.sequence([motion, .removeFromParent()]))
            emitted += 1
        }
        distanceToNextEmber -= min(distance - traveled, distanceToNextEmber)
        if emitted > 0 { renewExpiry() }
        guard !trailScene.children.isEmpty else { return }
        // Keep the bounded trail inexpensive, even during a very rapid drag.
        while trailScene.children.count > 96 { trailScene.children.first?.removeFromParent() }
        trailView.isPaused = false
        order(.below, relativeTo: companion.windowNumber)
    }

    func clear() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        distanceToNextEmber = 4
        trailScene.removeAllChildren()
        trailView.isPaused = true
        orderOut(nil)
    }
}

@MainActor
private final class FlameTrailScene: SKScene {
    var finished: (() -> Void)?
    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didEvaluateActions() {
        if children.isEmpty { finished?() }
    }
}


/// The returning hammer can cross the desktop without enlarging the input surface.
@MainActor
final class HammerFlightPanel: NSPanel {
    private let flightView = CompanionView(frame: .zero)
    private let flightScene = SKScene(size: CGSize(width: 128, height: 128))
    private let sprite = SKSpriteNode()
    private let trailSprites = (0..<3).map { _ in SKSpriteNode() }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 128, height: 128),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "빌드정령 날아오는 망치"
        backgroundColor = .clear
        isOpaque = false
        ignoresMouseEvents = true
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        setAccessibilityElement(false)
        flightView.allowsTransparency = true
        flightView.preferredFramesPerSecond = 60
        flightView.setAccessibilityElement(false)
        flightScene.backgroundColor = .clear
        flightScene.scaleMode = .resizeFill
        sprite.name = "flyingHammer"
        sprite.zPosition = 1
        flightScene.addChild(sprite)
        flightView.presentScene(flightScene)
        contentView = flightView
        flightView.isPaused = true
    }

    func show(_ flight: HammerFlightFrame, at screenPoint: CGPoint, above companion: CompanionPanel) {
        sprite.texture = flight.texture
        sprite.size = flight.size
        sprite.anchorPoint = flight.anchorPoint
        sprite.zRotation = flight.rotation
        sprite.alpha = flight.opacity
        sprite.position = screenPoint
        var bounds = sprite.calculateAccumulatedFrame()
        for (index, ghost) in trailSprites.enumerated() {
            guard index < flight.trail.count else {
                ghost.removeFromParent()
                ghost.texture = nil
                continue
            }
            let sample = flight.trail[index]
            let viewPoint = companion.spiritScene.convertPoint(toView: sample.position)
            let windowPoint = companion.spiritView.convert(viewPoint, to: nil)
            ghost.position = companion.convertPoint(toScreen: windowPoint)
            ghost.texture = flight.texture
            ghost.size = sample.size
            ghost.anchorPoint = flight.anchorPoint
            ghost.zRotation = sample.rotation
            ghost.alpha = min(0.20, max(0, sample.opacity))
            ghost.name = "hammerTrail\(index)"
            ghost.zPosition = -CGFloat(index + 1)
            if ghost.parent == nil { flightScene.addChild(ghost) }
            bounds = bounds.union(ghost.calculateAccumulatedFrame())
        }
        // Include each rotated silhouette; a long trail can extend beyond the grip window.
        bounds = bounds.insetBy(dx: -4, dy: -4)
        let origin = CGPoint(x: floor(bounds.minX), y: floor(bounds.minY))
        let size = CGSize(width: max(64, ceil(bounds.maxX) - origin.x),
                          height: max(64, ceil(bounds.maxY) - origin.y))
        if frame.size != size {
            setFrame(CGRect(origin: origin, size: size), display: false)
            flightScene.size = size
        } else {
            setFrameOrigin(origin)
        }
        for node in [sprite] + trailSprites where node.parent != nil {
            node.position = CGPoint(x: node.position.x - origin.x, y: node.position.y - origin.y)
        }
        flightView.isPaused = false
        order(.above, relativeTo: companion.windowNumber)
    }

    func clear() {
        sprite.texture = nil
        for ghost in trailSprites {
            ghost.removeFromParent()
            ghost.texture = nil
            ghost.alpha = 0
        }
        flightView.isPaused = true
        orderOut(nil)
    }
}
