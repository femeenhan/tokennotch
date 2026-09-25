import Foundation
import Testing
@testable import SpiritCore

@Suite("Provider hooks")
struct ProviderHookTests {
    @Test func claudeDoesNotRequireCodexTurnAndToolIDsOrLeakContents() throws {
        let data = Data(#"{"hook_event_name":"PreToolUse","session_id":"shared","tool_name":"Bash","tool_use_id":"a","prompt":"secret prompt","tool_input":{"command":"secret command"},"transcript_path":"/secret/path"}"#.utf8)
        let wire = try ProviderHookAdapter.adapt(data, provider: .claude)
        #expect(wire.event.provider == "claude")
        #expect(wire.event.kind == .toolStarted)
        #expect(wire.event.turnID == nil)
        #expect(wire.event.payload.toolCategory == "shell")
        #expect(!String(decoding: try wire.encodedLine(), as: UTF8.self).contains("secret"))
    }

    @Test func turnEndIsSeparateFromSessionEnd() throws {
        for provider in [SpiritProvider.claude, .gemini, .grok] {
            let stop = provider == .gemini ? "AfterAgent" : "Stop"
            let sessionKey = provider == .grok ? "sessionId" : "session_id"
            let input = Data("{\"hook_event_name\":\"\(stop)\",\"\(sessionKey)\":\"s\"}".utf8)
            #expect(try ProviderHookAdapter.adapt(input, provider: provider).event.kind == .turnStopped)
            let end = Data("{\"hook_event_name\":\"SessionEnd\",\"\(sessionKey)\":\"s\"}".utf8)
            #expect(try ProviderHookAdapter.adapt(end, provider: provider).event.kind == .sessionEnded)
        }
    }

    @Test func permissionNotificationsOnlyAreAttention() throws {
        for (provider, notification) in [(SpiritProvider.claude, "permission_prompt"), (.gemini, "ToolPermission"), (.grok, "permission_prompt")] {
            let sessionKey = provider == .grok ? "sessionId" : "session_id"
            let data = Data("{\"hook_event_name\":\"Notification\",\"\(sessionKey)\":\"s\",\"notification_type\":\"\(notification)\"}".utf8)
            #expect(try ProviderHookAdapter.adapt(data, provider: provider).event.kind == .needsInput)
            #expect(throws: CodexHookError.unsupportedEvent) {
                try ProviderHookAdapter.adapt(Data("{\"hook_event_name\":\"Notification\",\"\(sessionKey)\":\"s\",\"notification_type\":\"idle_prompt\"}".utf8), provider: provider)
            }
        }
    }

