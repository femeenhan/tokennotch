import Foundation

public struct DashboardActivityDay: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let count: Int

    public init(date: Date, count: Int) {
        self.date = date
        self.count = count
    }
}

/// One consistent local-calendar and manually assigned project scope for the dashboard.
public struct DashboardQuery: Sendable {
    public let startDate: Date
    public let sessions: [DashboardSession]
    public let events: [SpiritEvent]
    public let usage: [UsageRecord]
    public let activity: [DashboardActivityDay]
    public let toolCount: Int
    public let workingCount: Int
    public let attentionCount: Int
    /// Latest observed cumulative totals for selected sessions, not a period delta.
    /// nil means no observation or an unrepresentable total; actual zero stays zero.
    public let observedTokenTotal: Int?
    /// Exact observed deltas only. Cumulative/baseline/gap reports never become period usage.
    public let tokenSummary: TokenUsageSummary

    public init(snapshot: DashboardSnapshot, days: Int, projectID: UUID? = nil,
                now: Date = Date(), calendar: Calendar = .current) {
        let dayCount = max(1, days)
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today
        startDate = start
        func inPeriod(_ date: Date) -> Bool { date >= start && date <= now }

        let periodEvents = snapshot.events.filter { inPeriod($0.occurredAt) }
        let periodUsage = snapshot.usage.filter { inPeriod($0.occurredAt) }
        let activeIDs = Set(periodEvents.map { SpiritProvider(rawValue: $0.provider)?.sessionKey($0.sessionID) ?? $0.sessionID } + periodUsage.map { SpiritProvider.codex.sessionKey($0.sessionID) })
        let selectedSessions = snapshot.sessions.filter {
            (projectID == nil || $0.projectID == projectID) &&
            (activeIDs.contains($0.provider.sessionKey($0.sessionID)) || inPeriod($0.startedAt))
        }.sorted {
            $0.lastObservedAt == $1.lastObservedAt ? $0.id < $1.id : $0.lastObservedAt > $1.lastObservedAt
        }
        sessions = selectedSessions
        let selectedIDs = Set(selectedSessions.map { $0.provider.sessionKey($0.sessionID) })
        let selectedEvents = periodEvents.filter { selectedIDs.contains(SpiritProvider(rawValue: $0.provider)?.sessionKey($0.sessionID) ?? $0.sessionID) }.sorted {
            $0.occurredAt == $1.occurredAt ? $0.eventID < $1.eventID : $0.occurredAt < $1.occurredAt
        }
        events = selectedEvents
        let selectedUsage = periodUsage.filter { selectedIDs.contains(SpiritProvider.codex.sessionKey($0.sessionID)) }.sorted {
            $0.occurredAt == $1.occurredAt ? $0.id < $1.id : $0.occurredAt < $1.occurredAt
        }
        usage = selectedUsage
        toolCount = selectedEvents.filter { $0.kind == .toolStarted }.count
        workingCount = selectedSessions.filter { $0.status == .working }.count
        attentionCount = selectedSessions.filter { $0.status == .attention }.count

        let counts = Dictionary(grouping: selectedEvents) { calendar.startOfDay(for: $0.occurredAt) }
        activity = (0..<dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return DashboardActivityDay(date: date, count: counts[date]?.count ?? 0)
        }

        var latest: [String: UsageRecord] = [:]
        for record in selectedUsage where record.scope == nil || record.scope == .sessionTotal { latest[record.sessionID] = record }
        var total = 0
        var overflow = false
        for record in latest.values {
            let addition = total.addingReportingOverflow(record.totalTokens)
            if addition.overflow || record.totalTokens < 0 { overflow = true; break }
            total = addition.partialValue
        }
        observedTokenTotal = latest.isEmpty || overflow ? nil : total
        tokenSummary = TokenUsageSummary(records: selectedUsage, dates: activity.map(\.date), calendar: calendar)
    }
}

