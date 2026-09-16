import Foundation

public enum CodexHookError: String, Error, Sendable {
    case malformedJSON, missingSessionID, missingTurnID, missingToolID, missingToolName, unsupportedEvent, oversizedInput
}

public struct SpiritWireEnvelope: Codable, Equatable, Sendable {
    public let event: SpiritEvent
    public func encodedLine() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(self)
        data.append(10)
        return data
    }
}

public enum CodexHookAdapter {
    public static let supportedEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                                         "PermissionRequest", "Stop", "Interrupt", "SessionEnd"]
    public static let maximumInputBytes = 262_144

    public static func adapt(_ data: Data, receivedAt: Date = Date()) throws -> SpiritWireEnvelope {
        guard data.count <= maximumInputBytes else { throw CodexHookError.oversizedInput }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexHookError.malformedJSON
        }
        func identifier(_ key: String) -> String? {
            guard let value = object[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  value.utf8.count <= 1024 else { return nil }
            return value
        }
        guard let session = identifier("session_id") else { throw CodexHookError.missingSessionID }
        let kind: SpiritEvent.Kind
        switch object["hook_event_name"] as? String {
        case "SessionStart": kind = .sessionStarted
        case "UserPromptSubmit": kind = .turnStarted
        case "PreToolUse": kind = .toolStarted
        case "PostToolUse": kind = .toolFinished
        case "PermissionRequest": kind = .needsInput
        case "Stop", "Interrupt": kind = .turnStopped
        case "SessionEnd": kind = .sessionEnded
        default: throw CodexHookError.unsupportedEvent
        }
        let turn = identifier("turn_id")
        if kind != .sessionStarted && kind != .sessionEnded && turn == nil { throw CodexHookError.missingTurnID }
        let isTool = [.toolStarted, .toolFinished, .needsInput].contains(kind)
        if isTool && identifier("tool_name") == nil { throw CodexHookError.missingToolName }
        if [.toolStarted, .toolFinished].contains(kind) && identifier("tool_use_id") == nil { throw CodexHookError.missingToolID }
        let category = isTool ? toolCategory(identifier("tool_name") ?? "") : nil
        // Construct a fresh allowlisted event. Never retain input JSON, transcript paths or content.
        return SpiritWireEnvelope(event: SpiritEvent(eventID: UUID().uuidString, provider: "codex",
            sessionID: session, turnID: turn, kind: kind, occurredAt: receivedAt, receivedAt: receivedAt,
            source: "codex.command-hook", sourceVersion: "0.154.0",
            payload: .init(toolCategory: category, modelID: identifier("model"))))
    }

    private static func toolCategory(_ name: String) -> String {
        let leaf = name.split(separator: ".").last.map(String.init) ?? name
        if name.hasPrefix("mcp__") || name.hasPrefix("mcp.") { return "mcp" }
        if ["Bash", "exec_command", "write_stdin", "shell", "shell_command"].contains(leaf) { return "shell" }
        if ["apply_patch", "edit_file", "write_file"].contains(leaf) { return "fileEdit" }
        if ["spawn_agent", "send_input", "wait_agent", "close_agent", "resume_agent"].contains(leaf) { return "agent" }
        return "other"
    }
}
