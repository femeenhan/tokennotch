import Foundation
import Darwin

/// Claude Code token usage aggregated from local transcript JSONL files.
public struct ClaudeTokenUsage: Equatable, Sendable {
    public let observedAt: Date
    /// Ascending by `startDate` ("yyyy-MM-dd" in the reader calendar's time zone).
    public let daily: [CodexDailyUsageBucket]
    public let totalTokens: Int
    public init(observedAt: Date, daily: [CodexDailyUsageBucket], totalTokens: Int) {
        self.observedAt = observedAt; self.daily = daily; self.totalTokens = totalTokens
    }
}

/// Incrementally reads `~/.claude/projects/**/*.jsonl` and aggregates assistant `usage` per day.
/// Only message identifiers, timestamps and token counts are retained; never prompt or response text.
public actor ClaudeTranscriptUsageReader {
    private struct FileState {
        var device: dev_t
        var inode: ino_t
        var offset: UInt64
        var partial: [UInt8]
        var dropping: Bool
    }
    private struct Entry {
        let date: Date
        let dayKey: String
        let tokens: Int
        let outputTokens: Int
    }

    private let root: URL
    private let calendar: Calendar
    private let maxAgeDays: Int
    private let maxLineBytes = 4 * 1_048_576
    private let chunkSize = 1_048_576
    private var files: [String: FileState] = [:]
    private var entries: [String: Entry] = [:]
    private let dayFormatter: DateFormatter
    private let isoFallback = ISO8601DateFormatter()
    private let isoFractionalFallback: ISO8601DateFormatter

    public init(root: URL, calendar: Calendar = Calendar(identifier: .gregorian), maxAgeDays: Int = 182) {
        self.root = root
        self.calendar = calendar
        self.maxAgeDays = max(1, maxAgeDays)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        dayFormatter = formatter
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFractionalFallback = fractional
    }

    public func read(now: Date = Date()) -> ClaudeTokenUsage {
        let cutoff = windowStart(now: now)
        scan(cutoff: cutoff)
        entries = entries.filter { $0.value.date >= cutoff }
        var byDay: [String: Int] = [:]
        var total = 0
        for entry in entries.values {
            byDay[entry.dayKey, default: 0] += entry.tokens
            total += entry.tokens
        }
        let daily = byDay.map { CodexDailyUsageBucket(startDate: $0.key, tokens: $0.value) }
            .sorted { $0.startDate < $1.startDate }
        return ClaudeTokenUsage(observedAt: now, daily: daily, totalTokens: total)
    }

    private func windowStart(now: Date) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(maxAgeDays - 1), to: today) ?? today
    }

    // MARK: - File scanning

    private func scan(cutoff: Date) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return }
        var seen = Set<String>()
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            let path = url.path
            if files[path] == nil, let modified = values.contentModificationDate, modified < cutoff { continue }
            seen.insert(path)
            readFile(path: path, cutoff: cutoff)
        }
        files = files.filter { seen.contains($0.key) }
    }

    private func readFile(path: String, cutoff: Date) {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { files[path] = nil; return }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { files[path] = nil; return }
        let size = UInt64(max(0, info.st_size))
        var state = files[path] ?? FileState(device: info.st_dev, inode: info.st_ino, offset: 0, partial: [], dropping: false)
        if state.device != info.st_dev || state.inode != info.st_ino || size < state.offset {
            state = FileState(device: info.st_dev, inode: info.st_ino, offset: 0, partial: [], dropping: false)
        }
        guard size > state.offset else { files[path] = state; return }
        guard lseek(fd, off_t(state.offset), SEEK_SET) >= 0 else { files[path] = nil; return }

        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, chunkSize) }
            guard count > 0 else { break }
            state.offset += UInt64(count)
            buffer.withUnsafeBytes { raw in
                let bytes = UnsafeRawBufferPointer(rebasing: raw[0..<count])
                consume(bytes, state: &state, cutoff: cutoff)
            }
        }
        files[path] = state
    }

    private func consume(_ bytes: UnsafeRawBufferPointer, state: inout FileState, cutoff: Date) {
        guard let base = bytes.baseAddress else { return }
        var start = 0
        let end = bytes.count
        while start < end {
            let remaining = end - start
            guard let hit = memchr(base + start, 0x0A, remaining) else {
                // No newline: keep as partial line until the next read.
                if !state.dropping {
                    if state.partial.count + remaining > maxLineBytes {
                        state.partial.removeAll(); state.dropping = true
                    } else {
                        state.partial.append(contentsOf: UnsafeRawBufferPointer(start: base + start, count: remaining))
                    }
                }
                return
            }
            let newline = base.distance(to: UnsafeRawPointer(hit))
            let segment = UnsafeRawBufferPointer(start: base + start, count: newline - start)
            if state.dropping {
                state.dropping = false
            } else if state.partial.isEmpty {
                if segment.count <= maxLineBytes { handleLine(segment, cutoff: cutoff) }
            } else {
                if state.partial.count + segment.count <= maxLineBytes {
                    state.partial.append(contentsOf: segment)
                    state.partial.withUnsafeBytes { handleLine($0, cutoff: cutoff) }
                }
            }
            state.partial.removeAll(keepingCapacity: false)
            start = newline + 1
        }
    }

    // MARK: - Line parsing

    private static let usageNeedle = Array("\"usage\"".utf8)
    private static let assistantNeedle = Array("\"assistant\"".utf8)

    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                let input_tokens: Int?
                let output_tokens: Int?
                let cache_creation_input_tokens: Int?
                let cache_read_input_tokens: Int?
            }
            let id: String?
            let model: String?
            let usage: Usage?
        }
        let type: String?
        let timestamp: String?
        let requestId: String?
        let message: Message?
    }

    private func handleLine(_ line: UnsafeRawBufferPointer, cutoff: Date) {
        guard !line.isEmpty,
              Self.contains(line, Self.usageNeedle),
              Self.contains(line, Self.assistantNeedle) else { return }
        guard let row = try? JSONDecoder().decode(Line.self, from: Data(line)),
              row.type == "assistant",
              let message = row.message, let usage = message.usage,
              message.model != "<synthetic>",
              let key = message.id.map({ "m:" + $0 }) ?? row.requestId.map({ "r:" + $0 }),
              let stamp = row.timestamp, let date = parseTimestamp(stamp),
              date >= cutoff else { return }
        let output = max(0, usage.output_tokens ?? 0)
        let tokens = max(0, usage.input_tokens ?? 0) + output
            + max(0, usage.cache_creation_input_tokens ?? 0) + max(0, usage.cache_read_input_tokens ?? 0)
        if let existing = entries[key], existing.outputTokens >= output { return }
        entries[key] = Entry(date: date, dayKey: dayFormatter.string(from: date), tokens: tokens, outputTokens: output)
    }

    private static func contains(_ haystack: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Bool {
        needle.withUnsafeBytes { n in
            memmem(haystack.baseAddress, haystack.count, n.baseAddress, n.count) != nil
        }
    }

    /// Fast path for "yyyy-MM-ddTHH:mm:ss(.fff)Z"; falls back to ISO8601DateFormatter.
    private func parseTimestamp(_ text: String) -> Date? {
        let u = Array(text.utf8)
        func num(_ from: Int, _ len: Int) -> Int? {
            var value = 0
            for i in from..<(from + len) {
                let c = u[i]
                guard c >= 48 && c <= 57 else { return nil }
                value = value * 10 + Int(c - 48)
            }
            return value
        }
        if u.count >= 20, u[4] == 45, u[7] == 45, u[10] == 84, u[13] == 58, u[16] == 58, u.last == 90,
           let y = num(0, 4), let mo = num(5, 2), let d = num(8, 2),
           let h = num(11, 2), let mi = num(14, 2), let s = num(17, 2),
           (1...12).contains(mo), (1...31).contains(d), h < 24, mi < 60, s < 61 {
            var fraction = 0.0
            if u.count > 20 {
                guard u[19] == 46, u.count > 21 else { return fallbackTimestamp(text) }
                var scale = 0.1
                for c in u[20..<(u.count - 1)] {
                    guard c >= 48 && c <= 57 else { return fallbackTimestamp(text) }
                    fraction += Double(c - 48) * scale; scale /= 10
                }
            } else if u[19] != 90 {
                return fallbackTimestamp(text)
            }
            // Days from civil (Howard Hinnant's algorithm).
            let yy = mo <= 2 ? y - 1 : y
            let era = (yy >= 0 ? yy : yy - 399) / 400
            let yoe = yy - era * 400
            let mp = (mo + 9) % 12
            let doy = (153 * mp + 2) / 5 + d - 1
            let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
            let days = era * 146_097 + doe - 719_468
            let seconds = Double(days * 86_400 + h * 3_600 + mi * 60 + s) + fraction
            return Date(timeIntervalSince1970: seconds)
        }
        return fallbackTimestamp(text)
    }

    private func fallbackTimestamp(_ text: String) -> Date? {
        isoFractionalFallback.date(from: text) ?? isoFallback.date(from: text)
    }
}
