import Foundation
import Testing
@testable import SpiritCore

@Suite("DashboardQuery")
struct DashboardQueryTests {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var seoul: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }
    private let nowText = "2026-09-16T03:00:00Z"
    private func session(_ id: String, project: UUID? = nil, status: SessionState.Status = .working) -> DashboardSession {
        DashboardSession(id: id, status: status, startedAt: date("2026-08-01T00:00:00Z"),
                         lastObservedAt: date("2026-09-16T03:00:00Z"), projectID: project)
    }
    private func event(_ id: String, session: String = "a", at: String, kind: SpiritEvent.Kind = .toolStarted) -> SpiritEvent {
        SpiritEvent(eventID: id, provider: "codex", sessionID: session, kind: kind,
                    occurredAt: date(at), receivedAt: date(at), source: "hook", sourceVersion: "1")
    }
    private func usage(_ id: String, session: String = "a", at: String = "2026-09-16T02:00:00Z", total: Int) -> UsageRecord {
        UsageRecord(id: id, sessionID: session, modelID: "codex", occurredAt: date(at),
                    inputTokens: total, outputTokens: 0, cachedInputTokens: nil,
                    reasoningOutputTokens: nil, totalTokens: total)
    }

    @Test func periodsUseLocalCalendarBoundariesAndExcludeFuture() {
        let snapshot = DashboardSnapshot(projects: [], sessions: [session("a")], events: [
            event("before30", at: "2026-08-17T14:59:59Z"),
            event("start30", at: "2026-08-17T15:00:00Z"),
            event("before7", at: "2026-09-09T14:59:59Z"),
            event("start7", at: "2026-09-09T15:00:00Z"),
            event("beforeToday", at: "2026-09-15T14:59:59Z"),
            event("startToday", at: "2026-09-15T15:00:00Z"),
            event("now", at: nowText), event("future", at: "2026-09-16T03:00:01Z")
        ], usage: [])
        let today = DashboardQuery(snapshot: snapshot, days: 1, now: date(nowText), calendar: seoul)
        #expect(today.startDate == date("2026-09-15T15:00:00Z"))
        #expect(Set(today.events.map(\.eventID)) == ["startToday", "now"])
        #expect(today.activity.map(\.count) == [2])
        let week = DashboardQuery(snapshot: snapshot, days: 7, now: date(nowText), calendar: seoul)
        #expect(week.startDate == date("2026-09-09T15:00:00Z"))
        #expect(week.activity.map(\.count) == [1, 0, 0, 0, 0, 1, 2])
        let month = DashboardQuery(snapshot: snapshot, days: 30, now: date(nowText), calendar: seoul)
        #expect(month.startDate == date("2026-08-17T15:00:00Z"))
        #expect(month.events.count == 6)
        #expect(month.activity.count == 30)
    }

    @Test func projectFilterUsesSessionAssignmentAndKeepsOlderActiveSessions() {
        let project = UUID()
        let snapshot = DashboardSnapshot(projects: [], sessions: [session("a", project: project), session("b", status: .attention), session("inactive", project: project)], events: [
            event("tool", at: "2026-09-16T01:00:00Z"),
            event("finished", at: "2026-09-16T02:00:00Z", kind: .toolFinished),
            event("other", session: "b", at: "2026-09-16T02:00:00Z")
        ], usage: [usage("a-total", total: 40), usage("b-total", session: "b", total: 90)])
        let query = DashboardQuery(snapshot: snapshot, days: 1, projectID: project, now: date(nowText), calendar: seoul)
        #expect(query.sessions.map(\.id) == ["a"])
        #expect(query.events.count == 2)
        #expect(query.usage.map(\.sessionID) == ["a"])
        #expect(query.toolCount == 1)
        #expect(query.workingCount == 1)
        #expect(query.attentionCount == 0)
        #expect(query.observedTokenTotal == 40)
    }

    @Test func latestUsageIsCumulativeNotSumOfObservationsAndUsageOnlySessionIsActive() {
        let snapshot = DashboardSnapshot(projects: [], sessions: [session("a")], events: [], usage: [
            usage("old", at: "2026-09-16T01:00:00Z", total: 10), usage("latest", total: 25),
            usage("future", at: "2026-09-16T04:00:00Z", total: 50)
        ])
        let query = DashboardQuery(snapshot: snapshot, days: 1, now: date(nowText), calendar: seoul)
        #expect(query.sessions.map(\.id) == ["a"])
        #expect(query.observedTokenTotal == 25)
        #expect(query.usage.count == 2)
        #expect(query.activity.map(\.count) == [0])
    }

    @Test func missingUsageDiffersFromZeroAndOverflowReturnsUnknown() {
        let activity = [event("tool", at: "2026-09-16T01:00:00Z")]
        let empty = DashboardSnapshot(projects: [], sessions: [session("a")], events: activity, usage: [])
        #expect(DashboardQuery(snapshot: empty, days: 1, now: date(nowText), calendar: seoul).observedTokenTotal == nil)
        let zero = DashboardSnapshot(projects: [], sessions: [session("a")], events: activity, usage: [usage("zero", total: 0)])
        #expect(DashboardQuery(snapshot: zero, days: 1, now: date(nowText), calendar: seoul).observedTokenTotal == 0)
        let overflow = DashboardSnapshot(projects: [], sessions: [session("a"), session("b")], events: activity,
                                         usage: [usage("max", total: Int.max), usage("one", session: "b", total: 1)])
        #expect(DashboardQuery(snapshot: overflow, days: 1, now: date(nowText), calendar: seoul).observedTokenTotal == nil)
    }

    @Test func daylightSavingUsesCalendarDaysNotFixedSeconds() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let snapshot = DashboardSnapshot(projects: [], sessions: [], events: [], usage: [])
        let query = DashboardQuery(snapshot: snapshot, days: 7, now: date("2026-03-10T19:00:00Z"), calendar: calendar)
        #expect(query.startDate == date("2026-03-04T08:00:00Z"))
        #expect(query.activity.count == 7)
        #expect(query.activity.last?.date == date("2026-03-10T07:00:00Z"))
    }

    @Test func immutableDeltasAggregateByExactModelAndLocalDateWithoutCumulativeDoubleCounting() {
        func delta(_ id: String, model: String?, at: String, input: Int, output: Int, cached: Int?) -> UsageRecord {
            UsageRecord(id: id, sessionID: "a", modelID: model, occurredAt: date(at), inputTokens: input,
                        outputTokens: output, cachedInputTokens: cached, reasoningOutputTokens: 1,
                        totalTokens: input + output, scope: .delta, attribution: .observedDelta)
        }
        let first = delta("d1", model: "gpt-6-astra", at: "2026-09-15T14:59:59Z", input: 10, output: 2, cached: 3)
        let second = delta("d2", model: "gpt-5.6-sol", at: "2026-09-15T15:00:00Z", input: 20, output: 4, cached: 5)
        let third = delta("d3", model: nil, at: "2026-09-16T02:00:00Z", input: 7, output: 1, cached: nil)
        let snapshot = DashboardSnapshot(sessions: [session("a")], usage: [first, first, second, third, usage("cumulative", total: 999)])
        let query = DashboardQuery(snapshot: snapshot, days: 7, now: date(nowText), calendar: seoul)
        #expect(query.tokenSummary.deltaRecordCount == 3)
        #expect(query.tokenSummary.exactRecords.map(\.id) == ["d1", "d2", "d3"])
        #expect(query.tokenSummary.totals?.inputTokens == 37)
        #expect(query.tokenSummary.totals?.outputTokens == 7)
        #expect(query.tokenSummary.totals?.totalTokens == 44)
        #expect(query.tokenSummary.totals?.cachedInputTokens == nil)
        #expect(query.tokenSummary.unclassifiedRecordCount == 1)
        #expect(query.tokenSummary.models.first { $0.modelID == "gpt-6-astra" }?.totals?.cachedInputTokens == 3)
        #expect(query.tokenSummary.days.filter { $0.totals != nil }.map { $0.totals!.totalTokens } == [12, 32])
        #expect(query.observedTokenTotal == 999)
        let today = DashboardQuery(snapshot: snapshot, days: 1, now: date(nowText), calendar: seoul)
        #expect(today.tokenSummary.totals?.totalTokens == 32)
    }

    @Test func cumulativeOnlyCoverageDoesNotPretendToBePeriodTokensAndDeltaZeroIsKnown() {
        let cumulative = DashboardSnapshot(sessions: [session("a")], usage: [usage("cumulative", total: 8)])
        let query = DashboardQuery(snapshot: cumulative, days: 1, now: date(nowText), calendar: seoul)
        #expect(query.tokenSummary.totals == nil)
        #expect(query.tokenSummary.cumulativeOnlySessionCount == 1)
        let zero = UsageRecord(id: "delta-zero", sessionID: "a", modelID: "gpt-6-astra", occurredAt: date(nowText),
                               inputTokens: 0, outputTokens: 0, cachedInputTokens: 0, reasoningOutputTokens: 0,
                               totalTokens: 0, scope: .delta, attribution: .observedDelta)
        let known = DashboardQuery(snapshot: DashboardSnapshot(sessions: [session("a")], usage: [zero]), days: 1, now: date(nowText), calendar: seoul)
        #expect(known.tokenSummary.totals?.totalTokens == 0)
        #expect(known.observedTokenTotal == nil)
    }

    @Test func uncertainIntervalsAreCoverageOnlyAndSubsetOverflowIsUnknown() {
        let gap = UsageRecord(id: "gap", sessionID: "a", occurredAt: date(nowText), inputTokens: 10,
                              outputTokens: 2, totalTokens: 12, scope: .delta, attribution: .observationGap)
        let baseline = UsageRecord(id: "historical", sessionID: "a", occurredAt: date(nowText), inputTokens: 99,
                                   outputTokens: 1, totalTokens: 100, scope: .historicalUnattributed, attribution: .historicalBaseline)
        let uncertain = DashboardQuery(snapshot: DashboardSnapshot(sessions: [session("a")], usage: [gap, baseline]), days: 1, now: date(nowText), calendar: seoul)
        #expect(uncertain.tokenSummary.totals == nil)
        #expect(uncertain.tokenSummary.excludedRecordCount == 2)
        #expect(uncertain.tokenSummary.unattributedRecords.count == 2)
        #expect(uncertain.tokenSummary.days.first?.totals == nil)
        let max = UsageRecord(id: "max-delta", sessionID: "a", modelID: "gpt-6-astra", occurredAt: date(nowText), inputTokens: Int.max,
                              outputTokens: 0, cachedInputTokens: Int.max, totalTokens: Int.max, scope: .delta, attribution: .observedDelta)
        let one = UsageRecord(id: "one-delta", sessionID: "a", modelID: "gpt-6-astra", occurredAt: date(nowText), inputTokens: 1,
                              outputTokens: 0, cachedInputTokens: 1, totalTokens: 1, scope: .delta, attribution: .observedDelta)
        let overflow = DashboardQuery(snapshot: DashboardSnapshot(sessions: [session("a")], usage: [max, one]), days: 1, now: date(nowText), calendar: seoul)
        #expect(overflow.tokenSummary.totals == nil)
        #expect(overflow.tokenSummary.models.first?.totals == nil)
    }
}
