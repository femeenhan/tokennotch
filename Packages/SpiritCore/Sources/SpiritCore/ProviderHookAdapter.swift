import Foundation

/// CLI lifecycle observer. Inputs and responses are deliberately excluded from the wire event.
public enum ProviderHookAdapter {
    public static let maximumInputBytes = CodexHookAdapter.maximumInputBytes

    public static func supportedEvents(for provider: SpiritProvider) -> [String] {
        switch provider {
        case .codex: CodexHookAdapter.supportedEvents
        case .claude: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"]
        case .gemini: ["SessionStart", "BeforeAgent", "BeforeTool", "AfterTool", "AfterAgent", "Notification", "SessionEnd"]
        case .grok: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "Notification", "Stop", "StopCancelled", "StopFailure", "SessionEnd"]
        }
    }

    public static func adapt(_ data: Data, provider: SpiritProvider, receivedAt: Date = Date()) throws -> SpiritWireEnvelope {
        if provider == .codex { return try CodexHookAdapter.adapt(data, receivedAt: receivedAt) }
        guard data.count <= maximumInputBytes else { throw CodexHookError.oversizedInput }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CodexHookError.malformedJSON }
        func identifier(_ keys: String...) -> String? {
            for key in keys {
                if let value = object[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.utf8.count <= 1024 { return value }
            }
            return nil
        }
        // Grok imports Claude hooks automatically. Reject its distinct envelope in the
        // Claude/Gemini entry point so imported hooks cannot misattribute activity.
        if provider != .grok && object["hookEventName"] != nil { throw CodexHookError.unsupportedEvent }
        guard let sessionID = provider == .grok ? identifier("sessionId") : identifier("session_id") else { throw CodexHookError.missingSessionID }
        // Child tool events can share the main Claude session ID. Do not let their stop/end
        // events make the main session idle; independent child aggregation is not installed yet.
        guard identifier("agent_id", "subagentType") == nil else { throw CodexHookError.unsupportedEvent }
        // Grok emits both names: PascalCase hook_event_name and snake_case
        // hookEventName. Support its canonical name as well as the Claude alias.
        let grokNames = ["session_start": "SessionStart", "user_prompt_submit": "UserPromptSubmit",
                         "pre_tool_use": "PreToolUse", "post_tool_use": "PostToolUse",
                         "post_tool_use_failure": "PostToolUseFailure", "notification": "Notification",
                         "stop": "Stop", "stop_cancelled": "StopCancelled", "stop_failure": "StopFailure",
                         "session_end": "SessionEnd"]
        let eventName = identifier("hook_event_name") ?? (provider == .grok ? identifier("hookEventName").flatMap { grokNames[$0] } : nil)
        guard let name = eventName, supportedEvents(for: provider).contains(name) else { throw CodexHookError.unsupportedEvent }
        let kind: SpiritEvent.Kind
        switch name {
        case "SessionStart": kind = .sessionStarted
        case "UserPromptSubmit", "BeforeAgent": kind = .turnStarted
        case "PreToolUse", "BeforeTool": kind = .toolStarted
        case "PostToolUse", "PostToolUseFailure", "AfterTool": kind = .toolFinished
        case "PermissionRequest": kind = .needsInput
        case "Notification":
            let notification = identifier("notification_type", "notificationType")
            guard (provider == .gemini && notification == "ToolPermission") ||
                  (provider != .gemini && notification == "permission_prompt") else { throw CodexHookError.unsupportedEvent }
            kind = .needsInput
        case "Stop", "StopCancelled", "AfterAgent": kind = .turnStopped
        case "StopFailure": kind = .collectionInterrupted
        case "SessionEnd": kind = .sessionEnded
        default: throw CodexHookError.unsupportedEvent
        }
        let toolName = identifier("tool_name", "toolName")
        if kind == .toolStarted || kind == .toolFinished {
            guard toolName != nil else { throw CodexHookError.missingToolName }
        }
        // Claude and Gemini do not expose a turn ID in their common hook schema.
        // Leave it absent instead of inventing a correlation across hook processes.
        let turnID = provider == .grok ? identifier("promptId", "prompt_id") : nil
        let occurredAt = identifier("timestamp").flatMap { value -> Date? in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        } ?? receivedAt
        return SpiritWireEnvelope(event: SpiritEvent(eventID: UUID().uuidString, provider: provider.rawValue,
            sessionID: sessionID, turnID: turnID, kind: kind, occurredAt: occurredAt, receivedAt: receivedAt,
            // Adapter contract revision; do not claim an unobserved CLI version.
            source: "\(provider.rawValue).command-hook", sourceVersion: "1",
            payload: .init(toolCategory: toolName.map(category), success: name == "PostToolUseFailure" ? false : nil,
                           modelID: identifier("model"))))
    }

    private static func category(_ name: String) -> String {
        if name.hasPrefix("mcp") || name.contains("__") { return "mcp" }
        if ["Bash", "run_shell_command", "run_terminal_command"].contains(name) { return "shell" }
        if ["Edit", "Write", "MultiEdit", "replace", "write_file", "search_replace"].contains(name) { return "fileEdit" }
        if ["Task", "Agent", "spawn_subagent"].contains(name) { return "agent" }
        return "other"
    }
}
