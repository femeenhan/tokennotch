import Foundation
import Darwin

/// Claude Code subscription limits, as reported to the statusLine command (Pro/Max only).
public struct ClaudeRateLimits: Codable, Equatable, Sendable {
    public enum Failure: Error { case unsafeDirectory, writeFailed }

    public static let maximumFileBytes = 64 * 1024

    public let observedAt: Date
    public let fiveHour: QuotaWindow?
    public let sevenDay: QuotaWindow?

    public init(observedAt: Date, fiveHour: QuotaWindow?, sevenDay: QuotaWindow?) {
        self.observedAt = observedAt; self.fiveHour = fiveHour; self.sevenDay = sevenDay
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BuildSpirit/claude-rate-limits.json")
    }

    /// Parses the statusLine stdin JSON. Returns nil when no usable window is present.
    public static func parseStatusLine(_ data: Data, now: Date) -> ClaudeRateLimits? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = root["rate_limits"] as? [String: Any] else { return nil }
        let fiveHour = window(limits["five_hour"], minutes: 300)
        let sevenDay = window(limits["seven_day"], minutes: 10080)
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return ClaudeRateLimits(observedAt: now, fiveHour: fiveHour, sevenDay: sevenDay)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    private static func window(_ value: Any?, minutes: Int) -> QuotaWindow? {
        guard let object = value as? [String: Any], let used = number(object["used_percentage"]), used >= 0 else { return nil }
        let resetsAt = number(object["resets_at"]).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        return QuotaWindow(usedPercent: min(used, 100), windowDurationMins: minutes, resetsAt: resetsAt)
    }

    /// Lowest remaining fraction (0...1) across windows that have not reset yet.
    public func remainingFraction(at now: Date) -> Double? {
        let fractions = [fiveHour, sevenDay].compactMap { window -> Double? in
            guard let window, window.resetsAt.map({ $0 > now }) ?? true,
                  let remaining = window.remainingPercent else { return nil }
            return remaining / 100
        }
        return fractions.min()
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// Atomically replaces `file` (mode 0600). The parent directory must already exist and be owned by the user.
    public static func write(_ limits: ClaudeRateLimits, to file: URL) throws {
        let data = try encoder().encode(limits)
        let directory = open(file.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw Failure.unsafeDirectory }
        defer { close(directory) }
        var info = stat()
        guard fstat(directory, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid() else { throw Failure.unsafeDirectory }
        let temporary = ".claude-rate-limits-\(UUID().uuidString).tmp"
        let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Failure.writeFailed }
        var renamed = false
        defer { if !renamed { unlinkat(directory, temporary, 0) } }
        do {
            defer { close(descriptor) }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            try handle.write(contentsOf: data)
        }
        guard renameat(directory, temporary, directory, file.lastPathComponent) == 0 else { throw Failure.writeFailed }
        renamed = true
    }

    /// Returns nil for a missing, non-regular, oversized or invalid file.
    public static func read(from file: URL) -> ClaudeRateLimits? {
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size <= maximumFileBytes else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        guard let data = try? handle.read(upToCount: maximumFileBytes + 1), data.count <= maximumFileBytes else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(ClaudeRateLimits.self, from: data)
    }
}
