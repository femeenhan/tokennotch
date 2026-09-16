import Darwin
import Foundation
import Testing
@testable import SpiritCore

@Suite("SpiritSocket")
struct SpiritSocketTests {
    @Test func deliversOverPrivateSocketAndUpdatesReducer() async throws {
        let directory = URL(fileURLWithPath: "/tmp/spirit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("events.sock")
        let wire = try CodexHookAdapter.adapt(Data(#"{"session_id":"s","turn_id":"t","hook_event_name":"UserPromptSubmit"}"#.utf8))
        try await confirmation("received") { received in
            let server = try SpiritSocketServer(url: path) { event in
                #expect(event == wire.event)
                var stream = SpiritEventStream()
                #expect(stream.state == .idle)
                stream.receive(event)
                #expect(stream.state == .working)
                received()
            }
            defer { server.stop() }
            #expect(try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int == 0o700)
            #expect(try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? Int == 0o600)
            #expect(SpiritSocketClient.send(try wire.encodedLine(), to: path))
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    @Test func missingSocketReturnsImmediately() {
        let start = Date()
        #expect(!SpiritSocketClient.send(Data("{}\n".utf8), to: URL(fileURLWithPath: "/tmp/absent-\(UUID()).sock")))
        #expect(Date().timeIntervalSince(start) < 0.5)
    }

    @Test func refusesSymlinkDirectory() throws {
        let directory = URL(fileURLWithPath: "/tmp/spirit-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(atPath: directory.path, withDestinationPath: "/tmp")
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: (any Error).self) { try SpiritSocketServer(url: directory.appendingPathComponent("events.sock")) { _ in } }
    }

    @Test func stopDoesNotCreateCompletionAndRestartForgetsActiveSessions() throws {
        var stream = SpiritEventStream()
        for name in ["UserPromptSubmit", "Stop"] {
            stream.receive(try CodexHookAdapter.adapt(Data("{\"session_id\":\"s\",\"turn_id\":\"t\",\"hook_event_name\":\"\(name)\"}".utf8)).event)
        }
        #expect(stream.state == .idle)
        #expect(stream.sessions["s"]?.status == .idle)
        #expect(SpiritEventStream().sessions.isEmpty)
        stream.receive(try CodexHookAdapter.adapt(Data(#"{"session_id":"s","hook_event_name":"SessionEnd"}"#.utf8)).event)
        #expect(stream.state == .completed)
    }

    @Test func sessionStartGreetsOnceThenReturnsToIdle() throws {
        var stream = SpiritEventStream()
        stream.receive(try CodexHookAdapter.adapt(Data(#"{"session_id":"s","hook_event_name":"SessionStart"}"#.utf8)).event)
        #expect(stream.state == .greeting)
        let presentation = try #require(stream.greetingPresentationID)
        stream.finishGreetingPresentation(id: presentation)
        #expect(stream.state == .idle)
        #expect(stream.greetingPresentationID == nil)
    }

    @Test func staleGreetingCallbackCannotOverwriteWork() throws {
        var stream = SpiritEventStream()
        stream.receive(try CodexHookAdapter.adapt(Data(#"{"session_id":"s","hook_event_name":"SessionStart"}"#.utf8)).event)
        let greeting = try #require(stream.greetingPresentationID)
        stream.receive(try CodexHookAdapter.adapt(Data(#"{"session_id":"s","turn_id":"t","hook_event_name":"UserPromptSubmit"}"#.utf8)).event)
        stream.finishGreetingPresentation(id: greeting)
        #expect(stream.state == .working)
    }

    @Test func completionPresentationReturnsToIdleWithoutAnotherHook() throws {
        var stream = SpiritEventStream()
        stream.receive(try CodexHookAdapter.adapt(Data(#"{"session_id":"s","hook_event_name":"SessionEnd"}"#.utf8)).event)
        #expect(stream.state == .completed)
        let presentation = try #require(stream.completionPresentationID)
        stream.finishCompletionPresentation(id: presentation)
        #expect(stream.state == .idle)
        #expect(stream.completionPresentationID == nil)
        #expect(stream.sessions["s"]?.status == .ended)
    }

    @Test func oldCompletionCallbackCannotOverwriteNewWorkingOrAttention() throws {
        for (name, expected) in [("UserPromptSubmit", SpiritState.working), ("PermissionRequest", .attention)] {
            var stream = SpiritEventStream()
            stream.receive(try CodexHookAdapter.adapt(Data(#"{"session_id":"ended","hook_event_name":"SessionEnd"}"#.utf8)).event)
            let old = try #require(stream.completionPresentationID)
            let data = Data("{\"session_id\":\"active\",\"turn_id\":\"t\",\"hook_event_name\":\"\(name)\",\"tool_name\":\"Bash\"}".utf8)
            stream.receive(try CodexHookAdapter.adapt(data).event)
            stream.finishCompletionPresentation(id: old)
            #expect(stream.state == expected)
        }
    }

    @Test func oldCompletionCallbackCannotConsumeNewerCompletionPresentation() throws {
        var stream = SpiritEventStream()
        stream.receive(try CodexHookAdapter.adapt(Data(#"{"session_id":"first","hook_event_name":"SessionEnd"}"#.utf8)).event)
        let old = try #require(stream.completionPresentationID)
        stream.receive(try CodexHookAdapter.adapt(Data(#"{"session_id":"second","hook_event_name":"SessionEnd"}"#.utf8)).event)
        let current = try #require(stream.completionPresentationID)
        stream.finishCompletionPresentation(id: old)
        #expect(stream.state == .completed)
        #expect(stream.completionPresentationID == current)
        stream.finishCompletionPresentation(id: current)
        #expect(stream.state == .idle)
    }
}
