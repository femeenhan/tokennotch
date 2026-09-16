import Foundation
import Testing
@testable import SpiritCore

struct UsageFileReaderTests {
    private func fixture(_ content: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("selected.jsonl")
        try Data(content.utf8).write(to: url)
        return url
    }
    private var header: String {
        "{\"type\":\"session_meta\",\"payload\":{\"id\":\"fixture-session\"}}\n{\"type\":\"turn_context\",\"payload\":{\"model\":\"fixture-model\"}}\n"
    }
    private func usage(_ input: Int = 10, output: Int = 3, at: String = "2026-09-16T01:02:03.456Z") -> String {
        "{\"timestamp\":\"\(at)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"output_tokens\":\(output),\"cached_input_tokens\":2,\"reasoning_output_tokens\":1,\"total_tokens\":\(input + output)}}}}"
    }
    @Test func latestCumulativeTotalsAreNotSummedAndRepeatedPollIsEmpty() async throws {
        let url = try fixture(header + usage() + "\n" + usage() + "\n" + usage(20) + "\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reader = UsageFileReader(url: url)
        let records = try await reader.read()
        let total = records.first { $0.scope == .sessionTotal }
        #expect(records.count == 3) // One historical baseline, one delta, one mutable total.
        #expect(total?.id == "codex-total:fixture-session")
        #expect(total?.inputTokens == 20)
        #expect(total?.totalTokens == 23)
        #expect(total?.modelID == nil) // A cumulative session total is not the latest model's usage.
        #expect(total?.cachedInputTokens == 2)
        #expect(total?.reasoningOutputTokens == 1)
        #expect(try await reader.read().isEmpty)
    }
    @Test func partialLastLineWaitsForNewline() async throws {
        let line = usage()
        let url = try fixture(header + String(line.prefix(30)))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reader = UsageFileReader(url: url)
        #expect(try await reader.read().isEmpty)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((String(line.dropFirst(30)) + "\n").utf8))
        try handle.close()
        #expect(try await reader.read().first(where: { $0.scope == .sessionTotal })?.totalTokens == 13)
    }
    @Test func replacementAndSameInodeRewriteClearSessionAndCursor() async throws {
        let url = try fixture(header + usage() + "\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reader = UsageFileReader(url: url)
        #expect(try await reader.read().count == 2)
        try Data((header.replacingOccurrences(of: "fixture-session", with: "another-session") + usage(40) + "\n").utf8).write(to: url, options: .atomic)
        #expect(try await reader.read().first?.sessionID == "another-session")
        try Data((header + usage(70) + "\n").utf8).write(to: url)
        #expect(try await reader.read().first?.inputTokens == 70)
    }
    @Test func malformedUnknownAndSensitiveContentNeverBecomeMetadata() async throws {
        let sensitive = "{\"type\":\"response_item\",\"payload\":{\"content\":\"SECRET PROMPT PATCH\"}}\n"
        let invalid = usage().replacingOccurrences(of: "\"input_tokens\":10", with: "\"input_tokens\":-1")
        let overflow = usage().replacingOccurrences(of: "\"input_tokens\":10", with: "\"input_tokens\":9223372036854775808")
        let url = try fixture(header + sensitive + "not JSON\n" + invalid + "\n" + overflow + "\n" + usage(0, output: 0).replacingOccurrences(of: "\"cached_input_tokens\":2,\"reasoning_output_tokens\":1,", with: "") + "\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reader = UsageFileReader(url: url)
        let records = try await reader.read()
        #expect(records.count == 2)
        #expect(records.first?.totalTokens == 0)
        #expect(records.first?.cachedInputTokens == nil)
        #expect(await reader.unsupportedRecordCount >= 3)
        let encoded = String(decoding: try JSONEncoder().encode(records), as: UTF8.self)
        #expect(!encoded.contains("SECRET"))
    }
    @Test func lastOnlyUsageIsNotMistakenForSessionTotalAndOversizedLineIsSkipped() async throws {
        let lastOnly = usage().replacingOccurrences(of: "total_token_usage", with: "last_token_usage")
        let url = try fixture(header + lastOnly + "\n" + String(repeating: "x", count: 1_100_000) + "\n" + usage() + "\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reader = UsageFileReader(url: url)
        #expect(try await reader.read().count == 2)
        #expect(await reader.unsupportedRecordCount >= 2)
    }
    @Test func invalidSessionMetadataMustNotAttachUsageToPreviousSession() async throws {
        let url = try fixture(header + usage() + "\n{\"type\":\"session_meta\",\"payload\":{\"id\":\"not a session id\"}}\n" + usage(50) + "\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reader = UsageFileReader(url: url)
        #expect(try await reader.read().first?.inputTokens == 10)
    }
    @Test func undecodableSessionHeaderClearsContextAndUnknownSchemaIsReported() async throws {
        let url = try fixture(header + usage() + "\n{\"type\":\"session_meta\",\"payload\":{\"id\":123}}\n" + usage(50) + "\n{\"type\":\"future_format\",\"payload\":{}}\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reader = UsageFileReader(url: url)
        #expect(try await reader.read().first?.inputTokens == 10)
        #expect(await reader.unsupportedRecordCount == 3)
    }
    @Test func deltasKeepReportedDayAndModelWithoutAttributingTheHistoricBaseline() async throws {
        let first = usage(100, output: 10, at: "2026-09-15T23:59:00.123Z")
        let second = usage(120, output: 15, at: "2026-09-15T23:59:30.123Z")
        let switchModel = "{\"type\":\"turn_context\",\"payload\":{\"model\":\"other-model\"}}\n"
        let third = usage(150, output: 20, at: "2026-09-16T00:01:00.123Z")
        let url = try fixture(header + first + "\n" + second + "\n" + switchModel + third + "\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let records = try await UsageFileReader(url: url).read()
        let deltas = records.filter { $0.scope == .delta }.sorted { $0.occurredAt < $1.occurredAt }
        #expect(deltas.count == 2)
        #expect(deltas.map(\.inputTokens) == [20, 30])
        #expect(deltas.map(\.outputTokens) == [5, 5])
        #expect(deltas.map(\.modelID) == ["fixture-model", "other-model"])
        #expect(deltas.allSatisfy { $0.attribution == .observedDelta && $0.cacheWriteInputTokens == nil })
        #expect(deltas.map { ISO8601DateFormatter().string(from: $0.occurredAt) } == ["2026-09-15T23:59:30Z", "2026-09-16T00:01:00Z"])
        let baseline = records.first { $0.scope == .historicalUnattributed }
        #expect(baseline?.totalTokens == 110)
        #expect(baseline?.modelID == nil)
        #expect(baseline?.attribution == .historicalBaseline)
        #expect(records.first { $0.scope == .sessionTotal }?.totalTokens == 170)
    }
    @Test func immutableIdentifiersSurviveReselectionFileCopyAndDuplicateReports() async throws {
        let content = header + usage() + "\n" + usage(20) + "\n" + usage(20) + "\n" + usage(30) + "\n"
        let url = try fixture(content), copy = try fixture(content)
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: copy.deletingLastPathComponent())
        }
        let first = try await UsageFileReader(url: url).read()
        let reselected = try await UsageFileReader(url: url).read()
        let copied = try await UsageFileReader(url: copy).read()
        #expect(first == reselected)
        #expect(first == copied)
        #expect(first.filter { $0.scope == .delta }.count == 2)
    }
    @Test func resetCompactionAndSkippedTokenRecordsNeverPretendToBeExactModelUsage() async throws {
        let compaction = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"context_compacted\"}}\n"
        let invalid = usage(50).replacingOccurrences(of: "\"input_tokens\":50", with: "\"input_tokens\":-1")
        let content = header + usage(100, output: 10) + "\n" + usage(10, output: 3) + "\n" + compaction + usage(30, output: 5) + "\n" + invalid + "\n" + usage(60, output: 8) + "\n"
        let url = try fixture(content)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let records = try await UsageFileReader(url: url).read()
        let reset = records.first { $0.attribution == .counterReset }
        #expect(reset?.scope == .historicalUnattributed)
        #expect(reset?.totalTokens == 13)
        let compacted = records.first { $0.attribution == .compactionBoundary }
        #expect(compacted?.scope == .delta)
        #expect(compacted?.inputTokens == 20)
        #expect(compacted?.modelID == nil)
        let gap = records.first { $0.attribution == .observationGap }
        #expect(gap?.scope == .delta)
        #expect(gap?.inputTokens == 30)
        #expect(gap?.modelID == nil)
        #expect(records.filter { $0.scope == .delta && $0.attribution == .observedDelta }.isEmpty)
    }
    @Test func multipleModelsBetweenReportsAreAmbiguousAndMissingSubsetsStayNil() async throws {
        let changes = "{\"type\":\"turn_context\",\"payload\":{\"model\":\"intermediate\"}}\n{\"type\":\"turn_context\",\"payload\":{\"model\":\"final-model\"}}\n"
        let next = usage(20).replacingOccurrences(of: "\"cached_input_tokens\":2,\"reasoning_output_tokens\":1,", with: "")
        let url = try fixture(header + usage() + "\n" + changes + next + "\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let delta = try await UsageFileReader(url: url).read().first { $0.scope == .delta }
        #expect(delta?.inputTokens == 10)
        #expect(delta?.modelID == nil)
        #expect(delta?.attribution == .ambiguousModel)
        #expect(delta?.cachedInputTokens == nil)
        #expect(delta?.reasoningOutputTokens == nil)
    }
    @Test func legacyRecordsDecodeAsUnspecifiedCumulativeNotDelta() throws {
        let old = Data(#"{"id":"old","sessionID":"fixture","occurredAt":0,"inputTokens":10,"outputTokens":3,"totalTokens":13}"#.utf8)
        let record = try JSONDecoder().decode(UsageRecord.self, from: old)
        #expect(record.scope == nil)
        #expect(record.attribution == nil)
        #expect(record.cacheWriteInputTokens == nil)
    }
    @Test func malformedModelContextMustNotLeakThePreviousModelIntoLaterDeltas() async throws {
        let invalidContext = "{\"type\":\"turn_context\",\"payload\":{\"model\":123}}\n"
        let url = try fixture(header + usage() + "\n" + invalidContext + usage(20) + "\n" + usage(30) + "\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let records = try await UsageFileReader(url: url).read()
        let exact = records.first { $0.scope == .delta && $0.attribution == .observedDelta }
        #expect(exact?.inputTokens == 10)
        #expect(exact?.modelID == nil)
        #expect(records.first { $0.attribution == .observationGap }?.modelID == nil)
    }
}
