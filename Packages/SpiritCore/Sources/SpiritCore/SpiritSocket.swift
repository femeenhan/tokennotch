import Foundation
import Darwin

public enum SpiritSocketLocation {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BuildSpirit/events.sock")
    }
}

private func socketAddress(_ url: URL) -> sockaddr_un? {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(url.path.utf8) + [0]
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
    return address
}

public enum SpiritSocketClient {
    /// A nonblocking datagram is either delivered whole or dropped. There is no payload queue.
    public static func send(_ line: Data, to url: URL) -> Bool {
        guard line.count <= 16_384, var address = socketAddress(url) else { return false }
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFSOCK, info.st_mode & 0o077 == 0 else { return false }
        let descriptor = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { destination in
                line.withUnsafeBytes { bytes in
                    sendto(descriptor, bytes.baseAddress, bytes.count, MSG_DONTWAIT,
                           destination, socklen_t(MemoryLayout<sockaddr_un>.size)) == bytes.count
                }
            }
        }
    }
}

public final class SpiritSocketServer: @unchecked Sendable {
    public enum Failure: Error { case unsafeDirectory, unsafeSocket, pathTooLong, socketUnavailable }
    private let source: DispatchSourceRead

    public init(url: URL = SpiritSocketLocation.defaultURL,
                receive: @escaping @Sendable (SpiritEvent) -> Void) throws {
        let directory = url.deletingLastPathComponent()
        let manager = FileManager.default
        var info = stat()
        if lstat(directory.path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid() else { throw Failure.unsafeDirectory }
        } else {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        guard var address = socketAddress(url) else { throw Failure.pathTooLong }
        let descriptor = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { throw Failure.socketUnavailable }
        var started = false
        defer { if !started { close(descriptor) } }
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        if lstat(url.path, &info) == 0 {
            guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFSOCK else { throw Failure.unsafeSocket }
            // A live listener owns this path. Only a refused stale socket may be removed.
            let probe = socket(AF_UNIX, SOCK_DGRAM, 0)
            guard probe >= 0 else { throw Failure.socketUnavailable }
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            let refused = result < 0 && errno == ECONNREFUSED
            close(probe)
            guard refused else { throw Failure.socketUnavailable }
            guard unlink(url.path) == 0 else { throw Failure.unsafeSocket }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { throw Failure.socketUnavailable }
        do { try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        catch { unlink(url.path); throw error }
        _ = lstat(url.path, &info)
        let inode = info.st_ino
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: DispatchQueue(label: "local.buildspirit.events"))
        source.setEventHandler {
            var bytes = [UInt8](repeating: 0, count: 16_385)
            // Bound work per callback so a flooding client cannot starve cancellation.
            for _ in 0..<32 {
                let size = recv(descriptor, &bytes, bytes.count, MSG_DONTWAIT)
                guard size > 0 else { break }
                guard size <= 16_384 else { continue }
                let data = Data(bytes.prefix(size))
                guard data.last == 10, data.filter({ $0 == 10 }).count == 1,
                      let wire = try? JSONDecoder().decode(SpiritWireEnvelope.self, from: data),
                      wire.event.schemaVersion == 1, SpiritProvider(rawValue: wire.event.provider) != nil,
                      !wire.event.sessionID.isEmpty else { continue }
                receive(wire.event)
            }
        }
        source.setCancelHandler {
            close(descriptor)
            var current = stat()
            if lstat(url.path, &current) == 0 && current.st_ino == inode { unlink(url.path) }
        }
        source.resume()
        started = true
    }

    public func stop() { source.cancel() }
    deinit { source.cancel() }
}

public struct SpiritEventStream: Sendable {
    public private(set) var sessions: [String: SessionState] = [:]
    public private(set) var state: SpiritState = .idle
    public private(set) var completionPresentationID: UUID?
    public private(set) var greetingPresentationID: UUID?
    private var consumption = CompletionConsumption()
    public init() {}
    public mutating func receive(_ event: SpiritEvent) {
        greetingPresentationID = nil
        sessions = reduce(sessions: sessions, event: event)
        aggregate()
        if event.kind == .sessionStarted, state == .idle {
            state = .greeting
            greetingPresentationID = UUID()
        }
    }

    public mutating func finishGreetingPresentation(id: UUID) {
        guard state == .greeting, greetingPresentationID == id else { return }
        greetingPresentationID = nil
        aggregate()
    }

    /// A stale UI callback must not consume a newer completion or replace active work.
    public mutating func finishCompletionPresentation(id: UUID) {
        guard state == .completed, completionPresentationID == id else { return }
        aggregate()
    }

    private mutating func aggregate() {
        let result = aggregateSpiritState(from: sessions, consuming: consumption)
        state = result.state
        consumption = result.completionConsumption
        completionPresentationID = state == .completed ? UUID() : nil
    }
}
