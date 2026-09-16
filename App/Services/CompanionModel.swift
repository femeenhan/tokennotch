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
    @Published private(set) var eventStream = SpiritEventStream()
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
        eventStream.receive(event)
        hookStatus = "Codex CLI 이벤트를 수신했습니다."
        onAppearanceChange?()
        performDashboardOperation { store in try await store.record(event) }
    }

    func finishCompletionPresentation(id: UUID) {
        eventStream.finishCompletionPresentation(id: id)
        onAppearanceChange?()
    }

    func finishGreetingPresentation(id: UUID) {
        eventStream.finishGreetingPresentation(id: id)
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
