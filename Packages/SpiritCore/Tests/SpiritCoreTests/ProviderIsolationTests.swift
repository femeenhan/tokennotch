import Foundation
import CSQLite
import Testing
@testable import SpiritCore

@Suite("Provider isolation")
struct ProviderIsolationTests {
    private func event(_ provider: String, kind: SpiritEvent.Kind, id: String = "same", time: Double = 100) -> SpiritEvent {
        SpiritEvent(eventID: id, provider: provider, sessionID: "shared-session", kind: kind,
                    occurredAt: Date(timeIntervalSince1970: time), receivedAt: Date(timeIntervalSince1970: time),
                    source: "hook", sourceVersion: "1")
    }

    @Test func providersWithIdenticalIDsRemainIndependentAcrossReopening() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("db.sqlite")
        let store = try DashboardStore(url: url)
        try await store.record(event("codex", kind: .toolStarted))
        try await store.record(event("claude", kind: .needsInput))
        try await store.record(event("claude", kind: .needsInput))
        let snapshot = try await store.snapshot()
        #expect(snapshot.events.count == 2)
        #expect(snapshot.filtered(for: .codex).sessions.first?.status == .working)
        #expect(snapshot.filtered(for: .claude).sessions.first?.status == .attention)
        #expect(Set(snapshot.sessions.map(\.id)).count == 2)
        let project = try await store.registerProject(path: "/tmp/claude-only", name: "Claude")
        try await store.assignProject(sessionID: "shared-session", provider: .claude, projectID: project.id)
        let reopened = try DashboardStore(url: url)
        let restored = try await reopened.snapshot()
        #expect(restored.filtered(for: .codex).sessions.first?.projectID == nil)
        #expect(restored.filtered(for: .claude).sessions.first?.projectID == project.id)
        #expect(DashboardQuery(snapshot: snapshot.filtered(for: .claude), days: 1, now: Date(timeIntervalSince1970: 101)).events.count == 1)
    }

    @Test func streamRoutesAndCompletionDoesNotReplaceOtherProvidersWork() {
        var streams = ProviderSpiritStreams()
        streams.receive(event("codex", kind: .toolStarted))
        streams.receive(event("claude", kind: .sessionEnded))
        #expect(streams.stream(for: .codex).state == .working)
        #expect(streams.stream(for: .claude).state == .completed)
        if let id = streams.stream(for: .claude).completionPresentationID {
            streams.finishCompletionPresentation(id: id, provider: .claude)
        }
        #expect(streams.stream(for: .codex).state == .working)
        #expect(streams.stream(for: .claude).state == .idle)
        streams.receive(event("unrecognized", kind: .needsInput))
        #expect(streams.stream(for: .codex).state == .working)
        #expect(streams.stream(for: .gemini).sessions.isEmpty)
    }
    @Test func providerSelectionAndUsageStayScoped() {
        #expect(ProviderSelection.normalized([.codex, .codex, .claude, .gemini, .grok]) == [.codex, .claude, .gemini])
        #expect(ProviderSelection.normalized([]).isEmpty)
        let usage = UsageRecord(id: "u", sessionID: "shared-session", occurredAt: Date(), inputTokens: 1, outputTokens: 1, totalTokens: 2)
        let snapshot = DashboardSnapshot(usage: [usage])
        #expect(snapshot.filtered(for: .codex).usage == [usage])
        #expect(snapshot.filtered(for: .claude).usage.isEmpty)
        #expect(snapshot.filtered(for: .gemini).usage.isEmpty)
        #expect(snapshot.filtered(for: .grok).usage.isEmpty)
    }

    @Test func delayedEventsWithoutTurnIDsCannotOverwriteNewerWork() {
        var streams = ProviderSpiritStreams()
        streams.receive(event("claude", kind: .toolStarted, time: 102))
        streams.receive(event("claude", kind: .turnStopped, id: "late", time: 101))
        #expect(streams.stream(for: .claude).state == .working)
    }

    @Test(arguments: [SpiritProvider.claude, .gemini, .grok])
    func socketAcceptsAdditionalProviders(provider: SpiritProvider) async throws {
        let directory = URL(fileURLWithPath: "/tmp/spirit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let socket = directory.appendingPathComponent("events.sock")
        let input = event(provider.rawValue, kind: .toolStarted)
        try await confirmation("provider event delivered") { received in
            let server = try SpiritSocketServer(url: socket) { delivered in
                #expect(delivered == input)
                received()
            }
            defer { server.stop() }
            #expect(SpiritSocketClient.send(try SpiritWireEnvelope(event: input).encodedLine(), to: socket))
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    @Test func craftedProviderPrefixCannotCollideWithCodexID() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("db.sqlite")
        let store = try DashboardStore(url: url)
        let crafted = "claude:" + Data("shared-session".utf8).base64EncodedString()
        let codex = SpiritEvent(eventID: "claude:" + Data("same".utf8).base64EncodedString(), provider: "codex", sessionID: crafted,
                                kind: .toolStarted, occurredAt: Date(timeIntervalSince1970: 100), receivedAt: Date(timeIntervalSince1970: 100), source: "hook", sourceVersion: "1")
        try await store.record(codex)
        try await store.record(event("claude", kind: .needsInput))
        let snapshot = try await store.snapshot()
        #expect(snapshot.events.count == 2)
        #expect(snapshot.sessions.count == 2)
        #expect(Set(snapshot.sessions.map(\.id)).count == 2)
        #expect(snapshot.filtered(for: .codex).sessions.first?.status == .working)
        #expect(snapshot.filtered(for: .claude).sessions.first?.status == .attention)
    }

    @Test func versionOneRawCodexIDsAndAssignmentsMigrateAndDeduplicate() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let legacy = event("codex", kind: .sessionEnded)
        let data = String(decoding: try JSONEncoder().encode(legacy), as: UTF8.self).replacingOccurrences(of: "'", with: "''")
        let projectID = UUID()
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        let sql = """
        CREATE TABLE events (id TEXT PRIMARY KEY, data TEXT NOT NULL);
        CREATE TABLE projects (id TEXT PRIMARY KEY, path TEXT NOT NULL UNIQUE, name TEXT NOT NULL);
        CREATE TABLE assignments (session_id TEXT PRIMARY KEY, project_id TEXT REFERENCES projects(id));
        CREATE TABLE usage (id TEXT PRIMARY KEY, occurred_at REAL NOT NULL, data TEXT NOT NULL);
        INSERT INTO events VALUES ('same','\(data)');
        INSERT INTO projects VALUES ('\(projectID.uuidString)','/tmp/legacy','Legacy');
        INSERT INTO assignments VALUES ('shared-session','\(projectID.uuidString)');
        PRAGMA user_version=1;
        """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let store = try DashboardStore(url: url)
        try await store.record(legacy)
        try await store.record(event("claude", kind: .toolStarted))
        let snapshot = try await store.snapshot()
        #expect(snapshot.events.count == 2)
        let codex = try #require(snapshot.filtered(for: .codex).sessions.first)
        #expect(codex.id == "shared-session")
        #expect(codex.status == .ended)
        #expect(codex.projectID == projectID)
        #expect(snapshot.filtered(for: .claude).sessions.first?.projectID == nil)
    }

}
