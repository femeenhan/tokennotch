import Foundation
import Testing
@testable import SpiritCore

struct QuotaTrendTests {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }
    private func sample(_ at: String, _ percent: Double, reset: String = "2026-09-18T03:00:00Z", duration: Int = 10080, accountID: String? = "account-a") -> QuotaSnapshot {
        QuotaSnapshot(observedAt: date(at), buckets: [QuotaBucket(id: "codex", secondary:
            QuotaWindow(usedPercent: percent, windowDurationMins: duration, resetsAt: date(reset)))], accountID: accountID)
    }

    @Test func firstObservationDoesNotAssumeUsageStartedAtZero() {
        let query = QuotaTrend(history: [sample("2026-09-16T02:00:00Z", 40)], bucketID: "codex",
                               now: date("2026-09-16T03:00:00Z"), calendar: calendar)
        #expect(query.todayUsedPercentagePoints == nil)
        #expect(query.recentUsedPercentagePoints == nil)
        #expect(query.riskMessage == nil)
        #expect(query.remainingDays == 2)
        #expect(query.sampleCount == 1)
    }

    @Test func todayStartsAtLocalMidnightAndRecentUsesSixtyMinuteLookback() {
        let history = [sample("2026-09-15T14:59:59Z", 5), sample("2026-09-15T15:00:00Z", 10),
                       sample("2026-09-16T01:59:59Z", 20), sample("2026-09-16T02:00:00Z", 30),
                       sample("2026-09-16T02:30:00Z", 35), sample("2026-09-16T03:00:00Z", 40),
                       sample("2026-09-16T03:00:01Z", 90)]
        let query = QuotaTrend(history: history, bucketID: "codex", now: date("2026-09-16T03:00:00Z"), calendar: calendar)
        #expect(query.todayUsedPercentagePoints == 30)
        #expect(query.recentUsedPercentagePoints == 10)
        #expect(query.recentObservationMinutes == 60)
        #expect(query.sampleCount == 6)
        #expect(query.riskMessage != nil)
    }

    @Test func measuredZeroIsNotMissingAndShortRecentIntervalIsUnknown() {
        let history = [sample("2026-09-16T02:46:00Z", 20), sample("2026-09-16T03:00:00Z", 20)]
        let query = QuotaTrend(history: history, bucketID: "codex", now: date("2026-09-16T03:00:00Z"), calendar: calendar)
        #expect(query.todayUsedPercentagePoints == 0)
        #expect(query.recentUsedPercentagePoints == nil)
        #expect(query.recentObservationMinutes == nil)
        #expect(query.riskMessage == nil)
        let fifteen = QuotaTrend(history: [sample("2026-09-16T02:45:00Z", 20), sample("2026-09-16T03:00:00Z", 20)], bucketID: "codex", now: date("2026-09-16T03:00:00Z"), calendar: calendar)
        #expect(fifteen.recentUsedPercentagePoints == 0)
        #expect(fifteen.recentObservationMinutes == 15)
    }

    @Test func resetChangeAndRollingDecreaseInvalidateIntervalsRatherThanSumIncreases() {
        for history in [
            [sample("2026-09-16T02:00:00Z", 80), sample("2026-09-16T02:30:00Z", 10), sample("2026-09-16T03:00:00Z", 20)],
            [sample("2026-09-16T02:00:00Z", 10), sample("2026-09-16T03:00:00Z", 20, reset: "2026-09-19T03:00:00Z")]
        ] {
            let query = QuotaTrend(history: history, bucketID: "codex", now: date("2026-09-16T03:00:00Z"), calendar: calendar)
            #expect(query.todayUsedPercentagePoints == nil)
            #expect(query.recentUsedPercentagePoints == nil)
            #expect(query.riskMessage == nil)
        }
    }

    @Test func riskRequiresThreeStableSamplesThirtyMinutesAndFutureReset() {
        let now = date("2026-09-16T03:00:00Z")
        let stable = [sample("2026-09-16T02:30:00Z", 80), sample("2026-09-16T02:45:00Z", 85), sample("2026-09-16T03:00:00Z", 90)]
        #expect(QuotaTrend(history: stable, bucketID: "codex", now: now, calendar: calendar).riskMessage != nil)
        #expect(QuotaTrend(history: Array(stable.suffix(2)), bucketID: "codex", now: now, calendar: calendar).riskMessage == nil)
        let unstable = [sample("2026-09-16T02:30:00Z", 80), sample("2026-09-16T02:45:00Z", 80.1), sample("2026-09-16T03:00:00Z", 90)]
        #expect(QuotaTrend(history: unstable, bucketID: "codex", now: now, calendar: calendar).riskMessage == nil)
        let expired = stable.map { snapshot in
            QuotaSnapshot(observedAt: snapshot.observedAt, buckets: [QuotaBucket(id: "codex", secondary: QuotaWindow(usedPercent: 90, windowDurationMins: 10080, resetsAt: now))], accountID: "account-a")
        }
        #expect(QuotaTrend(history: expired, bucketID: "codex", now: now, calendar: calendar).riskMessage == nil)
    }

    @Test func nonWeeklyOrUnidentifiedWindowDoesNotInventWeeklyTrend() {
        let history = [sample("2026-09-16T02:00:00Z", 10, duration: 300), sample("2026-09-16T03:00:00Z", 20, duration: 300)]
        let query = QuotaTrend(history: history, bucketID: "codex", now: date("2026-09-16T03:00:00Z"), calendar: calendar)
        #expect(query.weeklyWindow == nil)
        #expect(query.todayUsedPercentagePoints == nil)
        #expect(query.remainingDays == nil)
        #expect(QuotaTrend(history: history, bucketID: "other", now: date("2026-09-16T03:00:00Z"), calendar: calendar).sampleCount == 0)
    }

    @Test func intermediateWindowChangeCannotBeHiddenBySkippingUnsupportedObservation() {
        let history = [sample("2026-09-16T02:00:00Z", 10),
                       sample("2026-09-16T02:30:00Z", 15, duration: 300),
                       sample("2026-09-16T03:00:00Z", 20)]
        let query = QuotaTrend(history: history, bucketID: "codex", now: date("2026-09-16T03:00:00Z"), calendar: calendar)
        #expect(query.todayUsedPercentagePoints == nil)
        #expect(query.recentUsedPercentagePoints == nil)
    }

    @Test func newestMissingOrUnsupportedWeeklyWindowInvalidatesOldTrendAndRisk() {
        let stable = [sample("2026-09-16T02:29:00Z", 80), sample("2026-09-16T02:44:00Z", 85), sample("2026-09-16T02:59:00Z", 90)]
        for latest in [QuotaSnapshot(observedAt: date("2026-09-16T03:00:00Z"), buckets: []),
                       sample("2026-09-16T03:00:00Z", 91, duration: 300)] {
            let query = QuotaTrend(history: stable + [latest], bucketID: "codex", now: date("2026-09-16T03:00:00Z"), calendar: calendar)
            #expect(query.weeklyWindow == nil)
            #expect(query.todayUsedPercentagePoints == nil)
            #expect(query.recentUsedPercentagePoints == nil)
            #expect(query.recentObservationMinutes == nil)
            #expect(query.riskMessage == nil)
            #expect(query.remainingDays == nil)
        }
    }

    @Test func unknownOrChangedAccountCannotProduceBucketTrend() {
        for accounts: [String?] in [[nil, nil, nil], ["account-a", "account-a", "account-b"], ["account-a", nil, "account-a"]] {
            let history = [sample("2026-09-16T02:30:00Z", 80, accountID: accounts[0]),
                           sample("2026-09-16T02:45:00Z", 85, accountID: accounts[1]),
                           sample("2026-09-16T03:00:00Z", 90, accountID: accounts[2])]
            let query = QuotaTrend(history: history, bucketID: "codex", now: date("2026-09-16T03:00:00Z"), calendar: calendar)
            #expect(query.weeklyWindow?.usedPercent == 90)
            #expect(query.todayUsedPercentagePoints == nil)
            #expect(query.recentUsedPercentagePoints == nil)
            #expect(query.riskMessage == nil)
        }
    }

    @Test func integerStaircaseAtMinutePollingStillRecognizesStableDrain() {
        let now = date("2026-09-16T03:00:00Z")
        let beginning = date("2026-09-16T02:00:00Z")
        let history = (0...60).map { minute in
            QuotaSnapshot(observedAt: beginning.addingTimeInterval(Double(minute * 60)), buckets: [QuotaBucket(id: "codex", secondary: QuotaWindow(usedPercent: Double(80 + minute / 10), windowDurationMins: 10080, resetsAt: date("2026-09-18T03:00:00Z")))], accountID: "account-a")
        }
        #expect(QuotaTrend(history: history, bucketID: "codex", now: now, calendar: calendar).riskMessage != nil)
        for burst: Bool in [false, true] {
            let plateau = history.enumerated().map { index, snapshot in
                QuotaSnapshot(observedAt: snapshot.observedAt, buckets: [QuotaBucket(id: "codex", secondary: QuotaWindow(usedPercent: burst && index >= 45 ? 90 : 80, windowDurationMins: 10080, resetsAt: date("2026-09-18T03:00:00Z")))], accountID: "account-a")
            }
            #expect(QuotaTrend(history: plateau, bucketID: "codex", now: now, calendar: calendar).riskMessage == nil)
        }
    }

    @Test func oneSecondResetJitterPreservesMeasuredZeroAndSteadyRiskButSixtySecondsDoesNot() {
        let now = date("2026-09-16T03:00:00Z")
        let beginning = date("2026-09-16T02:00:00Z")
        let reset = date("2026-09-18T03:00:00Z")
        for jitter in [1.0, 5.0, 6.0, 60.0] {
            for steadyDrain in [false, true] {
                let history = (0...60).map { minute in
                    QuotaSnapshot(observedAt: beginning.addingTimeInterval(Double(minute * 60)), buckets: [QuotaBucket(id: "codex", secondary: QuotaWindow(usedPercent: steadyDrain ? Double(80 + minute / 10) : 67, windowDurationMins: 10080, resetsAt: reset.addingTimeInterval(minute.isMultiple(of: 2) ? 0 : jitter)))], accountID: "account-a")
                }
                let query = QuotaTrend(history: history, bucketID: "codex", now: now, calendar: calendar)
                if jitter <= 5 {
                    #expect(query.todayUsedPercentagePoints == (steadyDrain ? 6 : 0))
                    #expect(query.recentUsedPercentagePoints == (steadyDrain ? 6 : 0))
                    #expect(query.recentObservationMinutes == 60)
                    #expect((query.riskMessage != nil) == steadyDrain)
                } else {
                    #expect(query.todayUsedPercentagePoints == nil)
                    #expect(query.recentUsedPercentagePoints == nil)
                    #expect(query.riskMessage == nil)
                }
            }
        }
    }

    @Test func resetToleranceIsAnchoredToLatestAndCannotAccumulateRollingDrift() {
        let beginning = date("2026-09-16T02:00:00Z")
        let reset = date("2026-09-18T03:00:00Z")
        let history = (0...6).map { index in
            QuotaSnapshot(observedAt: beginning.addingTimeInterval(Double(index * 600)), buckets: [QuotaBucket(id: "codex", secondary: QuotaWindow(usedPercent: 67, windowDurationMins: 10080, resetsAt: reset.addingTimeInterval(Double(index))))], accountID: "account-a")
        }
        let query = QuotaTrend(history: history, bucketID: "codex", now: date("2026-09-16T03:00:00Z"), calendar: calendar)
        #expect(query.todayUsedPercentagePoints == nil)
        #expect(query.recentUsedPercentagePoints == nil)
        #expect(query.riskMessage == nil)
    }
}
