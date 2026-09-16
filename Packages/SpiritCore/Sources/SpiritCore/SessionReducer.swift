import Foundation

public struct SessionState: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case unknown
        case idle
        case working
        case attention
        case error
        case ended
    }

    public var status: Status
    public var latestTurnID: String?
    public var latestTurnOccurredAt: Date?
    public var generationStartedAt: Date?
    public var endedAt: Date?
    public var completionID: String?

    public init(
        status: Status = .unknown,
        latestTurnID: String? = nil,
        latestTurnOccurredAt: Date? = nil,
        generationStartedAt: Date? = nil,
        endedAt: Date? = nil,
        completionID: String? = nil
    ) {
        self.status = status
        self.latestTurnID = latestTurnID
        self.latestTurnOccurredAt = latestTurnOccurredAt
        self.generationStartedAt = generationStartedAt
        self.endedAt = endedAt
        self.completionID = completionID
    }

    public static func restored() -> SessionState {
        SessionState(status: .unknown)
    }
}

public enum SpiritState: Equatable, Sendable {
    case idle
    case working
    case attention
    case completed
    case error
    case greeting
    case sleeping
}

public struct CompletionConsumption: Equatable, Sendable {
    public var consumedCompletionIDs: Set<String>

    public init(consumedCompletionIDs: Set<String> = []) {
        self.consumedCompletionIDs = consumedCompletionIDs
    }
}

public struct SpiritStateAggregation: Equatable, Sendable {
    public let state: SpiritState
    public let completionConsumption: CompletionConsumption

    public init(state: SpiritState, completionConsumption: CompletionConsumption) {
        self.state = state
        self.completionConsumption = completionConsumption
    }
}

public func reduce(
    sessions: [String: SessionState],
    event: SpiritEvent
) -> [String: SessionState] {
    var updatedSessions = sessions
    var session = updatedSessions[event.sessionID] ?? SessionState()

    if event.kind == .sessionStarted {
        applySessionStart(event, to: &session)
        updatedSessions[event.sessionID] = session
        return updatedSessions
    }

    guard belongsToCurrentGeneration(event, session: session) else {
        return updatedSessions
    }

    if session.status == .ended {
        return updatedSessions
    }

    switch event.kind {
    case .sessionStarted:
        break

    case .turnStarted:
        guard acceptsTurnStart(event, for: session) else { return updatedSessions }
        session.status = .working
        recordTurn(event, in: &session)

    case .toolStarted:
        guard acceptsCurrentTurnEvent(event, for: session) else { return updatedSessions }
        session.status = .working
        recordTurn(event, in: &session)

    case .toolFinished:
        guard acceptsCurrentTurnEvent(event, for: session) else { return updatedSessions }
        session.status = .working
        recordTurn(event, in: &session)

    case .needsInput:
        guard acceptsCurrentTurnEvent(event, for: session) else { return updatedSessions }
        session.status = .attention
        recordTurn(event, in: &session)

    case .turnStopped:
        guard acceptsCurrentTurnEvent(event, for: session) else { return updatedSessions }
        session.status = .idle
        recordTurn(event, in: &session)

    case .sessionEnded:
        session.status = .ended
        session.endedAt = event.occurredAt
        session.completionID = event.eventID

    case .usageObserved:
        break

    case .collectionInterrupted:
        guard acceptsCurrentTurnEvent(event, for: session) else { return updatedSessions }
        session.status = .error
        recordTurn(event, in: &session)
    }

    updatedSessions[event.sessionID] = session
    return updatedSessions
}

public func aggregateSpiritState(
    from sessions: [String: SessionState],
    consuming completionConsumption: CompletionConsumption
) -> SpiritStateAggregation {
    let statuses = Set(sessions.values.map(\.status))

    if statuses.contains(.attention) {
        return SpiritStateAggregation(state: .attention, completionConsumption: completionConsumption)
    }
    if statuses.contains(.error) {
        return SpiritStateAggregation(state: .error, completionConsumption: completionConsumption)
    }
    if statuses.contains(.working) {
        return SpiritStateAggregation(state: .working, completionConsumption: completionConsumption)
    }
    if let completionID = nextCompletionID(in: sessions, excluding: completionConsumption) {
        var updatedConsumption = completionConsumption
        updatedConsumption.consumedCompletionIDs.insert(completionID)
        return SpiritStateAggregation(state: .completed, completionConsumption: updatedConsumption)
    }
    return SpiritStateAggregation(state: .idle, completionConsumption: completionConsumption)
}

private func acceptsTurnStart(_ event: SpiritEvent, for session: SessionState) -> Bool {
    guard let latestTurnOccurredAt = session.latestTurnOccurredAt else { return true }
    return event.occurredAt >= latestTurnOccurredAt
}

private func applySessionStart(_ event: SpiritEvent, to session: inout SessionState) {
    if session.status == .ended {
        guard let endedAt = session.endedAt, event.occurredAt > endedAt else { return }
        session = SessionState(status: .idle, generationStartedAt: event.occurredAt)
    } else if session.status == .unknown {
        session.status = .idle
        session.generationStartedAt = event.occurredAt
    }
}

private func belongsToCurrentGeneration(_ event: SpiritEvent, session: SessionState) -> Bool {
    guard let generationStartedAt = session.generationStartedAt else { return true }
    return event.occurredAt > generationStartedAt
}

private func acceptsCurrentTurnEvent(_ event: SpiritEvent, for session: SessionState) -> Bool {
    if let turnID = event.turnID,
       let latestTurnID = session.latestTurnID,
       turnID != latestTurnID {
        return false
    }

    guard let latestTurnOccurredAt = session.latestTurnOccurredAt else { return true }
    return event.occurredAt >= latestTurnOccurredAt
}

private func recordTurn(_ event: SpiritEvent, in session: inout SessionState) {
    guard let turnID = event.turnID else { return }
    session.latestTurnID = turnID
    session.latestTurnOccurredAt = event.occurredAt
}

private func nextCompletionID(
    in sessions: [String: SessionState],
    excluding completionConsumption: CompletionConsumption
) -> String? {
    var candidates: [(id: String, endedAt: Date)] = []

    for (sessionID, session) in sessions where session.status == .ended {
        candidates.append((
            id: session.completionID ?? sessionID,
            endedAt: session.endedAt ?? .distantPast
        ))
    }

    return candidates
        .sorted { lhs, rhs in
            lhs.endedAt == rhs.endedAt ? lhs.id < rhs.id : lhs.endedAt < rhs.endedAt
        }
        .first { !completionConsumption.consumedCompletionIDs.contains($0.id) }?
        .id
}
