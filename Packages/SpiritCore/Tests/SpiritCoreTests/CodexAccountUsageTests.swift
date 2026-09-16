import Foundation
import Testing
@testable import SpiritCore

struct CodexAccountUsageTests {
    @Test func parsesOnlyAccountTokenAndThreadModelMetadataWithoutCostOrContent() throws {
        let data = Data(#"{"summary":{"lifetimeTokens":9223372036854775807,"prompt":"SECRET PROMPT"},"dailyUsageBuckets":[{"startDate":"2026-09-16","tokens":0},{"startDate":"2026-09-15","tokens":123}],"threadUsage":{"threadId":"fixture-thread","estimatedUsageCreditsMicros":123,"estimatedUsageUsdMicros":999,"groups":[{"model":"fixture-model","inputTokens":10,"outputTokens":4,"cachedInputTokens":3,"netNewInputTokens":7,"totalTokens":14,"estimatedUsageCreditsMicros":321,"command":"SECRET COMMAND"}]}}"#.utf8)
        let usage = try CodexQuotaClient.parseUsage(responseData: data, observedAt: Date(timeIntervalSince1970: 123))
        #expect(usage.observedAt == Date(timeIntervalSince1970: 123))
        #expect(usage.lifetimeTokens == Int.max)
        #expect(usage.dailyBuckets?.map(\.startDate) == ["2026-09-15", "2026-09-16"])
        #expect(usage.dailyBuckets?.map(\.tokens) == [123, 0])
        #expect(usage.threadUsage?.groups.first?.modelID == "fixture-model")
        #expect(usage.threadUsage?.groups.first?.totalTokens == 14)
        #expect(usage.threadUsage?.groups.first?.cachedInputTokens == 3)
        let encoded = String(decoding: try JSONEncoder().encode(usage), as: UTF8.self)
        #expect(!encoded.contains("SECRET"))
        #expect(!encoded.contains("estimatedUsage"))
    }

    @Test func missingUsageIsNotZeroAndMissingDailyBucketsAreNotEmpty() throws {
        let missing = try CodexQuotaClient.parseUsage(responseData: Data(#"{"summary":{},"dailyUsageBuckets":null,"threadUsage":null}"#.utf8))
        #expect(missing.lifetimeTokens == nil)
        #expect(missing.dailyBuckets == nil)
        #expect(missing.threadUsage == nil)
        let zero = try CodexQuotaClient.parseUsage(responseData: Data(#"{"summary":{"lifetimeTokens":0},"dailyUsageBuckets":[]}"#.utf8))
        #expect(zero.lifetimeTokens == 0)
        #expect(zero.dailyBuckets == [])
    }

    @Test func rejectsInvalidDatesTokenCountsDuplicateDaysAndOversizedInput() {
        for date in ["2026-02-29", "2026-13-01", "2026-09-31", "2026-9-16", "2026-09-16T00:00:00Z"] {
            let json = "{\"summary\":{},\"dailyUsageBuckets\":[{\"startDate\":\"\(date)\",\"tokens\":1}]}"
            #expect(throws: CodexQuotaClient.ClientError.self) { try CodexQuotaClient.parseUsage(responseData: Data(json.utf8)) }
        }
        for tokens in ["-1", "true", "1.5", "\"5\"", "9223372036854775808", "null"] {
            let json = "{\"summary\":{},\"dailyUsageBuckets\":[{\"startDate\":\"2026-09-16\",\"tokens\":\(tokens)}]}"
            #expect(throws: CodexQuotaClient.ClientError.self) { try CodexQuotaClient.parseUsage(responseData: Data(json.utf8)) }
        }
        let duplicate = Data(#"{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-09-16","tokens":1},{"startDate":"2026-09-16","tokens":2}]}"#.utf8)
        #expect(throws: CodexQuotaClient.ClientError.self) { try CodexQuotaClient.parseUsage(responseData: duplicate) }
        #expect(throws: CodexQuotaClient.ClientError.self) { try CodexQuotaClient.parseUsage(responseData: Data(repeating: 32, count: 1_048_577)) }
    }

    @Test func fetchUsageReusesInitializationAndOnlyCallsReadOnlyAccountUsage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fixture-codex")
        let script = """
        #!/bin/sh
        IFS= read -r request
        case "$request" in *'"method":"initialize"'*) ;; *) exit 21 ;; esac
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r notification
        case "$notification" in *'"method":"initialized"'*) ;; *) exit 22 ;; esac
        IFS= read -r query
        case "$query" in *'"method":"account/usage/read"'*) ;; *) exit 23 ;; esac
        printf '%s\\n' '{"id":2,"result":{"summary":{"lifetimeTokens":13},"dailyUsageBuckets":[{"startDate":"2026-09-16","tokens":13}]}}'
        IFS= read -r end
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let usage = try await CodexQuotaClient(executableURL: executable).fetchUsage()
        #expect(usage.lifetimeTokens == 13)
        #expect(usage.dailyBuckets?.count == 1)
    }

    @Test func leapDayIsAcceptedButInvalidOptionalCountsAndTooManyRowsAreRejected() throws {
        let leap = try CodexQuotaClient.parseUsage(responseData: Data(#"{"summary":{},"dailyUsageBuckets":[{"startDate":"2024-02-29","tokens":1}]}"#.utf8))
        #expect(leap.dailyBuckets?.first?.tokens == 1)
        for tokens in ["-1", "true", "1.5", "\"5\"", "9223372036854775808"] {
            let json = "{\"summary\":{\"lifetimeTokens\":\(tokens)}}"
            #expect(throws: CodexQuotaClient.ClientError.self) { try CodexQuotaClient.parseUsage(responseData: Data(json.utf8)) }
        }
        let rows = (1000...4660).map { ["startDate": "\($0)-01-01", "tokens": 1] as [String: Any] }
        let tooMany = try JSONSerialization.data(withJSONObject: ["summary": [:], "dailyUsageBuckets": rows])
        #expect(throws: CodexQuotaClient.ClientError.self) { try CodexQuotaClient.parseUsage(responseData: tooMany) }
        let groups = Array(repeating: ["model": "fixture-model"], count: 257)
        let tooManyGroups = try JSONSerialization.data(withJSONObject: ["summary": [:], "threadUsage": ["threadId": "fixture-thread", "groups": groups]])
        #expect(throws: CodexQuotaClient.ClientError.self) { try CodexQuotaClient.parseUsage(responseData: tooManyGroups) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["BUILD_SPIRIT_ACCOUNT_USAGE_LIVE_SMOKE"] == "1"))
    func explicitlyEnabledLiveAccountUsagePrintsCountsOnly() async throws {
        let usage = try await CodexQuotaClient(executableURL: URL(fileURLWithPath: "/usr/local/bin/codex")).fetchUsage()
        #expect(usage.dailyBuckets != nil)
        print("Account usage metadata: lifetime present=\(usage.lifetimeTokens != nil), daily rows=\(usage.dailyBuckets?.count ?? 0), thread usage present=\(usage.threadUsage != nil), group count=\(usage.threadUsage?.groups.count ?? 0)")
    }
}
