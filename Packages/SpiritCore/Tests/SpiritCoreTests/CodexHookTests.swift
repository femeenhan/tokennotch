import Foundation
import Testing
@testable import SpiritCore

@Suite("CodexHookAdapter")
struct CodexHookTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/codex/\(name).json"))
    }

    @Test func supportedEventsAndPrivacy() throws {
        let cases: [(String, SpiritEvent.Kind)] = [
            ("SessionStart", .sessionStarted), ("UserPromptSubmit", .turnStarted),
            ("PreToolUse", .toolStarted), ("PostToolUse", .toolFinished),
            ("PermissionRequest", .needsInput), ("Stop", .turnStopped),
            ("Interrupt", .turnStopped), ("SessionEnd", .sessionEnded)
        ]
        for (name, kind) in cases {
            let wire = try CodexHookAdapter.adapt(fixture(name), receivedAt: now)
            #expect(wire.event.kind == kind)
            #expect(wire.event.sessionID == "session-fixture")
            #expect(wire.event.occurredAt == now && wire.event.receivedAt == now)
            #expect(wire.event.payload.success == nil)
            let data = try wire.encodedLine()
            #expect(try JSONDecoder().decode(SpiritWireEnvelope.self, from: data) == wire)
            let text = String(decoding: data, as: UTF8.self)
            #expect(!text.contains("SENSITIVE_SENTINEL"))
            #expect(!text.contains("tool_name"))
            #expect(data.last == 10 && data.filter { $0 == 10 }.count == 1)
        }
    }

    @Test func rejectsInvalidWithoutEchoingPayload() throws {
        for (name, code) in [("malformed", CodexHookError.malformedJSON),
                             ("missing-id", .missingSessionID), ("unsupported", .unsupportedEvent)] {
            #expect(throws: code) { try CodexHookAdapter.adapt(fixture(name), receivedAt: now) }
        }
        #expect(throws: CodexHookError.missingTurnID) {
            try CodexHookAdapter.adapt(Data(#"{"session_id":"s","hook_event_name":"Stop"}"#.utf8), receivedAt: now)
        }
    }

    @Test func normalizesToolNames() throws {
        for (name, category) in [("Bash", "shell"), ("exec_command", "shell"), ("apply_patch", "fileEdit"),
                                  ("mcp__sample__read", "mcp"), ("spawn_agent", "agent"),
                                  ("unrecognized", "other")] {
            let input: [String: String] = ["session_id": "s", "turn_id": "t", "tool_use_id": "u",
                "hook_event_name": "PreToolUse", "tool_name": name]
            let wire = try CodexHookAdapter.adapt(JSONSerialization.data(withJSONObject: input), receivedAt: now)
            #expect(wire.event.payload.toolCategory == category)
        }
    }

    @Test func officialPermissionRequestWithoutToolUseIDIsAccepted() throws {
        let input = Data(#"{"session_id":"s","turn_id":"t","hook_event_name":"PermissionRequest","tool_name":"Bash"}"#.utf8)
        let wire = try CodexHookAdapter.adapt(input)
        #expect(wire.event.kind == .needsInput)
        #expect(wire.event.payload.toolCategory == "shell")
    }

    @Test func rejectsMissingToolMetadata() {
        #expect(throws: CodexHookError.missingToolID) {
            try CodexHookAdapter.adapt(Data(#"{"session_id":"s","turn_id":"t","hook_event_name":"PreToolUse","tool_name":"Bash"}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try CodexHookAdapter.adapt(Data(#"{"session_id":"s","turn_id":"t","tool_use_id":"u","hook_event_name":"PostToolUse"}"#.utf8))
        }
    }
}
