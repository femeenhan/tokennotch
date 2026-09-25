import Foundation

public enum ProviderHookInstaller {
    public static func supportedEvents(for provider: SpiritProvider) -> [String] {
        ProviderHookAdapter.supportedEvents(for: provider)
    }

    public static func configurationURL(for provider: SpiritProvider, home: URL = FileManager.default.homeDirectoryForCurrentUser, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        switch provider {
        case .codex:
            if let path = environment["CODEX_HOME"], !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("hooks.json")
            }
            return home.appendingPathComponent(".codex/hooks.json")
        case .claude: return home.appendingPathComponent(".claude/settings.json")
        case .gemini: return home.appendingPathComponent(".gemini/settings.json")
        case .grok: return home.appendingPathComponent(".grok/hooks/build-spirit.json")
        }
    }

    public static func command(bridgeURL: URL, provider: SpiritProvider) -> String {
        "'" + bridgeURL.path.replacingOccurrences(of: "'", with: "'\\''") + "' --\(provider.rawValue)-hook"
    }

    public static func install(in data: Data, command: String, provider: SpiritProvider) throws -> Data {
        try HookInstaller.install(in: data, command: command, events: supportedEvents(for: provider), timeout: provider == .gemini ? 1000 : 1)
    }

    public static func remove(from data: Data, command: String) throws -> Data {
        try HookInstaller.remove(from: data, command: command)
    }

    public static func isInstalled(in data: Data, command: String, provider: SpiritProvider) throws -> Bool {
        let valid = try HookInstaller.canonical(data)
        guard let root = try JSONSerialization.jsonObject(with: valid) as? [String: Any],
              let events = root["hooks"] as? [String: [[String: Any]]] else { return false }
        return supportedEvents(for: provider).allSatisfy { name in
            (events[name] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains {
                    $0["type"] as? String == "command" && $0["command"] as? String == command
                }
            }
        }
    }

    /// Used by an explicit connection action and later to maintain that opted-in connection.
    @discardableResult public static func write(to file: URL, command: String, installing: Bool, provider: SpiritProvider) throws -> URL? {
        try HookInstaller.write(to: file, command: command, installing: installing, events: supportedEvents(for: provider), timeout: provider == .gemini ? 1000 : 1)
    }
}
