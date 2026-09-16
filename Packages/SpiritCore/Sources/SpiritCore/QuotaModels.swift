import Foundation

public struct QuotaWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let windowDurationMins: Int?
    public let resetsAt: Date?
    public var remainingPercent: Double? {
        guard usedPercent.isFinite, (0...100).contains(usedPercent) else { return nil }
        return 100 - usedPercent
    }
    public init(usedPercent: Double, windowDurationMins: Int? = nil, resetsAt: Date? = nil) {
        self.usedPercent = usedPercent; self.windowDurationMins = windowDurationMins; self.resetsAt = resetsAt
    }
}

public struct QuotaBucket: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String?
    public let modelID: String?
    public let primary: QuotaWindow?
    public let secondary: QuotaWindow?
    public init(id: String, name: String? = nil, modelID: String? = nil,
                primary: QuotaWindow? = nil, secondary: QuotaWindow? = nil) {
        self.id = id; self.name = name; self.modelID = modelID
        self.primary = primary; self.secondary = secondary
    }
}

public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public let observedAt: Date
    public let buckets: [QuotaBucket]
    public let accountID: String?
    public init(observedAt: Date, buckets: [QuotaBucket], accountID: String? = nil) {
        self.observedAt = observedAt; self.buckets = buckets; self.accountID = accountID
    }
}

public struct CodexDailyUsageBucket: Codable, Equatable, Sendable, Identifiable {
    public var id: String { startDate }
    /// Backend calendar date, deliberately not reinterpreted in the local time zone.
    public let startDate: String
    public let tokens: Int
    public init(startDate: String, tokens: Int) { self.startDate = startDate; self.tokens = tokens }
}

public struct CodexThreadUsageGroup: Codable, Equatable, Sendable {
    public let modelID: String?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cachedInputTokens: Int?
    public let netNewInputTokens: Int?
    public let totalTokens: Int?
    public init(modelID: String?, inputTokens: Int?, outputTokens: Int?, cachedInputTokens: Int?, netNewInputTokens: Int?, totalTokens: Int?) {
        self.modelID = modelID; self.inputTokens = inputTokens; self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens; self.netNewInputTokens = netNewInputTokens; self.totalTokens = totalTokens
    }
}

/// Per-thread estimated token metadata, not account-wide model attribution or costs.
public struct CodexThreadUsage: Codable, Equatable, Sendable {
    public let threadID: String
    public let groups: [CodexThreadUsageGroup]
    public init(threadID: String, groups: [CodexThreadUsageGroup]) { self.threadID = threadID; self.groups = groups }
}

public struct CodexAccountUsage: Codable, Equatable, Sendable {
    public let observedAt: Date
    public let lifetimeTokens: Int?
    public let dailyBuckets: [CodexDailyUsageBucket]?
    public let threadUsage: CodexThreadUsage?
    public init(observedAt: Date, lifetimeTokens: Int?, dailyBuckets: [CodexDailyUsageBucket]?, threadUsage: CodexThreadUsage? = nil) {
        self.observedAt = observedAt; self.lifetimeTokens = lifetimeTokens
        self.dailyBuckets = dailyBuckets; self.threadUsage = threadUsage
    }
}
