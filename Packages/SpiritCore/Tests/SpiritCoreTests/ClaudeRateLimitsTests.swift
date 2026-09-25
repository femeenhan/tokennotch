import Foundation
import Testing
@testable import SpiritCore

@Suite("ClaudeRateLimits")
struct ClaudeRateLimitsTests {
    let now = Date(timeIntervalSince1970: 1_738_400_000)

    func parse(_ text: String) -> ClaudeRateLimits? { ClaudeRateLimits.parseStatusLine(Data(text.utf8), now: now) }

    @Test func parsesBothWindows() throws {
        let limits = try #require(parse(#"{"model":{"id":"x"},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}"#))
        #expect(limits.observedAt == now)
        #expect(limits.fiveHour == QuotaWindow(usedPercent: 23.5, windowDurationMins: 300, resetsAt: Date(timeIntervalSince1970: 1_738_425_600)))
        #expect(limits.sevenDay == QuotaWindow(usedPercent: 41.2, windowDurationMins: 10080, resetsAt: Date(timeIntervalSince1970: 1_738_857_600)))
    }

    @Test func parsesSingleWindowAndMissingReset() throws {
        let limits = try #require(parse(#"{"rate_limits":{"seven_day":{"used_percentage":10}}}"#))
        #expect(limits.fiveHour == nil)
        #expect(limits.sevenDay == QuotaWindow(usedPercent: 10, windowDurationMins: 10080, resetsAt: nil))
    }

    @Test func rejectsMissingOrGarbage() {
        for text in [#"{"model":{}}"#, "garbage", "[]", #"{"rate_limits":{}}"#, #"{"rate_limits":[1]}"#,
                     #"{"rate_limits":{"five_hour":{"used_percentage":"12"}}}"#,
                     #"{"rate_limits":{"five_hour":{"used_percentage":true}}}"#,
                     #"{"rate_limits":{"five_hour":{"resets_at":1738425600}}}"#] {
            #expect(parse(text) == nil, "\(text)")
        }
    }

    @Test func clampsAboveHundredAndRejectsNegative() throws {
        let limits = try #require(parse(#"{"rate_limits":{"five_hour":{"used_percentage":130},"seven_day":{"used_percentage":-1}}}"#))
        #expect(limits.fiveHour?.usedPercent == 100)
        #expect(limits.sevenDay == nil)
        #expect(parse(#"{"rate_limits":{"five_hour":{"used_percentage":-0.5}}}"#) == nil)
    }

    @Test func remainingFractionIgnoresExpiredWindows() {
        let future = now.addingTimeInterval(3600), past = now.addingTimeInterval(-1)
        let both = ClaudeRateLimits(observedAt: now, fiveHour: QuotaWindow(usedPercent: 80, windowDurationMins: 300, resetsAt: future),
                                    sevenDay: QuotaWindow(usedPercent: 40, windowDurationMins: 10080, resetsAt: nil))
        #expect(abs(both.remainingFraction(at: now)! - 0.2) < 1e-9)
        let expiredFive = ClaudeRateLimits(observedAt: now, fiveHour: QuotaWindow(usedPercent: 80, windowDurationMins: 300, resetsAt: past),
                                           sevenDay: QuotaWindow(usedPercent: 40, windowDurationMins: 10080, resetsAt: future))
        #expect(abs(expiredFive.remainingFraction(at: now)! - 0.6) < 1e-9)
        let allExpired = ClaudeRateLimits(observedAt: now, fiveHour: QuotaWindow(usedPercent: 80, windowDurationMins: 300, resetsAt: past), sevenDay: nil)
        #expect(allExpired.remainingFraction(at: now) == nil)
    }

    @Test func writeReadRoundTripIsPrivateAndRefusesMissingDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("claude-rate-limits.json")
        let limits = try #require(parse(#"{"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600}}}"#))
        try ClaudeRateLimits.write(limits, to: file)
        try ClaudeRateLimits.write(limits, to: file)
        #expect(ClaudeRateLimits.read(from: file) == limits)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["claude-rate-limits.json"])

        let missing = directory.appendingPathComponent("absent/claude-rate-limits.json")
        #expect(throws: (any Error).self) { try ClaudeRateLimits.write(limits, to: missing) }
        #expect(!FileManager.default.fileExists(atPath: missing.deletingLastPathComponent().path))
        #expect(ClaudeRateLimits.read(from: missing) == nil)

        try Data("garbage".utf8).write(to: file)
        #expect(ClaudeRateLimits.read(from: file) == nil)
        try Data(repeating: 0x20, count: ClaudeRateLimits.maximumFileBytes + 1).write(to: file)
        #expect(ClaudeRateLimits.read(from: file) == nil)
    }

    @Test func refusesSymlinkedDirectoryAndSymlinkedFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let real = directory.appendingPathComponent("real"), link = directory.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let limits = ClaudeRateLimits(observedAt: now, fiveHour: QuotaWindow(usedPercent: 1), sevenDay: nil)
        #expect(throws: (any Error).self) { try ClaudeRateLimits.write(limits, to: link.appendingPathComponent("x.json")) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: real.path).isEmpty)

        let target = real.appendingPathComponent("target.json")
        try ClaudeRateLimits.write(limits, to: target)
        let fileLink = real.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: target)
        #expect(ClaudeRateLimits.read(from: fileLink) == nil)
    }
}

