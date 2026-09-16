import Foundation

public struct FocusTimer: Codable, Equatable, Sendable {
    public enum ValidationError: Error { case invalidMinutes }
    public let deadline: Date
    public private(set) var deliveredAt: Date?

    public init(minutes: Int = 25, now: Date) throws {
        guard (1...180).contains(minutes) else { throw ValidationError.invalidMinutes }
        deadline = now.addingTimeInterval(Double(minutes) * 60)
    }

    public mutating func consumeIfDue(at now: Date) -> Bool {
        guard deliveredAt == nil, now >= deadline else { return false }
        deliveredAt = now
        return true
    }
}

public struct Reminder: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let dueAt: Date
    public let message: String
    public private(set) var deliveredAt: Date?

    public init(dueAt: Date, message: String) {
        id = UUID()
        self.dueAt = dueAt
        self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public mutating func consumeIfDue(at now: Date) -> Bool {
        guard deliveredAt == nil, now >= dueAt else { return false }
        deliveredAt = now
        return true
    }
}
