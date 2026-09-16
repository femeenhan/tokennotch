import Foundation

public enum SpiritProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex, claude, gemini, grok
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .gemini: "Gemini"
        case .grok: "Grok"
        }
    }

    // Provider plus encoded identifier is collision-free even when an ID contains a provider prefix.
    public func sessionKey(_ sessionID: String) -> String {
        "\(rawValue):\(Data(sessionID.utf8).base64EncodedString())"
    }

    public func dashboardSessionID(_ sessionID: String) -> String {
        self == .codex && !sessionID.contains(":") ? sessionID : sessionKey(sessionID)
    }
}

public enum ProviderSelection {
    public static func normalized(_ providers: [SpiritProvider]) -> [SpiritProvider] {
        var seen: Set<SpiritProvider> = []
        return Array(providers.filter { seen.insert($0).inserted }.prefix(3))
    }
}

public struct ProviderSpiritStreams: Sendable {
    private var streams: [SpiritProvider: SpiritEventStream] = [:]
    public init() {}
    public func stream(for provider: SpiritProvider) -> SpiritEventStream {
        streams[provider] ?? SpiritEventStream()
    }
    public mutating func receive(_ event: SpiritEvent) {
        guard let provider = SpiritProvider(rawValue: event.provider) else { return }
        var stream = stream(for: provider)
        stream.receive(event)
        streams[provider] = stream
    }
    public mutating func finishCompletionPresentation(id: UUID, provider: SpiritProvider) {
        var stream = stream(for: provider)
        stream.finishCompletionPresentation(id: id)
        streams[provider] = stream
    }
    public mutating func finishGreetingPresentation(id: UUID, provider: SpiritProvider) {
        var stream = stream(for: provider)
        stream.finishGreetingPresentation(id: id)
        streams[provider] = stream
    }
}
