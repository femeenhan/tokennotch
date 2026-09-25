import Foundation
import Testing
@testable import SpiritCore

struct ClaudeTranscriptUsageTests {
    private let seoul: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()
    private let now = ISO8601DateFormatter().date(from: "2026-09-25T12:00:00Z")!

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func line(id: String?, requestId: String? = nil, timestamp: String = "2026-09-25T03:00:00.000Z",
                      input: Int = 1, output: Int = 10, cacheCreate: Int = 100, cacheRead: Int = 1000,
                      model: String = "claude-opus-5-5", type: String = "assistant") -> String {
        var message: [String: Any] = [
            "model": model, "role": "assistant", "type": "message",
            "content": [["type": "text", "text": "secret response text"]],
            "usage": ["input_tokens": input, "output_tokens": output,
                      "cache_creation_input_tokens": cacheCreate, "cache_read_input_tokens": cacheRead]
        ]
        if let id { message["id"] = id }
        var row: [String: Any] = ["type": type, "timestamp": timestamp, "message": message]
        if let requestId { row["requestId"] = requestId }
        let data = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func write(_ lines: [String], to url: URL, trailingNewline: Bool = true) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        try Data(text.utf8).write(to: url)
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    @Test func missingRootReturnsEmpty() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)")
        let usage = await ClaudeTranscriptUsageReader(root: root, calendar: seoul).read(now: now)
        #expect(usage.daily.isEmpty)
        #expect(usage.totalTokens == 0)
        #expect(usage.observedAt == now)
    }

    @Test func dedupesWithinAndAcrossFilesIncludingNestedSubagents() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // Streamed blocks: same id, growing output_tokens → keep larger.
        try write([line(id: "msg_a", output: 5), line(id: "msg_a", output: 10)],
                  to: root.appendingPathComponent("proj/s1.jsonl"))
        // Resumed session copies msg_a into a new file; plus a new message.
        try write([line(id: "msg_a", output: 10), line(id: "msg_b", output: 20)],
                  to: root.appendingPathComponent("proj/s2.jsonl"))
        // Nested subagent transcript; requestId fallback key.
        try write([line(id: nil, requestId: "req_c", output: 30), line(id: nil, requestId: "req_c", output: 30),
                   line(id: nil, requestId: nil, output: 999)],
                  to: root.appendingPathComponent("proj/s1/subagents/agent-1.jsonl"))
        let usage = await ClaudeTranscriptUsageReader(root: root, calendar: seoul).read(now: now)
        let expected = (1 + 10 + 100 + 1000) + (1 + 20 + 100 + 1000) + (1 + 30 + 100 + 1000)
        #expect(usage.totalTokens == expected)
        #expect(usage.daily == [CodexDailyUsageBucket(startDate: "2026-09-25", tokens: expected)])
    }

    @Test func incrementalAppendCompletesPartialLine() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("proj/s.jsonl")
        try write([line(id: "msg_1")], to: file)
        let reader = ClaudeTranscriptUsageReader(root: root, calendar: seoul)
        #expect(await reader.read(now: now).totalTokens == 1111)

        let second = line(id: "msg_2", output: 20)
        let splitIndex = second.index(second.startIndex, offsetBy: second.count / 2)
        try append(String(second[..<splitIndex]), to: file)
        #expect(await reader.read(now: now).totalTokens == 1111) // partial line not yet counted
        try append(String(second[splitIndex...]) + "\n", to: file)
        #expect(await reader.read(now: now).totalTokens == 1111 + 1121)
        // Re-reading unchanged state never double counts.
        #expect(await reader.read(now: now).totalTokens == 1111 + 1121)
        // Streamed duplicate with larger output replaces the earlier value.
        try append(line(id: "msg_2", output: 50) + "\n", to: file)
        #expect(await reader.read(now: now).totalTokens == 1111 + 1151)
    }

    @Test func truncatedOrReplacedFileIsReReadWithoutDoubleCounting() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("proj/s.jsonl")
        try write([line(id: "msg_1"), line(id: "msg_2")], to: file)
        let reader = ClaudeTranscriptUsageReader(root: root, calendar: seoul)
        #expect(await reader.read(now: now).totalTokens == 2222)
        try FileManager.default.removeItem(at: file)
        try write([line(id: "msg_1"), line(id: "msg_3")], to: file)
        #expect(await reader.read(now: now).totalTokens == 3333)
    }

    @Test func bucketsDaysInCalendarTimeZone() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write([
            line(id: "a", timestamp: "2026-09-24T14:59:59.999Z", input: 0, output: 1, cacheCreate: 0, cacheRead: 0),
            line(id: "b", timestamp: "2026-09-24T15:30:00Z", input: 0, output: 2, cacheCreate: 0, cacheRead: 0),
            line(id: "c", timestamp: "2026-09-25T10:07:02.301Z", input: 0, output: 4, cacheCreate: 0, cacheRead: 0)
        ], to: root.appendingPathComponent("p/s.jsonl"))
        let usage = await ClaudeTranscriptUsageReader(root: root, calendar: seoul).read(now: now)
        #expect(usage.daily == [
            CodexDailyUsageBucket(startDate: "2026-09-24", tokens: 1),
            CodexDailyUsageBucket(startDate: "2026-09-25", tokens: 6)
        ])
        #expect(usage.totalTokens == 7)
    }

    @Test func ignoresMalformedNonAssistantAndSyntheticLines() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write([
            "{not json \"usage\" \"assistant\"",
            "",
            line(id: "u", type: "user"),
            line(id: "s", model: "<synthetic>"),
            #"{"type":"assistant","message":{"id":"x","usage":{"output_tokens":5}}}"#, // no timestamp
            #"{"type":"assistant","timestamp":"2026-09-25T01:00:00Z","message":{"id":"partial","usage":{"output_tokens":5}}}"#,
            line(id: "ok")
        ], to: root.appendingPathComponent("p/s.jsonl"))
        try write([line(id: "ignored")], to: root.appendingPathComponent("p/notes.txt"))
        let usage = await ClaudeTranscriptUsageReader(root: root, calendar: seoul).read(now: now)
        #expect(usage.totalTokens == 5 + 1111)
    }

    @Test func excludesEntriesOutsideWindowAndPrunesAsTimeAdvances() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write([
            line(id: "old", timestamp: "2026-09-10T03:00:00Z"),
            line(id: "edge", timestamp: "2026-09-19T03:00:00Z"),
            line(id: "new", timestamp: "2026-09-25T03:00:00Z")
        ], to: root.appendingPathComponent("p/s.jsonl"))
        // Old file by modification date is skipped entirely on first scan.
        let stale = root.appendingPathComponent("p/stale.jsonl")
        try write([line(id: "stale", timestamp: "2026-09-25T03:00:00Z")], to: stale)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: stale.path)

        let reader = ClaudeTranscriptUsageReader(root: root, calendar: seoul, maxAgeDays: 7)
        let usage = await reader.read(now: now)
        #expect(usage.daily.map(\.startDate) == ["2026-09-19", "2026-09-25"])
        #expect(usage.totalTokens == 2222)
        let later = await reader.read(now: now.addingTimeInterval(86_400))
        #expect(later.daily.map(\.startDate) == ["2026-09-25"])
        #expect(later.totalTokens == 1111)
    }

    @Test func skipsSymlinkedFiles() async throws {
        let root = try makeRoot()
        let outside = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let target = outside.appendingPathComponent("t.jsonl")
        try write([line(id: "linked")], to: target)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("p"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("p/link.jsonl"), withDestinationURL: target)
        let usage = await ClaudeTranscriptUsageReader(root: root, calendar: seoul).read(now: now)
        #expect(usage.totalTokens == 0)
    }
}
