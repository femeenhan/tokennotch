import Foundation

/// Owns Claude Code's `statusLine` only when it is absent; a user's own status line is never replaced.
public enum ClaudeStatusLineInstaller {
    public enum State: Equatable, Sendable { case absent, installed, foreign }

    public static func command(bridgeURL: URL) -> String {
        "'" + bridgeURL.path.replacingOccurrences(of: "'", with: "'\\''") + "' --claude-statusline"
    }

    public static func state(in data: Data, command: String) throws -> State {
        try state(of: HookInstaller.object(data), command: command)
    }

    private static func state(of root: [String: Any], command: String) -> State {
        guard let value = root["statusLine"], !(value is NSNull) else { return .absent }
        guard let entry = value as? [String: Any], entry["type"] as? String == "command",
              entry["command"] as? String == command else { return .foreign }
        return .installed
    }

    /// Returns `data` unchanged unless the status line is absent.
    public static func install(in data: Data, command: String) throws -> Data {
        var root = try HookInstaller.object(data)
        guard state(of: root, command: command) == .absent else { return data }
        root["statusLine"] = ["type": "command", "command": command, "padding": 0] as [String: Any]
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    }

    /// Returns `data` unchanged unless the status line is exactly ours.
    public static func remove(from data: Data, command: String) throws -> Data {
        var root = try HookInstaller.object(data)
        guard state(of: root, command: command) == .installed else { return data }
        root.removeValue(forKey: "statusLine")
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    }

    /// Explicit opt-in action only. Uses the same guarded writer as hook installation; returns the backup URL if one was made.
    @discardableResult public static func write(to file: URL, command: String, installing: Bool) throws -> URL? {
        try HookInstaller.write(to: file, backupPrefix: file.lastPathComponent, skipWhenMissing: !installing) { original in
            try installing ? install(in: original, command: command) : remove(from: original, command: command)
        }
    }
}
