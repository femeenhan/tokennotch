import Foundation
import Darwin
import SpiritCore

// This observer never prints hook decisions or errors. Every path ends successfully.
func forwardHook() {
    guard let provider = SpiritProvider.allCases.first(where: { CommandLine.arguments.contains("--\($0.rawValue)-hook") }) else { return }
    var input = Data()
    var bytes = [UInt8](repeating: 0, count: 8192)
    let deadline = DispatchTime.now().uptimeNanoseconds + 250_000_000
    while DispatchTime.now().uptimeNanoseconds < deadline {
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let remaining = Int32(max(1, (deadline - min(deadline, DispatchTime.now().uptimeNanoseconds)) / 1_000_000))
        guard poll(&descriptor, 1, remaining) > 0 else { return }
        let count = read(STDIN_FILENO, &bytes, bytes.count)
        if count == 0 { break }
        guard count > 0, input.count + count <= ProviderHookAdapter.maximumInputBytes else { return }
        input.append(contentsOf: bytes.prefix(count))
    }
    guard let wire = try? ProviderHookAdapter.adapt(input, provider: provider), let line = try? wire.encodedLine() else { return }
    var url = SpiritSocketLocation.defaultURL
    if let index = CommandLine.arguments.firstIndex(of: "--socket"), index + 1 < CommandLine.arguments.count {
        url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    }
    _ = SpiritSocketClient.send(line, to: url)
}

forwardHook()
exit(0)
