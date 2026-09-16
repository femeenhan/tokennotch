import Foundation
import CSQLite

public enum DashboardStoreError: Error, Equatable, Sendable {
    case databaseUnavailable
    case invalidMetadata
    case unsupportedVersion
}

// SQLite's pointer stays inside this actor; the wrapper only closes its owned handle.
private final class DatabaseHandle: @unchecked Sendable {
    let pointer: OpaquePointer
    init(_ pointer: OpaquePointer) { self.pointer = pointer }
    deinit { sqlite3_close(pointer) }
}

public actor DashboardStore {
    private let database: DatabaseHandle
    private var states: [String: SessionState] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL) throws {
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        var pointer: OpaquePointer?
        guard sqlite3_open_v2(url.path, &pointer, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let pointer else {
            if let pointer { sqlite3_close(pointer) }
            throw DashboardStoreError.databaseUnavailable
        }
        let handle = DatabaseHandle(pointer)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        sqlite3_busy_timeout(pointer, 3_000)
        try Self.execute(pointer, "PRAGMA journal_mode=WAL")
        try Self.execute(pointer, "PRAGMA foreign_keys=ON")
        let version = try Self.rows(pointer, "PRAGMA user_version").first?.first ?? "0"
        guard version == "0" || version == "1" else { throw DashboardStoreError.unsupportedVersion }
        try Self.execute(pointer, "BEGIN IMMEDIATE")
        do {
            try Self.execute(pointer, "CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, data TEXT NOT NULL)")
            try Self.execute(pointer, "CREATE TABLE IF NOT EXISTS projects (id TEXT PRIMARY KEY, path TEXT NOT NULL UNIQUE, name TEXT NOT NULL)")
            try Self.execute(pointer, "CREATE TABLE IF NOT EXISTS assignments (session_id TEXT PRIMARY KEY, project_id TEXT REFERENCES projects(id))")
            try Self.execute(pointer, "CREATE TABLE IF NOT EXISTS usage (id TEXT PRIMARY KEY, occurred_at REAL NOT NULL, data TEXT NOT NULL)")
            try Self.execute(pointer, "PRAGMA user_version=1")
            try Self.execute(pointer, "COMMIT")
        } catch {
            try? Self.execute(pointer, "ROLLBACK")
            throw error
        }
        self.database = handle
        let decodedEvents: [SpiritEvent] = try Self.rows(pointer, "SELECT data FROM events ORDER BY rowid").map {
            try JSONDecoder().decode(SpiritEvent.self, from: Data($0[0].utf8))
        }
        let events = decodedEvents.sorted { lhs, rhs in
            lhs.occurredAt == rhs.occurredAt ? lhs.receivedAt < rhs.receivedAt : lhs.occurredAt < rhs.occurredAt
        }
        var restored: [String: SessionState] = [:]
        for event in events { restored = reduce(sessions: restored, event: event) }
        self.states = restored.mapValues { $0.status == .ended ? $0 : .restored() }
    }

    public func record(_ event: SpiritEvent) throws {
        guard event.provider == "codex", event.schemaVersion == 1,
              !event.eventID.isEmpty, !event.sessionID.isEmpty else { throw DashboardStoreError.invalidMetadata }
        let countKeys: Set<String> = ["inputTokens", "outputTokens", "cachedInputTokens", "reasoningOutputTokens", "totalTokens",
                                      "input_tokens", "output_tokens", "cached_input_tokens", "reasoning_output_tokens", "total_tokens"]
        var payload = event.payload
        payload.usageCounts = payload.usageCounts?.filter { countKeys.contains($0.key) && $0.value >= 0 }
        let storedEvent = SpiritEvent(schemaVersion: event.schemaVersion, eventID: event.eventID, provider: event.provider,
                                      sessionID: event.sessionID, parentSessionID: event.parentSessionID, turnID: event.turnID,
                                      kind: event.kind, occurredAt: event.occurredAt, receivedAt: event.receivedAt,
                                      projectID: event.projectID, worktreeID: event.worktreeID, source: event.source,
                                      sourceVersion: event.sourceVersion, payload: payload)
        let bytes = try encoder.encode(storedEvent)
        guard bytes.count <= 32_768, let json = String(data: bytes, encoding: .utf8) else { throw DashboardStoreError.invalidMetadata }
        try Self.execute(database.pointer, "INSERT OR IGNORE INTO events(id,data) VALUES (?,?)", [event.eventID, json])
        if sqlite3_changes(database.pointer) > 0 { states = reduce(sessions: states, event: event) }
    }

    public func snapshot(now: Date = Date()) throws -> DashboardSnapshot {
        let decodedEvents: [SpiritEvent] = try Self.rows(database.pointer, "SELECT data FROM events ORDER BY rowid").map {
            try decoder.decode(SpiritEvent.self, from: Data($0[0].utf8))
        }
        let events = decodedEvents.sorted { lhs, rhs in
            lhs.occurredAt == rhs.occurredAt ? lhs.eventID < rhs.eventID : lhs.occurredAt < rhs.occurredAt
        }
        let projects = try Self.rows(database.pointer, "SELECT id,path,name FROM projects ORDER BY name,id").map {
            guard let id = UUID(uuidString: $0[0]) else { throw DashboardStoreError.invalidMetadata }
            return DashboardProject(id: id, path: $0[1], name: $0[2])
        }
        let assignments: [String: UUID?] = Dictionary(uniqueKeysWithValues: try Self.rows(database.pointer, "SELECT session_id,project_id FROM assignments").map { ($0[0], UUID(uuidString: $0[1])) })
        let groups = Dictionary(grouping: events, by: \.sessionID)
        let unsortedSessions: [DashboardSession] = groups.map { id, events in
            DashboardSession(id: id, status: states[id]?.status ?? .unknown,
                             startedAt: events.map(\.occurredAt).min() ?? now,
                             lastObservedAt: events.map(\.receivedAt).max() ?? now,
                             projectID: assignments[id] ?? events.last?.projectID)
        }
        let usage = try Self.rows(database.pointer, "SELECT data FROM usage ORDER BY occurred_at,id").map {
            try decoder.decode(UsageRecord.self, from: Data($0[0].utf8))
        }
        var combinedSessions = unsortedSessions
        for (id, records) in Dictionary(grouping: usage, by: \.sessionID) where groups[id] == nil {
            combinedSessions.append(DashboardSession(id: id, status: .unknown,
                                                      startedAt: records.map(\.occurredAt).min() ?? now,
                                                      lastObservedAt: records.map(\.occurredAt).max() ?? now,
                                                      projectID: assignments[id] ?? nil))
        }
        let sessions = combinedSessions.sorted { lhs, rhs in
            lhs.lastObservedAt == rhs.lastObservedAt ? lhs.id < rhs.id : lhs.lastObservedAt > rhs.lastObservedAt
        }
        return DashboardSnapshot(projects: projects, sessions: sessions, events: events, usage: usage)
    }

    public func registerProject(path: String, name: String) throws -> DashboardProject {
        guard path.hasPrefix("/"), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              path.utf8.count < 4096, name.utf8.count < 1024 else { throw DashboardStoreError.invalidMetadata }
        let path = URL(fileURLWithPath: path).standardizedFileURL.path
        let existing = try Self.rows(database.pointer, "SELECT id FROM projects WHERE path=?", [path]).first?.first
        let id = existing.flatMap(UUID.init(uuidString:)) ?? UUID()
        try Self.execute(database.pointer, "INSERT INTO projects(id,path,name) VALUES (?,?,?) ON CONFLICT(path) DO UPDATE SET name=excluded.name", [id.uuidString, path, name])
        return DashboardProject(id: id, path: path, name: name)
    }

    public func assignProject(sessionID: String, projectID: UUID?) throws {
        let known = try Self.rows(database.pointer, "SELECT id FROM events WHERE json_extract(data,'$.sessionID')=? UNION ALL SELECT id FROM usage WHERE json_extract(data,'$.sessionID')=? LIMIT 1", [sessionID, sessionID])
        guard !known.isEmpty else { throw DashboardStoreError.invalidMetadata }
        try Self.execute(database.pointer, "INSERT INTO assignments(session_id,project_id) VALUES (?,?) ON CONFLICT(session_id) DO UPDATE SET project_id=excluded.project_id", [sessionID, projectID?.uuidString])
    }

    public func recordUsage(_ records: [UsageRecord]) throws {
        try Self.execute(database.pointer, "BEGIN IMMEDIATE")
        do {
            for record in records {
                guard !record.id.isEmpty, !record.sessionID.isEmpty, record.inputTokens >= 0,
                      record.outputTokens >= 0, record.totalTokens >= 0,
                      (record.cachedInputTokens ?? 0) >= 0, (record.reasoningOutputTokens ?? 0) >= 0,
                      (record.cachedInputTokens ?? 0) <= record.inputTokens,
                      (record.cacheWriteInputTokens ?? 0) >= 0,
                      (record.cacheWriteInputTokens ?? 0) <= record.inputTokens - (record.cachedInputTokens ?? 0),
                      (record.reasoningOutputTokens ?? 0) <= record.outputTokens else { throw DashboardStoreError.invalidMetadata }
                let data = try encoder.encode(record)
                guard data.count <= 32_768, let json = String(data: data, encoding: .utf8) else { throw DashboardStoreError.invalidMetadata }
                let sql: String
                if record.scope == nil || record.scope == .sessionTotal {
                    sql = "INSERT INTO usage(id,occurred_at,data) VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET occurred_at=excluded.occurred_at,data=excluded.data WHERE excluded.occurred_at>=usage.occurred_at AND COALESCE(json_extract(usage.data,'$.scope'),'sessionTotal')='sessionTotal'"
                } else {
                    sql = "INSERT OR IGNORE INTO usage(id,occurred_at,data) VALUES (?,?,?)"
                }
                try Self.execute(database.pointer, sql, [record.id, String(record.occurredAt.timeIntervalSince1970), json])
            }
            try Self.execute(database.pointer, "COMMIT")
        } catch {
            try? Self.execute(database.pointer, "ROLLBACK")
            throw error
        }
    }

    private static func prepare(_ db: OpaquePointer, _ sql: String, _ values: [String?]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw DashboardStoreError.databaseUnavailable }
        for (offset, value) in values.enumerated() {
            let result = value.map { sqlite3_bind_text(statement, Int32(offset + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
                ?? sqlite3_bind_null(statement, Int32(offset + 1))
            if result != SQLITE_OK { sqlite3_finalize(statement); throw DashboardStoreError.databaseUnavailable }
        }
        return statement
    }

    private static func execute(_ db: OpaquePointer, _ sql: String, _ values: [String?] = []) throws {
        let statement = try prepare(db, sql, values)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else { throw DashboardStoreError.databaseUnavailable }
    }

    private static func rows(_ db: OpaquePointer, _ sql: String, _ values: [String?] = []) throws -> [[String]] {
        let statement = try prepare(db, sql, values)
        defer { sqlite3_finalize(statement) }
        var rows: [[String]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else { throw DashboardStoreError.databaseUnavailable }
            rows.append((0..<sqlite3_column_count(statement)).map {
                sqlite3_column_text(statement, $0).map { String(cString: $0) } ?? ""
            })
        }
    }
}
