import Foundation

public struct PendingAlert: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let message: String
    public let reminderID: UUID?
}

public struct LocalAlertState: Codable, Sendable {
    public var focusTimer: FocusTimer?
    public var reminders: [Reminder]
    public private(set) var pending: [PendingAlert] = []

    public init(focusTimer: FocusTimer? = nil, reminders: [Reminder] = []) {
        self.focusTimer = focusTimer
        self.reminders = reminders
    }

    public mutating func consumeDue(at now: Date) {
        if var timer = focusTimer, timer.consumeIfDue(at: now) {
            focusTimer = timer
            pending.append(PendingAlert(id: UUID(), message: "집중 시간이 끝났어요. 잠깐 쉬어 가세요.", reminderID: nil))
        }
        for index in reminders.indices where reminders[index].deliveredAt == nil {
            if reminders[index].consumeIfDue(at: now) {
                pending.append(PendingAlert(id: UUID(), message: reminders[index].message, reminderID: reminders[index].id))
            }
        }
    }

    public func currentAlert(isSuspended: Bool) -> PendingAlert? {
        isSuspended ? nil : pending.first
    }

    public mutating func acknowledge(id: UUID) {
        guard let current = pending.first, current.id == id else { return }
        pending.removeFirst()
        if let reminderID = current.reminderID { reminders.removeAll { $0.id == reminderID } }
    }
}
