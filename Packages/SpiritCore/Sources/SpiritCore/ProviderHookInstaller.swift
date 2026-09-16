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

    /// Explicit UI action only; existing safe atomic writer and ownership checks apply.
    @discardableResult public static func write(to file: URL, command: String, installing: Bool, provider: SpiritProvider) throws -> URL? {
        try HookInstaller.write(to: file, command: command, installing: installing, events: supportedEvents(for: provider), timeout: provider == .gemini ? 1000 : 1)
    }
}
