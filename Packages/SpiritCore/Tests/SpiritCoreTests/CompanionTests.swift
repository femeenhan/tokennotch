import Foundation
import CoreGraphics
import Testing
@testable import SpiritCore

@Suite("Companion geometry and one-shot alerts")
struct CompanionTests {
    @Test func sizeClampsAndRejectsNonfiniteValues() {
        #expect(CompanionGeometry.clampedSize(20) == 80)
        #expect(CompanionGeometry.clampedSize(300) == 192)
        #expect(CompanionGeometry.clampedSize(128) == 128)
        #expect(CompanionGeometry.clampedSize(.nan) == 128)
    }

    @Test func disconnectedDisplayFallsBackToPrimarySafeArea() {
        let primary = CGRect(x: 0, y: 24, width: 1440, height: 876)
        let restored = CompanionGeometry.safeOrigin(CGPoint(x: 2500, y: 200), size: 128,
            visibleFrames: [primary], primaryFrame: primary)
        #expect(restored == CGPoint(x: 1296, y: 40))
    }

    @Test func connectedDisplayKeepsPositionAndClampsEdges() {
        let primary = CGRect(x: 0, y: 24, width: 1440, height: 876)
        let secondary = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        #expect(CompanionGeometry.safeOrigin(CGPoint(x: -1000, y: 200), size: 128,
            visibleFrames: [primary, secondary], primaryFrame: primary) == CGPoint(x: -1000, y: 200))
        #expect(CompanionGeometry.safeOrigin(CGPoint(x: 1400, y: 880), size: 128,
            visibleFrames: [primary], primaryFrame: primary) == CGPoint(x: 1296, y: 756))
    }

    @Test func timerRejectsInvalidMinutes() {
        #expect(throws: FocusTimer.ValidationError.self) { try FocusTimer(minutes: 0, now: .distantPast) }
        #expect(throws: FocusTimer.ValidationError.self) { try FocusTimer(minutes: 181, now: .distantPast) }
    }

    @Test func timerExpiresOnceAcrossWakeAndPersistence() throws {
        let start = Date(timeIntervalSince1970: 1000)
        var timer = try FocusTimer(now: start)
        #expect(timer.deadline == Date(timeIntervalSince1970: 2500))
        let early = timer.consumeIfDue(at: Date(timeIntervalSince1970: 2499))
        let expired = timer.consumeIfDue(at: Date(timeIntervalSince1970: 6000))
        let repeated = timer.consumeIfDue(at: Date(timeIntervalSince1970: 6001))
        #expect(!early)
        #expect(expired)
        #expect(!repeated)
        let data = try JSONEncoder().encode(timer)
        var restored = try JSONDecoder().decode(FocusTimer.self, from: data)
        let replayed = restored.consumeIfDue(at: Date(timeIntervalSince1970: 7000))
        #expect(!replayed)
        #expect(try FocusTimer(minutes: 1, now: start).deadline == Date(timeIntervalSince1970: 1060))
        #expect(try FocusTimer(minutes: 180, now: start).deadline == Date(timeIntervalSince1970: 11800))
    }

    @Test func reminderConsumesOnceAndPersistsMessage() throws {
        var reminder = Reminder(dueAt: Date(timeIntervalSince1970: 2000), message: "  물 마시기  ")
        #expect(reminder.message == "물 마시기")
        let early = reminder.consumeIfDue(at: Date(timeIntervalSince1970: 1999))
        let due = reminder.consumeIfDue(at: Date(timeIntervalSince1970: 2000))
        #expect(!early)
        #expect(due)
        var restored = try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(reminder))
        let replayed = restored.consumeIfDue(at: Date(timeIntervalSince1970: 6000))
        #expect(!replayed)
    }
}