public struct UsageTokenTotals: Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedInputTokens: Int?
    public let reasoningOutputTokens: Int?
    public let totalTokens: Int

    fileprivate init?(records: [UsageRecord]) {
        guard !records.isEmpty else { return nil }
        func sum(_ values: [Int]) -> Int? {
            var result = 0
            for value in values {
                let next = result.addingReportingOverflow(value)
                guard value >= 0, !next.overflow else { return nil }
                result = next.partialValue
            }
            return result
        }
        guard let input = sum(records.map(\.inputTokens)), let output = sum(records.map(\.outputTokens)),
              let total = sum(records.map(\.totalTokens)) else { return nil }
        inputTokens = input; outputTokens = output; totalTokens = total
        cachedInputTokens = records.allSatisfy { $0.cachedInputTokens != nil } ? sum(records.compactMap(\.cachedInputTokens)) : nil
        reasoningOutputTokens = records.allSatisfy { $0.reasoningOutputTokens != nil } ? sum(records.compactMap(\.reasoningOutputTokens)) : nil
    }
}

public struct ModelTokenUsage: Identifiable, Equatable, Sendable {
    public var id: String { modelID.map { "model:\($0)" } ?? "unclassified" }
    public let modelID: String?
    public let totals: UsageTokenTotals?
    public let recordCount: Int
}

public struct DailyTokenUsage: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let totals: UsageTokenTotals?
    public let models: [ModelTokenUsage]
}

public struct TokenUsageSummary: Equatable, Sendable {
    public let totals: UsageTokenTotals?
    public let models: [ModelTokenUsage]
    public let days: [DailyTokenUsage]
    public let deltaRecordCount: Int
    public let cumulativeOnlySessionCount: Int
    public let unclassifiedRecordCount: Int
    public let excludedRecordCount: Int
    /// Immutable reports with uncertain interval/model attribution; never priced or dated as exact usage.
    public let unattributedRecords: [UsageRecord]
    public let observedSessionCount: Int
    /// Valid, deduplicated, date-attributed deltas for downstream API-price conversion.
    public let exactRecords: [UsageRecord]

    fileprivate init(records: [UsageRecord], dates: [Date], calendar: Calendar) {
        var seen: Set<String> = []
        let unique = records.filter { seen.insert($0.id).inserted }
        func valid(_ record: UsageRecord) -> Bool {
            let total = record.inputTokens.addingReportingOverflow(record.outputTokens)
            return record.inputTokens >= 0 && record.outputTokens >= 0 && record.totalTokens >= 0 &&
                !total.overflow && total.partialValue == record.totalTokens &&
                (record.cachedInputTokens ?? 0) >= 0 && (record.cachedInputTokens ?? 0) <= record.inputTokens &&
                (record.cacheWriteInputTokens ?? 0) >= 0 &&
                (record.cacheWriteInputTokens ?? 0) <= record.inputTokens - (record.cachedInputTokens ?? 0) &&
                (record.reasoningOutputTokens ?? 0) >= 0 && (record.reasoningOutputTokens ?? 0) <= record.outputTokens
        }
        let exact = unique.filter { $0.scope == .delta && $0.attribution == .observedDelta && valid($0) }
        exactRecords = exact
        let exactIDs = Set(exact.map(\.id))
        let cumulative = unique.filter { $0.scope == nil || $0.scope == .sessionTotal }
        let cumulativeIDs = Set(cumulative.map(\.id))
        unattributedRecords = unique.filter { !exactIDs.contains($0.id) && !cumulativeIDs.contains($0.id) }
        excludedRecordCount = unattributedRecords.count
        deltaRecordCount = exact.count
        unclassifiedRecordCount = exact.filter { $0.modelID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false }.count + unattributedRecords.count
        let deltaSessions = Set(exact.map(\.sessionID))
        cumulativeOnlySessionCount = Set(cumulative.map(\.sessionID)).subtracting(deltaSessions).count
        observedSessionCount = Set(unique.map(\.sessionID)).count
        totals = UsageTokenTotals(records: exact)
        func modelGroups(_ reports: [UsageRecord]) -> [ModelTokenUsage] {
            let grouped = Dictionary(grouping: reports) { report -> String in
                guard let model = report.modelID, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
                return model
            }
            return grouped.keys.sorted().map { model in
                let records = grouped[model] ?? []
                return ModelTokenUsage(modelID: model.isEmpty ? nil : model, totals: UsageTokenTotals(records: records), recordCount: records.count)
            }
        }
        models = modelGroups(exact)
        let groupedDays = Dictionary(grouping: exact) { calendar.startOfDay(for: $0.occurredAt) }
        days = dates.map { date in
            let reports = groupedDays[date] ?? []
            return DailyTokenUsage(date: date, totals: UsageTokenTotals(records: reports), models: modelGroups(reports))
        }
    }
}