    @Test func grokUsesOfficialCamelCaseIDsAndInterruptEvent() throws {
        let data = Data(#"{"hook_event_name":"PreToolUse","hookEventName":"pre_tool_use","sessionId":"g","promptId":"turn-g","toolName":"run_terminal_command","toolInput":{"command":"private"}}"#.utf8)
        let wire = try ProviderHookAdapter.adapt(data, provider: .grok)
        #expect(wire.event.sessionID == "g")
        #expect(wire.event.turnID == "turn-g")
        #expect(wire.event.payload.toolCategory == "shell")
        let stop = Data(#"{"hook_event_name":"StopCancelled","sessionId":"g","promptId":"turn-g"}"#.utf8)
        #expect(try ProviderHookAdapter.adapt(stop, provider: .grok).event.kind == .turnStopped)
    }

    @Test func importedGrokEnvelopeIsRejectedByClaudeAndOriginalTimestampIsPreserved() throws {
        let grok = Data(#"{"hook_event_name":"SessionStart","hookEventName":"session_start","sessionId":"g"}"#.utf8)
        #expect(throws: CodexHookError.unsupportedEvent) { try ProviderHookAdapter.adapt(grok, provider: .claude) }
        let gemini = Data(#"{"hook_event_name":"BeforeAgent","session_id":"g","timestamp":"2026-09-16T12:00:00.123Z"}"#.utf8)
        let received = Date(timeIntervalSince1970: 2_000_000_000)
        let event = try ProviderHookAdapter.adapt(gemini, provider: .gemini, receivedAt: received).event
        #expect(event.occurredAt < received)
        #expect(event.receivedAt == received)
    }

    @Test func malformedUnknownAndChildInputAreRejected() {
        for input in ["broken", #"{"hook_event_name":"Stop"}"#, #"{"hook_event_name":"Unknown","session_id":"s"}"#, #"{"hook_event_name":"Stop","session_id":"s","agent_id":"child"}"#] {
            #expect(throws: (any Error).self) { try ProviderHookAdapter.adapt(Data(input.utf8), provider: .claude) }
        }
    }

    @Test func codexConfigurationHonorsEnvironmentOverrideOnlyForCodex() {
        let home = URL(fileURLWithPath: "/test-home")
        let environment = ["CODEX_HOME": "/custom/codex"]
        #expect(ProviderHookInstaller.configurationURL(for: .codex, home: home, environment: environment).path == "/custom/codex/hooks.json")
        #expect(ProviderHookInstaller.configurationURL(for: .codex, home: home, environment: [:]).path == "/test-home/.codex/hooks.json")
        #expect(ProviderHookInstaller.configurationURL(for: .claude, home: home, environment: environment).path == "/test-home/.claude/settings.json")
    }

    @Test func grokCanonicalEventNameWithoutClaudeAliasIsAccepted() throws {
        let data = Data(#"{"hookEventName":"pre_tool_use","sessionId":"abc-123","promptId":"p-1","cwd":"/Users/you/project","workspaceRoot":"/Users/you/project","permissionMode":"default","toolName":"run_terminal_command","toolInput":{"command":"npm test"},"timestamp":"2026-04-14T12:00:00Z"}"#.utf8)
        #expect(try ProviderHookAdapter.adapt(data, provider: .grok).event.kind == .toolStarted)
    }

    @Test func eachInstallerPreservesExistingSettingsAndUsesCorrectTimeoutUnit() throws {
        let original = Data(#"{"theme":"keep","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo keep"}]}]}}"#.utf8)
        for provider in SpiritProvider.allCases {
            let command = ProviderHookInstaller.command(bridgeURL: URL(fileURLWithPath: "/private/Spirit Bridge"), provider: provider)
            let once = try ProviderHookInstaller.install(in: original, command: command, provider: provider)
            #expect(try ProviderHookInstaller.install(in: once, command: command, provider: provider) == once)
            let root = try #require(JSONSerialization.jsonObject(with: once) as? [String: Any])
            let hooks = try #require(root["hooks"] as? [String: [[String: Any]]])
            for name in ProviderHookInstaller.supportedEvents(for: provider) {
                let installed = try #require(hooks[name]?.last?["hooks"] as? [[String: Any]])
                #expect(installed.last?["timeout"] as? Int == (provider == .gemini ? 1000 : 1))
            }
            #expect(try JSONSerialization.jsonObject(with: ProviderHookInstaller.remove(from: once, command: command)) as? NSDictionary == JSONSerialization.jsonObject(with: original) as? NSDictionary)
        }
    }

    @Test func partialClaudeHookDoesNotCountAsConnected() throws {
        let command = "'/Applications/BuildSpirit.app/Contents/MacOS/SpiritBridge' --claude-hook"
        let partial = Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"'/Applications/BuildSpirit.app/Contents/MacOS/SpiritBridge' --claude-hook"}]}]}}"#.utf8)
        #expect(try !ProviderHookInstaller.isInstalled(in: partial, command: command, provider: .claude))
        let complete = try ProviderHookInstaller.install(in: partial, command: command, provider: .claude)
        #expect(try ProviderHookInstaller.isInstalled(in: complete, command: command, provider: .claude))
    }
}