@Suite("ClaudeStatusLineInstaller")
struct ClaudeStatusLineInstallerTests {
    let command = ClaudeStatusLineInstaller.command(bridgeURL: URL(fileURLWithPath: "/Applications/Build Spirit's.app/Contents/MacOS/SpiritBridge"))
    let hooks = #"{"custom":{"flag":true},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo keep"}]}]}}"#

    func root(_ data: Data) throws -> [String: Any] { try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]) }

    @Test func commandQuotesBridgePath() {
        #expect(command == #"'/Applications/Build Spirit'\''s.app/Contents/MacOS/SpiritBridge' --claude-statusline"#)
    }

    @Test func installsOnlyWhenAbsentAndPreservesOtherKeys() throws {
        let original = Data(hooks.utf8)
        #expect(try ClaudeStatusLineInstaller.state(in: original, command: command) == .absent)
        let installed = try ClaudeStatusLineInstaller.install(in: original, command: command)
        #expect(try ClaudeStatusLineInstaller.state(in: installed, command: command) == .installed)
        let object = try root(installed)
        #expect(object["statusLine"] as? NSDictionary == ["type": "command", "command": command, "padding": 0] as NSDictionary)
        #expect(object["hooks"] as? NSDictionary == (try root(original))["hooks"] as? NSDictionary)
        #expect(object["custom"] as? NSDictionary == ["flag": true] as NSDictionary)
        #expect(try ClaudeStatusLineInstaller.install(in: installed, command: command) == installed)
        let removed = try ClaudeStatusLineInstaller.remove(from: installed, command: command)
        #expect(try root(removed) as NSDictionary == (try root(original)) as NSDictionary)
    }

    @Test func leavesForeignStatusLineUntouched() throws {
        for foreign in [#"{"statusLine":{"type":"command","command":"~/.claude/mine.sh"}}"#,
                        #"{"statusLine":{"type":"static","command":"\#(command.replacingOccurrences(of: "'", with: "\\u0027"))"}}"#,
                        #"{"statusLine":"weird"}"#] {
            let data = Data(foreign.utf8)
            #expect(try ClaudeStatusLineInstaller.state(in: data, command: command) == .foreign)
            #expect(try ClaudeStatusLineInstaller.install(in: data, command: command) == data)
            #expect(try ClaudeStatusLineInstaller.remove(from: data, command: command) == data)
        }
        #expect(throws: (any Error).self) { try ClaudeStatusLineInstaller.install(in: Data("broken".utf8), command: command) }
    }

    @Test func writeUsesGuardedWriterWithBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("settings.json")
        let original = Data(hooks.utf8)
        try original.write(to: file)
        let backup = try #require(try ClaudeStatusLineInstaller.write(to: file, command: command, installing: true))
        #expect(backup.lastPathComponent.hasPrefix("settings.json.build-spirit-"))
        #expect(try Data(contentsOf: backup) == original)
        #expect(try ClaudeStatusLineInstaller.state(in: Data(contentsOf: file), command: command) == .installed)
        #expect(try ClaudeStatusLineInstaller.write(to: file, command: command, installing: true) == nil)
        _ = try ClaudeStatusLineInstaller.write(to: file, command: command, installing: false)
        #expect(try ClaudeStatusLineInstaller.state(in: Data(contentsOf: file), command: command) == .absent)
        #expect(String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("echo keep"))

        let foreign = Data(#"{"statusLine":{"type":"command","command":"mine"}}"#.utf8)
        try foreign.write(to: file)
        #expect(try ClaudeStatusLineInstaller.write(to: file, command: command, installing: true) == nil)
        #expect(try ClaudeStatusLineInstaller.write(to: file, command: command, installing: false) == nil)
        #expect(try Data(contentsOf: file) == foreign)

        let absent = directory.appendingPathComponent("absent.json")
        #expect(try ClaudeStatusLineInstaller.write(to: absent, command: command, installing: false) == nil)
        #expect(!FileManager.default.fileExists(atPath: absent.path))
    }

    @Test func writeRefusesSymlinkedDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let real = directory.appendingPathComponent("real"), link = directory.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try Data(hooks.utf8).write(to: real.appendingPathComponent("settings.json"))
        #expect(throws: (any Error).self) {
            try ClaudeStatusLineInstaller.write(to: link.appendingPathComponent("settings.json"), command: command, installing: true)
        }
        #expect(try Data(contentsOf: real.appendingPathComponent("settings.json")) == Data(hooks.utf8))
    }
}
