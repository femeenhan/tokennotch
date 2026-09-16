import Foundation
import Testing
@testable import SpiritCore

struct AlertPresentationTests {
    @Test func separateTicksPreserveFIFOAndAcknowledgmentCleansReminders() throws {
        let a = Reminder(dueAt: Date(timeIntervalSince1970: 10), message: "A")
        let b = Reminder(dueAt: Date(timeIntervalSince1970: 20), message: "B")
        var state = LocalAlertState(reminders: [a, b])
        state.consumeDue(at: Date(timeIntervalSince1970: 10))
        state.consumeDue(at: Date(timeIntervalSince1970: 20))
        state.consumeDue(at: Date(timeIntervalSince1970: 30))
        #expect(state.pending.map(\.message) == ["A", "B"])
        let first = try #require(state.currentAlert(isSuspended: false))
        #expect(first.message == "A")
        state.acknowledge(id: first.id)
        #expect(state.currentAlert(isSuspended: false)?.message == "B")
        #expect(state.reminders.map(\.id) == [b.id])
        state.acknowledge(id: first.id) // stale button must not acknowledge B
        #expect(state.pending.map(\.message) == ["B"])
        let second = try #require(state.currentAlert(isSuspended: false))
        state.acknowledge(id: second.id)
        state.consumeDue(at: Date(timeIntervalSince1970: 40))
        #expect(state.pending.isEmpty)
        #expect(state.reminders.isEmpty)
    }

    @Test func suspensionAndCodableRestoreOnlyUnacknowledgedAlert() throws {
        var state = LocalAlertState(reminders: [Reminder(dueAt: .distantPast, message: "A")])
        state.consumeDue(at: Date(timeIntervalSince1970: 10))
        let first = try #require(state.currentAlert(isSuspended: false))
        #expect(state.currentAlert(isSuspended: true) == nil)
        #expect(state.currentAlert(isSuspended: false) == first)
        var restored = try JSONDecoder().decode(LocalAlertState.self, from: JSONEncoder().encode(state))
        restored.consumeDue(at: Date(timeIntervalSince1970: 20))
        #expect(restored.pending.count == 1)
        #expect(restored.currentAlert(isSuspended: false) == first)
        restored.acknowledge(id: first.id)
        #expect(restored.currentAlert(isSuspended: true) == nil)
        #expect(restored.currentAlert(isSuspended: false) == nil)
        let acknowledged = try JSONDecoder().decode(LocalAlertState.self, from: JSONEncoder().encode(restored))
        #expect(acknowledged.pending.isEmpty)
        #expect(acknowledged.reminders.isEmpty)
    }

    @Test func timerAndReminderShareQueueWithoutReconsumingTimer() throws {
        var state = LocalAlertState(focusTimer: try FocusTimer(minutes: 1, now: Date(timeIntervalSince1970: 0)),
            reminders: [Reminder(dueAt: Date(timeIntervalSince1970: 70), message: "B")])
        state.consumeDue(at: Date(timeIntervalSince1970: 60))
        let timerAlert = try #require(state.currentAlert(isSuspended: false))
        state.consumeDue(at: Date(timeIntervalSince1970: 70))
        #expect(state.pending.count == 2)
        state.acknowledge(id: timerAlert.id)
        state.consumeDue(at: Date(timeIntervalSince1970: 80))
        #expect(state.pending.map(\.message) == ["B"])
    }

}
