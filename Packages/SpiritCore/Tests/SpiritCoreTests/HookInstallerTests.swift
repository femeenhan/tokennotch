import Foundation
import Testing
@testable import SpiritCore

@Suite("HookInstaller")
struct HookInstallerTests {
    let command = "'/Applications/Build Spirit.app/Contents/MacOS/SpiritBridge' --codex-hook"
    let original = Data(#"{"description":"keep","custom":{"flag":true},"hooks":{"Stop":[{"matcher":"x","hooks":[{"type":"command","command":"echo keep","timeout":8}]}],"Unknown":[{"hooks":[{"type":"command","command":"keep unknown"}]}]}}"#.utf8)

    @Test func preservesOtherHooksAndIsIdempotent() throws {
        let once = try HookInstaller.install(in: original, command: command)
        #expect(try HookInstaller.install(in: once, command: command) == once)
        let removed = try HookInstaller.remove(from: once, command: command)
        #expect(try JSONSerialization.jsonObject(with: removed) as? NSDictionary == JSONSerialization.jsonObject(with: original) as? NSDictionary)
        #expect(try HookInstaller.remove(from: original, command: command) == HookInstaller.canonical(original))
    }

    @Test func removesOnlyOurCommandInsideMixedGroup() throws {
        let input = try JSONSerialization.data(withJSONObject: ["hooks": ["Stop": [["matcher": "x", "hooks": [
            ["type": "command", "command": command], ["type": "command", "command": "keep"]]]]]])
        let result = try HookInstaller.remove(from: input, command: command)
        let text = String(decoding: result, as: UTF8.self)
        #expect(text.contains("keep") && text.contains("matcher") && !text.contains("SpiritBridge"))
    }

    @Test func refusesDamagedJSON() {
        for text in ["broken", "[]", #"{"hooks":[]}"#, #"{"hooks":{"Stop":4}}"#] {
            #expect(throws: (any Error).self) { try HookInstaller.install(in: Data(text.utf8), command: command) }
        }
    }

    @Test func writesBackupAndAtomicReplacementInTemporaryDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("hooks.json")
        try original.write(to: file)
        let backup = try HookInstaller.write(to: file, command: command, installing: true)
        #expect(try Data(contentsOf: #require(backup)) == original)
        #expect(try Data(contentsOf: file) == HookInstaller.install(in: original, command: command))
        _ = try HookInstaller.write(to: file, command: command, installing: false)
        #expect(try Data(contentsOf: file) == HookInstaller.canonical(original))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.hasPrefix(".spirit-") })
    }

    @Test func acceptsOwnedReadableClaudeDirectoryAndPreservesOtherHooks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("settings.json")
        try original.write(to: file)
        let claudeCommand = "'/Applications/Build Spirit.app/Contents/MacOS/SpiritBridge' --claude-hook"
        _ = try ProviderHookInstaller.write(to: file, command: claudeCommand, installing: true, provider: .claude)
        #expect(try ProviderHookInstaller.isInstalled(in: Data(contentsOf: file), command: claudeCommand, provider: .claude))
        #expect(String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("keep unknown"))
    }

    @Test func refusesSymlinkParentWithoutChangingTargetOrCreatingBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = directory.appendingPathComponent("real")
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let file = target.appendingPathComponent("hooks.json")
        try original.write(to: file)
        for installing in [true, false] {
            #expect(throws: (any Error).self) {
                try HookInstaller.write(to: link.appendingPathComponent("hooks.json"), command: command, installing: installing)
            }
            #expect(try Data(contentsOf: file) == original)
            #expect(try FileManager.default.contentsOfDirectory(atPath: target.path) == ["hooks.json"])
        }
    }

    @Test func refusesNonprivateDirectoryWithoutChangingTargetOrCreatingBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: directory.path)
        let file = directory.appendingPathComponent("hooks.json")
        try original.write(to: file)
        for installing in [true, false] {
            #expect(throws: (any Error).self) {
                try HookInstaller.write(to: file, command: command, installing: installing)
            }
            #expect(try Data(contentsOf: file) == original)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["hooks.json"])
        }
    }
}
