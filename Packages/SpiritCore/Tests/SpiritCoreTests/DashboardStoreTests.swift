import Foundation
import Testing
@testable import SpiritCore

@Suite("DashboardStore")
struct DashboardStoreTests {
    private func database() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("dashboard.sqlite")
    }

    private func event(_ id: String = "event-1", kind: SpiritEvent.Kind = .toolStarted, time: Double = 100) -> SpiritEvent {
        SpiritEvent(eventID: id, provider: "codex", sessionID: "session-1", kind: kind,
                    occurredAt: Date(timeIntervalSince1970: time), receivedAt: Date(timeIntervalSince1970: time),
                    source: "hook", sourceVersion: "1")
    }

    @Test func duplicateEventsArePersistedOnce() async throws {
        let store = try DashboardStore(url: database())
        for _ in 0..<100 { try await store.record(event()) }
        let snapshot = try await store.snapshot()
        #expect(snapshot.events.count == 1)
        #expect(snapshot.sessions.first?.status == .working)
    }

    @Test func reopenedActiveSessionIsUnknownAndEndedSessionStaysEnded() async throws {
        let url = try database()
        let store = try DashboardStore(url: url)
        try await store.record(event())
        let reopened = try DashboardStore(url: url)
        #expect(try await reopened.snapshot().events.count == 1)
        #expect(try await reopened.snapshot().sessions.first?.status == .unknown)
        try await reopened.record(event("end", kind: .sessionEnded, time: 101))
        let ended = try DashboardStore(url: url)
        #expect(try await ended.snapshot().sessions.first?.status == .ended)
    }

    @Test func projectAssignmentSurvivesReopening() async throws {
        let url = try database()
        let store = try DashboardStore(url: url)
        try await store.record(event())
        let project = try await store.registerProject(path: "/tmp/my-project", name: "My Project")
        let same = try await store.registerProject(path: "/tmp/my-project/", name: "Renamed")
        #expect(project.id == same.id)
        try await store.assignProject(sessionID: "session-1", projectID: project.id)
        let reopened = try DashboardStore(url: url)
        #expect(try await reopened.snapshot().sessions.first?.projectID == project.id)
        #expect(try await reopened.snapshot().projects.count == 1)
    }

    @Test func unknownPayloadKeysNeverReachStorage() async throws {
        let url = try database()
        let encoded = try JSONEncoder().encode(event())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["payload"] = ["prompt": "SENSITIVE_PROMPT_123", "command": "SENSITIVE_COMMAND_456", "toolCategory": "shell"]
        let decoded = try JSONDecoder().decode(SpiritEvent.self, from: JSONSerialization.data(withJSONObject: object))
        let store = try DashboardStore(url: url)
        try await store.record(decoded)
        let snapshot = try await store.snapshot()
        #expect(snapshot.events.first?.payload.toolCategory == "shell")
        let files = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        for file in files {
            let bytes = try Data(contentsOf: file)
            #expect(bytes.range(of: Data("SENSITIVE_PROMPT_123".utf8)) == nil)
            #expect(bytes.range(of: Data("SENSITIVE_COMMAND_456".utf8)) == nil)
        }
    }

    @Test func usageDictionaryStoresOnlyRecognizedCountKeys() async throws {
        let store = try DashboardStore(url: database())
        let source = event()
        let metadata = SpiritEvent(eventID: source.eventID, provider: source.provider, sessionID: source.sessionID,
                                   kind: .usageObserved, occurredAt: source.occurredAt, receivedAt: source.receivedAt,
                                   source: source.source, sourceVersion: source.sourceVersion,
                                   payload: .init(usageCounts: ["inputTokens": 4, "SENSITIVE_PROMPT_IN_KEY": 7]))
        try await store.record(metadata)
        #expect(try await store.snapshot().events.first?.payload.usageCounts == ["inputTokens": 4])
    }

    @Test func cumulativeUsageUsesLatestRecordAndSurvivesReopening() async throws {
        let url = try database()
        let store = try DashboardStore(url: url)
        func usage(_ time: Double, _ input: Int) -> UsageRecord {
            UsageRecord(id: "codex-total:session-1", sessionID: "session-1", modelID: nil, occurredAt: Date(timeIntervalSince1970: time), inputTokens: input, outputTokens: 2, cachedInputTokens: nil, reasoningOutputTokens: nil, totalTokens: input + 2)
        }
        try await store.recordUsage([usage(100, 5), usage(101, 10), usage(100, 5)])
        let snapshot = try await store.snapshot()
        #expect(snapshot.usage.count == 1)
        #expect(snapshot.usage.first?.inputTokens == 10)
        let reopened = try DashboardStore(url: url)
        #expect(try await reopened.snapshot().usage == snapshot.usage)
    }

    @Test func invalidUsageBatchRollsBackAllRecords() async throws {
        let store = try DashboardStore(url: database())
        let valid = UsageRecord(id: "good", sessionID: "session-1", modelID: nil, occurredAt: Date(), inputTokens: 1, outputTokens: 1, cachedInputTokens: nil, reasoningOutputTokens: nil, totalTokens: 2)
        let invalid = UsageRecord(id: "bad", sessionID: "session-1", modelID: nil, occurredAt: Date(), inputTokens: -1, outputTokens: 1, cachedInputTokens: nil, reasoningOutputTokens: nil, totalTokens: 0)
        await #expect(throws: DashboardStoreError.invalidMetadata) { try await store.recordUsage([valid, invalid]) }
        #expect(try await store.snapshot().usage.isEmpty)
    }

    @Test func usageOnlySessionCanBeManuallyAssignedToProject() async throws {
        let store = try DashboardStore(url: database())
        let usage = UsageRecord(id: "usage-only", sessionID: "session-usage", occurredAt: Date(), inputTokens: 1, outputTokens: 0, totalTokens: 1)
        try await store.recordUsage([usage])
        let project = try await store.registerProject(path: "/tmp/usage-project", name: "Usage Project")
        try await store.assignProject(sessionID: "session-usage", projectID: project.id)
        let session = try #require(await store.snapshot().sessions.first)
        #expect(session.id == "session-usage")
        #expect(session.projectID == project.id)
        #expect(session.status == .unknown)
    }

    @Test func deltaIdentityIsImmutableButLatestCumulativeCanUpdate() async throws {
        let url = try database()
        let store = try DashboardStore(url: url)
        func row(_ id: String, _ total: Int, _ time: Double, scope: UsageRecord.Scope) -> UsageRecord {
            UsageRecord(id: id, sessionID: "session-1", modelID: "gpt-6-astra", occurredAt: Date(timeIntervalSince1970: time),
                        inputTokens: total, outputTokens: 0, totalTokens: total, scope: scope, attribution: scope == .delta ? .observedDelta : nil)
        }
        try await store.recordUsage([row("delta", 3, 100, scope: .delta), row("total", 10, 100, scope: .sessionTotal)])
        try await store.recordUsage([row("delta", 5, 101, scope: .delta), row("total", 20, 101, scope: .sessionTotal)])
        let reopened = try DashboardStore(url: url)
        let rows = try await reopened.snapshot().usage
        #expect(rows.count == 2)
        #expect(rows.first { $0.id == "delta" }?.totalTokens == 3)
        #expect(rows.first { $0.id == "total" }?.totalTokens == 20)
    }

    @Test func invalidCachedOrReasoningSubsetsNeverPersist() async throws {
        let store = try DashboardStore(url: database())
        let invalid = UsageRecord(id: "bad-subset", sessionID: "a", occurredAt: Date(), inputTokens: 1,
                                  outputTokens: 2, cachedInputTokens: 2, reasoningOutputTokens: 3,
                                  totalTokens: 3, scope: .delta, attribution: .observedDelta)
        await #expect(throws: DashboardStoreError.invalidMetadata) { try await store.recordUsage([invalid]) }
        #expect(try await store.snapshot().usage.isEmpty)
    }

    @Test func invalidCacheWriteMetadataIsRejected() async throws {
        let store = try DashboardStore(url: database())
        let invalid = UsageRecord(id: "cache-write", sessionID: "a", occurredAt: Date(), inputTokens: 10,
                                  outputTokens: 2, cachedInputTokens: 5, totalTokens: 12,
                                  cacheWriteInputTokens: -1, scope: .delta, attribution: .observedDelta)
        await #expect(throws: DashboardStoreError.invalidMetadata) { try await store.recordUsage([invalid]) }
    }
}
