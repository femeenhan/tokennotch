import AppKit
import Combine
import SpiritCore
import UniformTypeIdentifiers

@MainActor
final class CompanionModel: ObservableObject {
    private let defaults = UserDefaults.standard
    @Published var size: Double { didSet { defaults.set(size, forKey: "spiritSize"); onAppearanceChange?() } }
    @Published var isShown: Bool { didSet { defaults.set(isShown, forKey: "spiritShown"); onAppearanceChange?() } }
    @Published var hideInFullScreen: Bool { didSet { defaults.set(hideInFullScreen, forKey: "hideInFullScreen"); onAppearanceChange?() } }
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: "soundEnabled") } }
    @Published private var alerts: LocalAlertState
    var focusTimer: FocusTimer? { alerts.focusTimer }
    var reminders: [Reminder] { alerts.reminders }
    var pendingAlertCount: Int { alerts.pending.count }
    @Published var errorMessage: String?
    @Published private(set) var providerStreams = ProviderSpiritStreams()
    var eventStream: SpiritEventStream { stream(for: .codex) }
    @Published var selectedProvider: SpiritProvider = .codex
    @Published private(set) var visibleProviders: [SpiritProvider] = [.codex]
    @Published private(set) var autoConnectClaude = false
    @Published private(set) var claudeConnectionStatus = "Claude Code 확인 중"
    @Published private(set) var claudeExecutableDetected = false
    private var claudeRevealPending = false
    @Published private var providerSizes: [String: Double] = [:]

    func stream(for provider: SpiritProvider) -> SpiritEventStream { providerStreams.stream(for: provider) }

    @discardableResult
    func setProviderVisible(_ provider: SpiritProvider, visible: Bool) -> Bool {
        if visible && !visibleProviders.contains(provider) {
            guard visibleProviders.count < 3 else {
                errorMessage = "정령은 최대 3개까지 표시할 수 있습니다. 다른 정령을 먼저 숨겨 주세요."
                return false
            }
            visibleProviders.append(provider)
        } else if !visible { visibleProviders.removeAll { $0 == provider } }
        defaults.set(visibleProviders.map(\.rawValue), forKey: "visibleSpiritProviders")
        errorMessage = nil
        onAppearanceChange?()
        return true
    }

    func size(for provider: SpiritProvider) -> Double {
        provider == .codex ? size : providerSizes[provider.rawValue] ?? 128
    }

    func setSize(_ value: Double, for provider: SpiritProvider) {
        let clamped = CompanionGeometry.clampedSize(value)
        if provider == .codex { size = clamped }
        else {
            providerSizes[provider.rawValue] = clamped
            defaults.set(providerSizes, forKey: "providerSpiritSizes")
            onAppearanceChange?()
        }
    }

    func providerStatus(for provider: SpiritProvider) -> String {
        let stream = stream(for: provider)
        guard !stream.sessions.isEmpty else { return "상태 미관측 · CLI 연결과 이벤트 수신을 확인하세요." }
        let working = stream.sessions.values.filter { $0.status == .working }.count
        let attention = stream.sessions.values.filter { $0.status == .attention }.count
        if working > 0 || attention > 0 { return "작업 중 \(working) · 확인 필요 \(attention)" }
        if stream.sessions.values.contains(where: { $0.status == .unknown }) { return "상태 확인 불가 · 새 이벤트를 기다립니다." }
        return SpiritPresentation(state: stream.state).label + " · 마지막 관측 상태"
    }

    func savedOrigin(for provider: SpiritProvider) -> CGPoint? {
        if provider == .codex { return savedOrigin }
        guard let point = defaults.array(forKey: "spiritOrigin.\(provider.rawValue)") as? [Double], point.count == 2 else { return nil }
        return CGPoint(x: point[0], y: point[1])
    }
    func saveOrigin(_ point: CGPoint, for provider: SpiritProvider) {
        if provider == .codex { saveOrigin(point) }
        else { defaults.set([point.x, point.y], forKey: "spiritOrigin.\(provider.rawValue)") }
    }
    @Published var hookStatus = "연결을 준비하고 있습니다."
    @Published var codexCLI: CodexCLI?
    @Published var dashboard = DashboardSnapshot()
    @Published var dashboardError: String?
    @Published var dashboardLoading = true
    @Published var usageStatus = "수집 안 함"
    @Published var selectedUsageFilename: String?
    var dashboardStore: DashboardStore?
    var dashboardWork: Task<Void, Never>?
    var usageReader: UsageFileReader?
    var usageToken = UUID()
    var usageReading = false
    var pendingUsage: [String: UsageRecord] = [:]
    var lastUsagePoll = Date.distantPast
    @Published var quota: QuotaSnapshot?
    @Published var quotaHistory: [QuotaSnapshot] = []
    @Published var quotaRefreshing = false
    @Published var quotaHasSuccessfulRead = false
    @Published var quotaError: String?
    @Published var accountUsage: CodexAccountUsage?
    @Published var accountUsageError: String?
    @Published var accountUsageDaily: [CodexDailyUsageBucket] = []
    @Published var quotaHistoryError: String?
    @Published var claudeTokenUsage: ClaudeTokenUsage?
    @Published var claudeRateLimits: ClaudeRateLimits?
    var claudeUsageReader = ClaudeTranscriptUsageReader(
        root: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects"),
        calendar: .current)
    var claudeUsageReading = false
    var claudeUsageLastRead = Date.distantPast
    var claudeRateLimitsURL = ClaudeRateLimits.defaultURL
    var claudeRateLimitsModified: Date?
    @Published var quotaMonitoringEnabled = UserDefaults.standard.object(forKey: "quotaMonitoringEnabled") as? Bool ?? true {
        didSet { defaults.set(quotaMonitoringEnabled, forKey: "quotaMonitoringEnabled") }
    }
    var quotaClient: CodexQuotaClient?
    var quotaHistoryStore: QuotaHistoryStore?
    var quotaHistoryWork: Task<Void, Never>?
    var quotaTask: Task<Void, Never>?
    var quotaLastAttempt = Date.distantPast
    var quotaAutomaticAllowed = true
    var quotaExecutableOverride: URL?
    var spiritState: SpiritState { eventStream.state }

    func receiveHook(_ event: SpiritEvent) {
        if event.provider == SpiritProvider.claude.rawValue && claudeRevealPending &&
           (visibleProviders.contains(.claude) || visibleProviders.count < 3) {
            claudeRevealPending = false
            defaults.set(false, forKey: "claudeRevealPending")
            _ = setProviderVisible(.claude, visible: true)
            selectedProvider = .claude
        }
        providerStreams.receive(event)
        hookStatus = "\(SpiritProvider(rawValue: event.provider)?.displayName ?? event.provider) CLI 이벤트를 수신했습니다."
        onAppearanceChange?()
        performDashboardOperation { store in try await store.record(event) }
    }

    func finishCompletionPresentation(id: UUID, provider: SpiritProvider = .codex) {
        providerStreams.finishCompletionPresentation(id: id, provider: provider)
        onAppearanceChange?()
    }

    func finishGreetingPresentation(id: UUID, provider: SpiritProvider = .codex) {
        providerStreams.finishGreetingPresentation(id: id, provider: provider)
        onAppearanceChange?()
    }

    func detectCodex() async {
        codexCLI = await Task.detached { CodexCLI.detect() }.value
        if let executable = quotaExecutableOverride ?? codexCLI?.executable {
            quotaClient = CodexQuotaClient(executableURL: executable)
            refreshQuota(force: true)
        } else {
            quotaError = "Codex CLI를 찾지 못했습니다. 설정에서 연결을 확인하세요."
        }
    }

    func refreshClaudeConnection(bridgeURL: URL) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map {
            URL(fileURLWithPath: String($0)).appendingPathComponent("claude").path
        }
        let candidates = [home.appendingPathComponent(".local/bin/claude").path,
                          "/opt/homebrew/bin/claude", "/usr/local/bin/claude"] + paths
        claudeExecutableDetected = candidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
        guard claudeExecutableDetected else {
            claudeConnectionStatus = "Claude Code CLI를 찾지 못했습니다."
            return
        }
        let file = ProviderHookInstaller.configurationURL(for: .claude)
        let command = ProviderHookInstaller.command(bridgeURL: bridgeURL, provider: .claude)
        do {
            let installed = try (try? Data(contentsOf: file)).map {
                try ProviderHookInstaller.isInstalled(in: $0, command: command, provider: .claude)
            } ?? false
            if autoConnectClaude && !installed {
                guard FileManager.default.isExecutableFile(atPath: bridgeURL.path) else {
                    claudeConnectionStatus = "연결 브리지를 찾지 못했습니다. 앱을 다시 빌드해 주세요."
                    return
                }
                try ProviderHookInstaller.write(to: file, command: command, installing: true, provider: .claude)
            }
            // Rate limits are only exposed to statusLine commands; never replace a user's own statusLine.
            let statusCommand = ClaudeStatusLineInstaller.command(bridgeURL: bridgeURL)
            var statusState = try (try? Data(contentsOf: file)).map {
                try ClaudeStatusLineInstaller.state(in: $0, command: statusCommand)
            } ?? .absent
            if autoConnectClaude && statusState == .absent && FileManager.default.isExecutableFile(atPath: bridgeURL.path) {
                try ClaudeStatusLineInstaller.write(to: file, command: statusCommand, installing: true)
                statusState = .installed
            }
            claudeConnectionStatus = installed || autoConnectClaude ? "Claude Code 연결됨 · 다음 작업부터 반응합니다." : "Claude Code 감지됨 · 연결을 켜 주세요."
            if autoConnectClaude && statusState == .foreign {
                claudeConnectionStatus += " 사용 중인 statusLine이 있어 한도는 받지 않습니다."
            }
        } catch {
            claudeConnectionStatus = "Claude 연결 설정을 확인하거나 저장하지 못했습니다."
        }
    }

    func setClaudeAutoConnection(_ enabled: Bool, bridgeURL: URL) {
        if enabled && !claudeExecutableDetected { refreshClaudeConnection(bridgeURL: bridgeURL) }
        guard !enabled || claudeExecutableDetected else { return }
        let file = ProviderHookInstaller.configurationURL(for: .claude)
        let command = ProviderHookInstaller.command(bridgeURL: bridgeURL, provider: .claude)
        do {
            try ProviderHookInstaller.write(to: file, command: command, installing: enabled, provider: .claude)
            if !enabled {
                try ClaudeStatusLineInstaller.write(to: file, command: ClaudeStatusLineInstaller.command(bridgeURL: bridgeURL), installing: false)
            }
            autoConnectClaude = enabled
            defaults.set(enabled, forKey: "autoConnectClaude")
            claudeRevealPending = enabled && !visibleProviders.contains(.claude)
            defaults.set(claudeRevealPending, forKey: "claudeRevealPending")
            refreshClaudeConnection(bridgeURL: bridgeURL)
        } catch {
            claudeConnectionStatus = "연결 설정을 저장하지 못했습니다. 파일과 폴더 권한을 확인해 주세요."
        }
    }
    var latestAlert: String? { alerts.pending.first?.message }
    var onAppearanceChange: (() -> Void)?
    var onAlertChange: (() -> Void)?

    init() {
        defaults.register(defaults: ["spiritSize": 128.0, "spiritShown": true,
                                     "hideInFullScreen": true, "soundEnabled": false])
        size = CompanionGeometry.clampedSize(defaults.double(forKey: "spiritSize"))
        isShown = defaults.bool(forKey: "spiritShown")
        hideInFullScreen = defaults.bool(forKey: "hideInFullScreen")
        soundEnabled = defaults.bool(forKey: "soundEnabled")
        autoConnectClaude = defaults.bool(forKey: "autoConnectClaude")
        claudeRevealPending = defaults.bool(forKey: "claudeRevealPending")
        if let stored = defaults.stringArray(forKey: "visibleSpiritProviders") {
            visibleProviders = ProviderSelection.normalized(stored.compactMap(SpiritProvider.init(rawValue:)))
        }
        providerSizes = defaults.dictionary(forKey: "providerSpiritSizes") as? [String: Double] ?? [:]
        if let index = CommandLine.arguments.firstIndex(of: "--providers"), index + 1 < CommandLine.arguments.count {
            visibleProviders = ProviderSelection.normalized(CommandLine.arguments[index + 1].split(separator: ",").compactMap { SpiritProvider(rawValue: String($0)) })
        }
        if let data = defaults.data(forKey: "localAlertState"),
           let restored = try? JSONDecoder().decode(LocalAlertState.self, from: data) {
            alerts = restored
        } else {
            let timer = defaults.data(forKey: "focusTimer").flatMap { try? JSONDecoder().decode(FocusTimer.self, from: $0) }
            let reminders = defaults.data(forKey: "reminders").flatMap { try? JSONDecoder().decode([Reminder].self, from: $0) } ?? []
            // Old builds did not record acknowledgment. Do not replay delivered history during migration.
            alerts = LocalAlertState(focusTimer: timer, reminders: reminders.filter { $0.deliveredAt == nil })
            persistAlerts()
            defaults.removeObject(forKey: "focusTimer")
            defaults.removeObject(forKey: "reminders")
        }
    }

    var savedOrigin: CGPoint? {
        guard let point = defaults.array(forKey: "spiritOrigin") as? [Double], point.count == 2 else { return nil }
        return CGPoint(x: point[0], y: point[1])
    }

    func saveOrigin(_ point: CGPoint) { defaults.set([point.x, point.y], forKey: "spiritOrigin") }

    func startFocus(minutes: Int) {
        do {
            alerts.focusTimer = try FocusTimer(minutes: minutes, now: Date())
            errorMessage = nil
            persistAlerts()
        } catch { errorMessage = "집중 시간은 1분부터 180분까지 입력해 주세요." }
    }

    func cancelFocus() { alerts.focusTimer = nil; persistAlerts() }

    func addReminder(dueAt: Date, message: String) -> Bool {
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 120, dueAt > Date() else {
            errorMessage = "미래 시각과 1자부터 120자까지의 문구를 입력해 주세요."
            return false
        }
        alerts.reminders.append(Reminder(dueAt: dueAt, message: cleaned))
        alerts.reminders.sort { $0.dueAt < $1.dueAt }
        errorMessage = nil
        persistAlerts()
        return true
    }

    func removeReminder(id: UUID) {
        alerts.reminders.removeAll { $0.id == id && $0.deliveredAt == nil }
        persistAlerts()
    }

    func currentAlert(isSuspended: Bool) -> PendingAlert? { alerts.currentAlert(isSuspended: isSuspended) }

    func acknowledgeAlert(id: UUID) {
        alerts.acknowledge(id: id)
        persistAlerts()
        onAlertChange?()
    }

    func checkDeadlines(at now: Date = Date()) {
        let previousCount = alerts.pending.count
        alerts.consumeDue(at: now)
        guard alerts.pending.count != previousCount else { return }
        // Persist consumption and the unacknowledged queue in the same snapshot before presentation.
        persistAlerts()
        onAlertChange?()
        if soundEnabled { NSSound(named: "Glass")?.play() }
    }

    private func persistAlerts() {
        defaults.set(try? JSONEncoder().encode(alerts), forKey: "localAlertState")
    }
}
