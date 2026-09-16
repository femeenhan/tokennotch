import Foundation
import CryptoKit
import Darwin

/// Reads only the URL explicitly supplied by the caller. Rollout JSONL is not a stable API.
public actor UsageFileReader {
    public enum ReadError: Error, LocalizedError, Sendable {
        case unavailable, notRegularFile, changedDuringRead
        public var errorDescription: String? {
            switch self {
            case .unavailable: "선택한 사용량 파일을 읽을 수 없습니다."
            case .notRegularFile: "일반 JSONL 파일을 선택해 주세요."
            case .changedDuringRead: "읽는 중 파일이 변경되었습니다. 다시 시도해 주세요."
            }
        }
    }
    public private(set) var unsupportedRecordCount = 0
    private let url: URL
    private var identity: Identity?
    private var offset: UInt64 = 0
    private var partial = Data()
    private var droppingLine = false
    private var anchors: [Anchor] = []
    private var sessionID: String?
    private var modelID: String?
    private var latest: [String: UsageRecord] = [:]
    private var baseline: Baseline?
    private var boundary: UsageRecord.Attribution?
    private var modelsSinceReport: Set<String> = []
    private let maxLineBytes = 1_048_576
    private let maxPollBytes = 8_388_608

    public init(url: URL) { self.url = url }

    public func read() throws -> [UsageRecord] {
        do { return try readSelectedFile() }
        catch let error as ReadError { reset(); throw error }
        catch { reset(); throw ReadError.unavailable } // Never propagate source text or a private path.
    }

    private func readSelectedFile() throws -> [UsageRecord] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let initial = try fileStat(handle)
        guard initial.st_mode & S_IFMT == S_IFREG else { throw ReadError.notRegularFile }
        let current = Identity(device: initial.st_dev, inode: initial.st_ino)
        let size = UInt64(max(0, initial.st_size))
        var unchanged = identity == current && size >= offset
        if unchanged {
            for anchor in anchors {
                try handle.seek(toOffset: anchor.offset)
                let bytes = try handle.read(upToCount: anchor.count) ?? Data()
                if Data(SHA256.hash(data: bytes)) != anchor.digest { unchanged = false; break }
            }
        }
        if !unchanged { reset(); identity = current }
        try handle.seek(toOffset: offset)
        var changed: [String: UsageRecord] = [:]
        var remaining = min(UInt64(maxPollBytes), size - offset)
        while remaining > 0 {
            let bytes = try handle.read(upToCount: Int(min(65_536, remaining))) ?? Data()
            guard !bytes.isEmpty else { break }
            offset += UInt64(bytes.count); remaining -= UInt64(bytes.count)
            for byte in bytes {
                if byte == 10 {
                    if !droppingLine && !partial.isEmpty {
                        for record in parse(partial) { changed[record.id] = record }
                    }
                    partial.removeAll(keepingCapacity: true); droppingLine = false
                } else if !droppingLine {
                    if partial.count < maxLineBytes { partial.append(byte) }
                    else {
                        partial.removeAll(keepingCapacity: true); droppingLine = true
                        unsupportedRecordCount += 1; boundary = .observationGap
                    }
                }
            }
        }
        let final = try fileStat(handle)
        guard final.st_dev == initial.st_dev, final.st_ino == initial.st_ino,
              final.st_size >= Int64(offset),
              (final.st_size != initial.st_size || (final.st_mtimespec.tv_sec == initial.st_mtimespec.tv_sec && final.st_mtimespec.tv_nsec == initial.st_mtimespec.tv_nsec)) else {
            reset(); throw ReadError.changedDuringRead
        }
        anchors = []
        for position in Set([UInt64(0), offset > 4096 ? offset - 4096 : 0]) {
            let count = Int(min(4096, offset - position))
            guard count > 0 else { continue }
            try handle.seek(toOffset: position)
            let bytes = try handle.read(upToCount: count) ?? Data()
            anchors.append(Anchor(offset: position, count: count, digest: Data(SHA256.hash(data: bytes))))
        }
        return changed.values.sorted { $0.id < $1.id }
    }

    private func reset() {
        offset = 0; partial.removeAll(); droppingLine = false; anchors = []
        sessionID = nil; modelID = nil; latest = [:]; unsupportedRecordCount = 0
        baseline = nil; boundary = nil; modelsSinceReport = []
    }
    private func fileStat(_ handle: FileHandle) throws -> stat {
        var value = stat()
        guard fstat(handle.fileDescriptor, &value) == 0 else { throw ReadError.unavailable }
        return value
    }
    private func parse(_ bytes: Data) -> [UsageRecord] {
        guard let row = try? JSONDecoder().decode(Row.self, from: bytes) else {
            let type = try? JSONDecoder().decode(RowType.self, from: bytes).type
            if type == "session_meta" {
                clearSession()
            } else if type == "turn_context" {
                modelID = nil // An undecodable context must never reuse the previous model.
            }
            boundary = .observationGap
            unsupportedRecordCount += 1; return []
        }
        switch row.type {
        case "session_meta":
            guard let id = row.payload.id, safeIdentifier(id) else {
                clearSession()
                unsupportedRecordCount += 1; return []
            }
            if sessionID != id { clearSession() }
            sessionID = id
        case "turn_context":
            modelID = row.payload.model.flatMap { safeIdentifier($0) ? $0 : nil }
            if let modelID, modelsSinceReport.count < 2 { modelsSinceReport.insert(modelID) }
        case "event_msg" where row.payload.type == "token_count":
            guard let sessionID, let usage = row.payload.info?.total_token_usage,
                  usage.valid, let timestamp = row.timestamp, let date = parseDate(timestamp) else {
                boundary = .observationGap
                unsupportedRecordCount += 1; return []
            }
            let id = "codex-total:\(sessionID)"
            // Repeated cumulative telemetry is not another consumption record.
            if let baseline, baseline.counts == usage { return [] }
            let total = record(id: id, sessionID: sessionID, model: nil, date: date,
                               counts: usage, scope: .sessionTotal, attribution: nil)
            var records = [total]
            if let previous = baseline {
                if let delta = usage.subtracting(previous.counts), delta.valid {
                    var attribution = boundary ?? .observedDelta
                    if date < previous.date { attribution = .observationGap }
                    if attribution == .observedDelta && modelsSinceReport.count > 1 { attribution = .ambiguousModel }
                    let model = attribution == .observedDelta ? modelID : nil
                    if delta.total_tokens > 0 || delta.cached_input_tokens != 0 || delta.reasoning_output_tokens != 0 {
                        let deltaID = immutableID(prefix: "codex-delta", sessionID: sessionID, date: date,
                            counts: usage, previous: previous, model: model, attribution: attribution)
                        records.append(record(id: deltaID, sessionID: sessionID, model: model, date: date,
                            counts: delta, scope: .delta, attribution: attribution))
                    }
                } else {
                    // A decreasing counter starts a new baseline; the raw count is not new usage.
                    let resetID = immutableID(prefix: "codex-history", sessionID: sessionID, date: date,
                        counts: usage, previous: previous, model: nil, attribution: .counterReset)
                    records.append(record(id: resetID, sessionID: sessionID, model: nil, date: date,
                        counts: usage, scope: .historicalUnattributed, attribution: .counterReset))
                }
            } else {
                // Even last_token_usage does not prove a first cumulative report's model/day.
                // Codex uses last usage for the latest active context, not a complete historical ledger.
                let historyID = immutableID(prefix: "codex-history", sessionID: sessionID, date: date,
                    counts: usage, previous: nil, model: nil, attribution: .historicalBaseline)
                records.append(record(id: historyID, sessionID: sessionID, model: nil, date: date,
                    counts: usage, scope: .historicalUnattributed, attribution: .historicalBaseline))
            }
            latest[id] = total
            baseline = Baseline(counts: usage, date: date)
            boundary = nil; modelsSinceReport = []
            return records
        case "compacted": boundary = .compactionBoundary
        case "event_msg" where row.payload.type == "context_compacted": boundary = .compactionBoundary
        case "response_item", "event_msg": break // Non-usage content is never retained.
        default: unsupportedRecordCount += 1; boundary = .observationGap
        }
        return []
    }
    private func clearSession() {
        sessionID = nil; modelID = nil; latest = [:]; baseline = nil; boundary = nil; modelsSinceReport = []
    }
    private func record(id: String, sessionID: String, model: String?, date: Date, counts: Counts,
                        scope: UsageRecord.Scope, attribution: UsageRecord.Attribution?) -> UsageRecord {
        UsageRecord(id: id, sessionID: sessionID, modelID: model, occurredAt: date,
            inputTokens: counts.input_tokens, outputTokens: counts.output_tokens,
            cachedInputTokens: counts.cached_input_tokens, reasoningOutputTokens: counts.reasoning_output_tokens,
            totalTokens: counts.total_tokens, cacheWriteInputTokens: nil, scope: scope, attribution: attribution)
    }
    private func immutableID(prefix: String, sessionID: String, date: Date, counts: Counts,
                             previous: Baseline?, model: String?, attribution: UsageRecord.Attribution) -> String {
        // Only metadata enters this hash. File path/inode/cursor never affects reselection identity.
        let metadata = ["v1", sessionID, String(date.timeIntervalSince1970), counts.fingerprint,
                        previous.map { String($0.date.timeIntervalSince1970) + ":" + $0.counts.fingerprint } ?? "none",
                        model.map { "model:" + $0 } ?? "no-model", attribution.rawValue].joined(separator: "|")
        let digest = SHA256.hash(data: Data(metadata.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(prefix):\(sessionID):\(digest)"
    }
    private func safeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 95, 46, 47, 58].contains($0)
        }
    }
    private func parseDate(_ value: String) -> Date? {
        guard value.utf8.count <= 64 else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
    private struct Identity: Equatable { let device: dev_t; let inode: ino_t }
    private struct Anchor { let offset: UInt64; let count: Int; let digest: Data }
    private struct Baseline { let counts: Counts; let date: Date }
    // Narrow decoding means prompts, responses, tools, commands and patches are never retained.
    private struct Row: Decodable { let type: String; let timestamp: String?; let payload: Payload }
    private struct RowType: Decodable { let type: String }
    private struct Payload: Decodable { let id: String?; let model: String?; let type: String?; let info: Info? }
    private struct Info: Decodable { let total_token_usage: Counts? }
    private struct Counts: Decodable, Equatable {
        let input_tokens: Int; let output_tokens: Int; let total_tokens: Int
        let cached_input_tokens: Int?; let reasoning_output_tokens: Int?
        var fingerprint: String {
            [String(input_tokens), String(output_tokens), String(total_tokens),
             cached_input_tokens.map { String($0) } ?? "nil",
             reasoning_output_tokens.map { String($0) } ?? "nil"].joined(separator: ":")
        }
        func subtracting(_ previous: Counts) -> Counts? {
            guard input_tokens >= previous.input_tokens, output_tokens >= previous.output_tokens,
                  total_tokens >= previous.total_tokens else { return nil }
            func subset(_ value: Int?, _ old: Int?) -> Int? {
                guard let value, let old else { return nil }
                return value - old
            }
            return Counts(input_tokens: input_tokens - previous.input_tokens,
                output_tokens: output_tokens - previous.output_tokens,
                total_tokens: total_tokens - previous.total_tokens,
                cached_input_tokens: subset(cached_input_tokens, previous.cached_input_tokens),
                reasoning_output_tokens: subset(reasoning_output_tokens, previous.reasoning_output_tokens))
        }
        var valid: Bool {
            let sum = input_tokens.addingReportingOverflow(output_tokens)
            return input_tokens >= 0 && output_tokens >= 0 && total_tokens >= 0 && !sum.overflow && sum.partialValue == total_tokens
                && (cached_input_tokens.map { $0 >= 0 && $0 <= input_tokens } ?? true)
                && (reasoning_output_tokens.map { $0 >= 0 && $0 <= output_tokens } ?? true)
        }
    }
}
