import Foundation
import Darwin

public struct CodexCLI: Equatable, Sendable {
    public let executable: URL
    public let version: String

    public static func version(from output: String) -> String? {
        let words = output.split(whereSeparator: \.isWhitespace)
        guard words.count == 2, words[0] == "codex-cli",
              words[1].range(of: #"^\d+\.\d+\.\d+([.-][A-Za-z0-9.-]+)?$"#, options: .regularExpression) != nil else { return nil }
        return String(words[1])
    }

    public static func detect(candidates: [URL]? = nil) -> CodexCLI? {
        let paths = candidates ?? (
            (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex") }
            + [URL(fileURLWithPath: "/opt/homebrew/bin/codex"), URL(fileURLWithPath: "/usr/local/bin/codex"),
               FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex")])
        for path in paths where FileManager.default.isExecutableFile(atPath: path.path) {
            let process = Process()
            let output = Pipe()
            let ended = DispatchSemaphore(value: 0)
            process.executableURL = path
            process.arguments = ["--version"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in ended.signal() }
            do { try process.run() } catch { continue }
            if ended.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                continue
            }
            guard process.terminationStatus == 0,
                  let data = try? output.fileHandleForReading.read(upToCount: 256),
                  let version = version(from: String(decoding: data, as: UTF8.self)) else { continue }
            return CodexCLI(executable: path, version: version)
        }
        return nil
    }
}
