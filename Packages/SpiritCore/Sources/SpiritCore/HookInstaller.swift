import Foundation
import Darwin

public enum HookInstaller {
    public enum Failure: Error { case damagedJSON, unsafeDirectory, unsafeFile, concurrentChange, replacementFailed }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.damagedJSON }
        if let hooks = root["hooks"] {
            guard let events = hooks as? [String: Any] else { throw Failure.damagedJSON }
            for value in events.values {
                guard let groups = value as? [[String: Any]] else { throw Failure.damagedJSON }
                for group in groups {
                    guard group["hooks"] is [[String: Any]] else { throw Failure.damagedJSON }
                }
            }
        }
        return root
    }

    public static func canonical(_ data: Data) throws -> Data {
        try JSONSerialization.data(withJSONObject: object(data), options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    }

    public static func install(in data: Data, command: String, events names: [String] = CodexHookAdapter.supportedEvents, timeout: Int = 1) throws -> Data {
        var root = try object(data)
        var events = root["hooks"] as? [String: [[String: Any]]] ?? [:]
        for name in names {
            var groups = events[name] ?? []
            let present = groups.contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { owns($0, command: command) }
            }
            if !present { groups.append(["hooks": [["type": "command", "command": command, "timeout": timeout]]]) }
            events[name] = groups
        }
        root["hooks"] = events
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    }

    public static func remove(from data: Data, command: String) throws -> Data {
        var root = try object(data)
        if var events = root["hooks"] as? [String: [[String: Any]]] {
            for name in Array(events.keys) {
                let original = events[name] ?? []
                let groups = original.compactMap { group -> [String: Any]? in
                    var group = group
                    let before = group["hooks"] as? [[String: Any]] ?? []
                    let after = before.filter { !owns($0, command: command) }
                    guard after.count != before.count else { return group }
                    if after.isEmpty { return nil }
                    group["hooks"] = after
                    return group
                }
                if groups.isEmpty && !original.isEmpty { events.removeValue(forKey: name) }
                else { events[name] = groups }
            }
            root["hooks"] = events
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    }

    private static func owns(_ entry: [String: Any], command: String) -> Bool {
        entry["type"] as? String == "command" && entry["command"] as? String == command
    }

    public static func command(bridgeURL: URL) -> String {
        "'" + bridgeURL.path.replacingOccurrences(of: "'", with: "'\\''") + "' --codex-hook"
    }

    /// Call only for an opted-in install/remove action. No default path means previews cannot write accidentally.
    @discardableResult public static func write(to file: URL, command: String, installing: Bool, events: [String] = CodexHookAdapter.supportedEvents, timeout: Int = 1) throws -> URL? {
        let parent = file.deletingLastPathComponent()
        var directory = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if directory < 0 && errno == ENOENT {
            // Only create the final directory; an absent ancestor is not an installation target.
            guard mkdir(parent.path, 0o700) == 0 || errno == EEXIST else { throw Failure.unsafeDirectory }
            directory = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard directory >= 0 else { throw Failure.unsafeDirectory }
        defer { close(directory) }
        var directoryInfo = stat()
        guard fstat(directory, &directoryInfo) == 0, directoryInfo.st_mode & S_IFMT == S_IFDIR,
              directoryInfo.st_uid == getuid(), directoryInfo.st_mode & 0o022 == 0 else { throw Failure.unsafeDirectory }
        let name = file.lastPathComponent
        let initial = try readRegularFile(name, in: directory)
        let original = initial?.data ?? Data("{}".utf8)
        let updated = try installing ? install(in: original, command: command, events: events, timeout: timeout) : remove(from: original, command: command)
        if updated == original || (initial == nil && !installing) { return nil }
        let backupName = initial != nil ? "hooks.json.build-spirit-\(UUID().uuidString).bak" : nil
        if let backupName {
            try createPrivateFile(backupName, in: directory, data: original)
        }
        let temporary = ".spirit-\(UUID().uuidString).tmp"
        defer { unlinkat(directory, temporary, 0) }
        try createPrivateFile(temporary, in: directory, data: updated)
        let current = try readRegularFile(name, in: directory)
        if let initial {
            guard let current, current.info.st_ino == initial.info.st_ino,
                  current.info.st_dev == initial.info.st_dev, current.data == original else { throw Failure.concurrentChange }
        } else if current != nil { throw Failure.concurrentChange }
        guard renameat(directory, temporary, directory, name) == 0 else { throw Failure.replacementFailed }
        return backupName.map { parent.appendingPathComponent($0) }
    }

    private static func readRegularFile(_ name: String, in directory: Int32) throws -> (data: Data, info: stat)? {
        let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw Failure.unsafeFile
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid() else { throw Failure.unsafeFile }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        return (try handle.readToEnd() ?? Data(), info)
    }

    private static func createPrivateFile(_ name: String, in directory: Int32, data: Data) throws {
        let descriptor = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Failure.replacementFailed }
        defer { close(descriptor) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }
}
