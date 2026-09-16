import Foundation
import Testing
@testable import SpiritCore

@Suite("CodexConnection")
struct CodexConnectionTests {
    @Test func detectsExecutableVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("codex")
        try Data("#!/bin/sh\nprintf 'codex-cli 0.154.0\\n'\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        #expect(CodexCLI.detect(candidates: [file])?.version == "0.154.0")
    }
    @Test func missingExecutableIsNotDetected() {
        #expect(CodexCLI.detect(candidates: [URL(fileURLWithPath: "/absent/codex")]) == nil)
    }
    @Test func rejectsNonCodexVersionOutput() {
        #expect(CodexCLI.version(from: "unexpected") == nil)
        #expect(CodexCLI.version(from: "codex-cli 0.154.0\n") == "0.154.0")
    }
    @Test func quotedBridgePathSurvivesShellMetacharacters() throws {
        let path = "/Applications/Bob's $(false) `false` App/SpiritBridge"
        let command = HookInstaller.command(bridgeURL: URL(fileURLWithPath: path))
        let shell = Process()
        let output = Pipe()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "set -- " + command + "; printf '%s' \"$1\""]
        shell.standardOutput = output
        try shell.run()
        shell.waitUntilExit()
        #expect(shell.terminationStatus == 0)
        #expect(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == path)
    }
}
