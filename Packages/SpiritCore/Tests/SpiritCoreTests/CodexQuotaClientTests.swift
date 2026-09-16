import Foundation
import Darwin
import Testing
@testable import SpiritCore

struct CodexQuotaClientTests {
    private var multiResult: String {
        #"{"rateLimits":{"limitId":"legacy","primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":"Codex","normalModelSlug":"gpt-fixture","primary":{"usedPercent":23.5,"windowDurationMins":300,"resetsAt":1800000000},"secondary":{"usedPercent":62,"windowDurationMins":10080,"resetsAt":1800500000}},"daily":{"limitId":"daily","limitName":"Daily","primary":{"usedPercent":10,"windowDurationMins":1440,"resetsAt":null}}}}"#
    }
    private func executable(_ body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fixture-codex")
        try Data(("#!/bin/sh\n" + body).utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
    private func protocolFixture(result: String) throws -> URL {
        try executable("""
        IFS= read -r request
        case "$request" in *'"method":"initialize"'*) ;; *) exit 21 ;; esac
        printf '%s\\n' '{"id":1,"result":{"userAgent":"fixture"}}'
        IFS= read -r notification
        case "$notification" in *'"method":"initialized"'*) ;; *) exit 22 ;; esac
        IFS= read -r query
        case "$query" in *'"method":"account/rateLimits/read"'*'"excludeResetCreditDetails":true'*|*'"excludeResetCreditDetails":true'*'"method":"account/rateLimits/read"'*) ;; *) exit 23 ;; esac
        printf '%s\\n' '{"method":"warning","params":{"message":"SECRET USER CONTENT"}}'
        printf '%s\\n' '{"id":2,"result":\(result)}'
        IFS= read -r end
        """)
    }
    @Test func readsOnlyInitializationAndReadOnlyQuotaRequest() async throws {
        let url = try protocolFixture(result: multiResult)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let snapshot = try await CodexQuotaClient(executableURL: url).read()
        #expect(snapshot.buckets.map(\.id) == ["codex", "daily"])
        #expect(snapshot.buckets.first?.modelID == "gpt-fixture")
        #expect(snapshot.buckets.first?.primary?.remainingPercent == 76.5)
        #expect(snapshot.buckets.first?.secondary?.remainingPercent == 38)
        #expect(snapshot.buckets.first?.secondary?.windowDurationMins == 10080)
        #expect(snapshot.buckets.last?.primary?.windowDurationMins == 1440)
        #expect(snapshot.buckets.first?.primary?.resetsAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(!String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self).contains("SECRET"))
    }
    @Test func singleBucketFallbackDoesNotInventDurations() throws {
        let snapshot = try CodexQuotaClient.parse(responseData: Data(#"{"rateLimits":{"limitId":null,"limitName":null,"primary":{"usedPercent":0,"windowDurationMins":null,"resetsAt":null},"secondary":{"usedPercent":100,"windowDurationMins":60,"resetsAt":1800000000}},"rateLimitsByLimitId":null}"#.utf8), observedAt: Date(timeIntervalSince1970: 123))
        #expect(snapshot.observedAt == Date(timeIntervalSince1970: 123))
        #expect(snapshot.buckets.first?.primary?.remainingPercent == 100)
        #expect(snapshot.buckets.first?.primary?.windowDurationMins == nil)
        #expect(snapshot.buckets.first?.secondary?.remainingPercent == 0)
    }
    @Test func invalidPercentAndMalformedValuesAreRejectedNotClamped() throws {
        for percent in ["-1", "101", "true", "\"42\""] {
            let json = "{\"rateLimits\":{\"primary\":{\"usedPercent\":\(percent)}}}"
            #expect(throws: CodexQuotaClient.ClientError.self) {
                try CodexQuotaClient.parse(responseData: Data(json.utf8))
            }
        }
        #expect(QuotaWindow(usedPercent: .nan).remainingPercent == nil)
        #expect(QuotaWindow(usedPercent: 120).remainingPercent == nil)
    }
    @Test func accountIdentityIsPreservedAndOldArchiveRemainsDecodable() throws {
        let result = #"{"accountId":"fixture-account","rateLimits":{"limitId":"codex","primary":{"usedPercent":10}}}"#
        let snapshot = try CodexQuotaClient.parse(responseData: Data(result.utf8))
        #expect(snapshot.accountID == "fixture-account")
        let oldArchive = Data(#"{"observedAt":123,"buckets":[]}"#.utf8)
        let old = try JSONDecoder().decode(QuotaSnapshot.self, from: oldArchive)
        #expect(old.accountID == nil)
        let invalid = result.replacingOccurrences(of: "\"fixture-account\"", with: "true")
        #expect(throws: CodexQuotaClient.ClientError.self) { try CodexQuotaClient.parse(responseData: Data(invalid.utf8)) }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BUILD_SPIRIT_QUOTA_LIVE_SMOKE"] == "1"))
    func explicitlyEnabledInstalledClientSmokeReturnsMetadataOnly() async throws {
        let snapshot = try await CodexQuotaClient(executableURL: URL(fileURLWithPath: "/usr/local/bin/codex")).read()
        #expect(!snapshot.buckets.isEmpty)
        print("Quota accountID present: \(snapshot.accountID != nil)")
        for bucket in snapshot.buckets {
            for window in [bucket.primary, bucket.secondary].compactMap({ $0 }) {
                let duration = window.windowDurationMins.map { String($0) } ?? "unavailable"
                let remaining = window.remainingPercent.map { String($0) } ?? "unavailable"
                let reset = window.resetsAt.map { ISO8601DateFormatter().string(from: $0) } ?? "unavailable"
                print("Quota bucket=\(bucket.id) durationMins=\(duration) remainingPercent=\(remaining) resetsAt=\(reset)")
            }
        }
    }
    @Test func serverErrorsDoNotRevealResponseText() async throws {
        let url = try executable("IFS= read -r request\nprintf '%s\\n' '{\"id\":1,\"error\":{\"code\":-32000,\"message\":\"SECRET TOKEN\"}}'\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        do {
            _ = try await CodexQuotaClient(executableURL: url).read()
            Issue.record("Expected sanitized server error")
        } catch {
            #expect(error is CodexQuotaClient.ClientError)
            #expect(!error.localizedDescription.contains("SECRET"))
        }
    }
    @Test func cancellationStopsUnresponsiveProcessPromptly() async throws {
        let url = try executable("trap 'exit 0' TERM\nwhile IFS= read -r request; do :; done\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let client = CodexQuotaClient(executableURL: url)
        let task = Task { try await client.read() }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
    }
    @Test func oversizedProtocolOutputIsRejected() async throws {
        let url = try executable("IFS= read -r request\n/usr/bin/head -c 1100000 /dev/zero | /usr/bin/tr '\\000' x\nprintf '\\n'\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await #expect(throws: CodexQuotaClient.ClientError.self) { try await CodexQuotaClient(executableURL: url).read() }
    }
    @Test func deadlineTimesOutAndKillsAChildThatIgnoresTermination() async throws {
        let url = try executable("printf '%s' \"$$\" > \"${0%/*}/fixture-pid\"\ntrap '' TERM\nexec /bin/sleep 30\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let started = ContinuousClock.now
        do {
            _ = try await CodexQuotaClient(executableURL: url).read()
            Issue.record("Expected bounded timeout")
        } catch let error as CodexQuotaClient.ClientError {
            if case .timeout = error {} else { Issue.record("Expected timeout, got \(error)") }
        }
        #expect(started.duration(to: .now) < .seconds(22))
        let pidText = try String(contentsOf: url.deletingLastPathComponent().appendingPathComponent("fixture-pid"), encoding: .utf8)
        let pid = try #require(Int32(pidText))
        try await Task.sleep(for: .milliseconds(150))
        #expect(kill(pid, 0) == -1)
    }
}
