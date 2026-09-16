import Foundation

public struct DashboardProject: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let path: String
    public let name: String
    public init(id: UUID = UUID(), path: String, name: String) {
        self.id = id; self.path = path; self.name = name
    }
}

public struct DashboardSession: Equatable, Identifiable, Sendable {
    public let id: String
    public let status: SessionState.Status
    public let startedAt: Date
    public let lastObservedAt: Date
    public let projectID: UUID?
    public init(id: String, status: SessionState.Status, startedAt: Date, lastObservedAt: Date, projectID: UUID? = nil) {
        self.id = id; self.status = status; self.startedAt = startedAt
        self.lastObservedAt = lastObservedAt; self.projectID = projectID
    }
}

public struct DashboardSnapshot: Equatable, Sendable {
    public let projects: [DashboardProject]
    public let sessions: [DashboardSession]
    public let events: [SpiritEvent]
    public let usage: [UsageRecord]
    public init(projects: [DashboardProject] = [], sessions: [DashboardSession] = [], events: [SpiritEvent] = [], usage: [UsageRecord] = []) {
        self.projects = projects; self.sessions = sessions; self.events = events; self.usage = usage
    }
}
