import Foundation

/// Allowlisted token metadata. Unspecified legacy scope means cumulative, never a delta.
public struct UsageRecord: Codable, Equatable, Sendable {
    public enum Scope: String, Codable, Sendable {
        case sessionTotal, delta, historicalUnattributed
    }
    public enum Attribution: String, Codable, Sendable {
        case observedDelta, historicalBaseline, counterReset, compactionBoundary, observationGap, ambiguousModel
    }
    public let id: String
    public let sessionID: String
    public let modelID: String?
    public let occurredAt: Date
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedInputTokens: Int?
    public let reasoningOutputTokens: Int?
    public let totalTokens: Int
    /// Not collected by the supported rollout decoder; nil is unavailable, not zero.
    public let cacheWriteInputTokens: Int?
    public let scope: Scope?
    public let attribution: Attribution?

    public init(id: String, sessionID: String, modelID: String? = nil, occurredAt: Date,
                inputTokens: Int, outputTokens: Int, cachedInputTokens: Int? = nil,
                reasoningOutputTokens: Int? = nil, totalTokens: Int,
                cacheWriteInputTokens: Int? = nil, scope: Scope? = nil, attribution: Attribution? = nil) {
        self.id = id; self.sessionID = sessionID; self.modelID = modelID
        self.occurredAt = occurredAt; self.inputTokens = inputTokens
        self.outputTokens = outputTokens; self.cachedInputTokens = cachedInputTokens
        self.reasoningOutputTokens = reasoningOutputTokens; self.totalTokens = totalTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens; self.scope = scope; self.attribution = attribution
    }
}
