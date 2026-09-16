import Foundation

public struct SpiritEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case sessionStarted
        case turnStarted
        case toolStarted
        case toolFinished
        case needsInput
        case turnStopped
        case sessionEnded
        case usageObserved
        case collectionInterrupted
    }

    public struct Payload: Codable, Equatable, Sendable {
        public var toolCategory: String?
        public var success: Bool?
        public var relativePath: String?
        public var modelID: String?
        public var usageCounts: [String: Int]?

        public init(
            toolCategory: String? = nil,
            success: Bool? = nil,
            relativePath: String? = nil,
            modelID: String? = nil,
            usageCounts: [String: Int]? = nil
        ) {
            self.toolCategory = toolCategory
            self.success = success
            self.relativePath = relativePath
            self.modelID = modelID
            self.usageCounts = usageCounts
        }
    }

    public let schemaVersion: Int
    public let eventID: String
    public let provider: String
    public let sessionID: String
    public let parentSessionID: String?
    public let turnID: String?
    public let kind: Kind
    public let occurredAt: Date
    public let receivedAt: Date
    public let projectID: UUID?
    public let worktreeID: UUID?
    public let source: String
    public let sourceVersion: String
    public let payload: Payload

    public init(
        schemaVersion: Int = 1,
        eventID: String,
        provider: String,
        sessionID: String,
        parentSessionID: String? = nil,
        turnID: String? = nil,
        kind: Kind,
        occurredAt: Date,
        receivedAt: Date,
        projectID: UUID? = nil,
        worktreeID: UUID? = nil,
        source: String,
        sourceVersion: String,
        payload: Payload = .init()
    ) {
        self.schemaVersion = schemaVersion
        self.eventID = eventID
        self.provider = provider
        self.sessionID = sessionID
        self.parentSessionID = parentSessionID
        self.turnID = turnID
        self.kind = kind
        self.occurredAt = occurredAt
        self.receivedAt = receivedAt
        self.projectID = projectID
        self.worktreeID = worktreeID
        self.source = source
        self.sourceVersion = sourceVersion
        self.payload = payload
    }
}
