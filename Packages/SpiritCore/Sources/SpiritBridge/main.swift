import Foundation
import Darwin
import SpiritCore

// This observer never prints hook decisions or errors. Every path ends successfully.
/// Reads stdin with a short deadline; nil when stalled, failed or larger than `limit`.
func readBoundedStdin(limit: Int) -> Data? {
    var input = Data()
    var bytes = [UInt8](repeating: 0, count: 8192)
    let deadline = DispatchTime.now().uptimeNanoseconds + 250_000_000
    while DispatchTime.now().uptimeNanoseconds < deadline {
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let remaining = Int32(max(1, (deadline - min(deadline, DispatchTime.now().uptimeNanoseconds)) / 1_000_000))
        guard poll(&descriptor, 1, remaining) > 0 else { return nil }
        let count = read(STDIN_FILENO, &bytes, bytes.count)
        if count == 0 { break }
        guard count > 0, input.count + count <= limit else { return nil }
        input.append(contentsOf: bytes.prefix(count))
    }
    return input
}

func argument(after flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag), index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

func forwardHook() {
    guard let provider = SpiritProvider.allCases.first(where: { CommandLine.arguments.contains("--\($0.rawValue)-hook") }) else { return }
    guard let input = readBoundedStdin(limit: ProviderHookAdapter.maximumInputBytes) else { return }
    guard let wire = try? ProviderHookAdapter.adapt(input, provider: provider), let line = try? wire.encodedLine() else { return }
    let url = argument(after: "--socket").map { URL(fileURLWithPath: $0) } ?? SpiritSocketLocation.defaultURL
    _ = SpiritSocketClient.send(line, to: url)
}

/// Claude Code statusLine: record rate limits only. Prints nothing, so the status line stays empty.
func recordStatusLine() {
    guard let input = readBoundedStdin(limit: ProviderHookAdapter.maximumInputBytes),
          let limits = ClaudeRateLimits.parseStatusLine(input, now: Date()) else { return }
    let url = argument(after: "--rate-limits-file").map { URL(fileURLWithPath: $0) } ?? ClaudeRateLimits.defaultURL
    try? ClaudeRateLimits.write(limits, to: url)
}

if CommandLine.arguments.contains("--claude-statusline") {
    recordStatusLine()
} else {
    forwardHook()
}
exit(0)
