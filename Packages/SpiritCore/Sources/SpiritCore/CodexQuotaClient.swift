import Foundation
import CoreFoundation
import Darwin

/// One short-lived, read-only app-server connection. Never reads credentials or configuration itself.
public actor CodexQuotaClient {
    public enum ClientError: Error, LocalizedError, Sendable {
        case unavailable, timeout, malformedResponse, oversizedResponse, serverRejected, busy
        public var errorDescription: String? {
            switch self {
            case .unavailable: "Codex 할당량 연결을 시작하거나 읽을 수 없습니다."
            case .timeout: "Codex 할당량 조회 시간이 초과되었습니다."
            case .malformedResponse: "Codex 할당량 응답 형식을 확인할 수 없습니다."
            case .oversizedResponse: "Codex 할당량 응답이 허용 크기를 초과했습니다."
            case .serverRejected: "Codex가 할당량 조회를 거절했습니다. 로그인 상태를 확인해 주세요."
            case .busy: "Codex 할당량을 이미 조회하고 있습니다."
            }
        }
    }
    private let executableURL: URL
    private var reading = false
    public init(executableURL: URL) { self.executableURL = executableURL }

    public func read() async throws -> QuotaSnapshot {
        let data = try await requestData(.quota)
        return try Self.parse(responseData: data)
    }

    public func fetchUsage(threadID: String? = nil) async throws -> CodexAccountUsage {
        if let threadID {
            guard !(try Self.optionalString(threadID) ?? "").isEmpty else { throw ClientError.malformedResponse }
        }
        let data = try await requestData(.usage(threadID: threadID))
        return try Self.parseUsage(responseData: data)
    }

    private enum Request: Sendable {
        case quota, usage(threadID: String?)
        var method: String {
            switch self { case .quota: "account/rateLimits/read"; case .usage: "account/usage/read" }
        }
        var parameters: [String: Any] {
            switch self {
            case .quota: ["excludeResetCreditDetails": true]
            case .usage(let threadID): threadID.map { ["threadId": $0] } ?? [:]
            }
        }
    }

    private func requestData(_ request: Request) async throws -> Data {
        guard !reading else { throw ClientError.busy }
        try Task.checkCancellation()
        reading = true
        defer { reading = false }
        let executable = executableURL
        let cancellation = RequestCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        let data = try Self.exchange(executableURL: executable, cancellation: cancellation, request: request)
                        continuation.resume(returning: data)
                    } catch let error as ClientError { continuation.resume(throwing: error) }
                    catch is CancellationError { continuation.resume(throwing: CancellationError()) }
                    catch { continuation.resume(throwing: ClientError.unavailable) }
                }
            }
        } onCancel: { cancellation.cancel() }
    }

    /// Strict allowlist for the account/usage/read result. No costs or content survive parsing.
    public nonisolated static func parseUsage(responseData: Data, observedAt: Date = Date()) throws -> CodexAccountUsage {
        guard responseData.count <= 1_048_576 else { throw ClientError.oversizedResponse }
        guard let object = try? JSONSerialization.jsonObject(with: responseData),
              let response = object as? [String: Any], let summary = response["summary"] as? [String: Any] else {
            throw ClientError.malformedResponse
        }
        let lifetime = try tokenCount(summary["lifetimeTokens"])
        var daily: [CodexDailyUsageBucket]?
        if let raw = response["dailyUsageBuckets"], !(raw is NSNull) {
            guard let rows = raw as? [[String: Any]], rows.count <= 3660 else { throw ClientError.malformedResponse }
            var buckets: [CodexDailyUsageBucket] = []
            for row in rows {
                guard let date = row["startDate"] as? String, validDay(date),
                      let tokens = try tokenCount(row["tokens"]) else { throw ClientError.malformedResponse }
                buckets.append(CodexDailyUsageBucket(startDate: date, tokens: tokens))
            }
            guard Set(buckets.map(\.startDate)).count == buckets.count else { throw ClientError.malformedResponse }
            daily = buckets.sorted { $0.startDate < $1.startDate }
        }
        var thread: CodexThreadUsage?
        if let raw = response["threadUsage"], !(raw is NSNull) {
            guard let value = raw as? [String: Any], let id = try optionalString(value["threadId"]), !id.isEmpty,
                  let groups = value["groups"] as? [[String: Any]], groups.count <= 256 else { throw ClientError.malformedResponse }
            thread = CodexThreadUsage(threadID: id, groups: try groups.map { group in
                CodexThreadUsageGroup(modelID: try optionalString(group["model"]),
                    inputTokens: try tokenCount(group["inputTokens"]), outputTokens: try tokenCount(group["outputTokens"]),
                    cachedInputTokens: try tokenCount(group["cachedInputTokens"]), netNewInputTokens: try tokenCount(group["netNewInputTokens"]),
                    totalTokens: try tokenCount(group["totalTokens"]))
            })
        }
        return CodexAccountUsage(observedAt: observedAt, lifetimeTokens: lifetime, dailyBuckets: daily, threadUsage: thread)
    }

    private nonisolated static func tokenCount(_ raw: Any?) throws -> Int? {
        guard let raw, !(raw is NSNull) else { return nil }
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let count = Int(number.stringValue), count >= 0 else { throw ClientError.malformedResponse }
        return count
    }

    private nonisolated static func validDay(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }),
              let year = Int(value.prefix(4)), year >= 1,
              let month = Int(value.dropFirst(5).prefix(2)), let day = Int(value.suffix(2)) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return false }
        let verified = calendar.dateComponents([.year, .month, .day], from: date)
        return verified.year == year && verified.month == month && verified.day == day
    }

    /// Parses only quota metadata from the account/rateLimits/read *result* object.
    public nonisolated static func parse(responseData: Data, observedAt: Date = Date()) throws -> QuotaSnapshot {
        guard responseData.count <= 1_048_576,
              let object = try? JSONSerialization.jsonObject(with: responseData),
              let response = object as? [String: Any] else { throw ClientError.malformedResponse }
        var buckets: [QuotaBucket] = []
        if let raw = response["rateLimitsByLimitId"], !(raw is NSNull) {
            guard let multiple = raw as? [String: Any], multiple.count <= 64 else { throw ClientError.malformedResponse }
            for key in multiple.keys.sorted() {
                guard let rawBucket = multiple[key], !(rawBucket is NSNull) else { continue }
                guard let value = rawBucket as? [String: Any] else { throw ClientError.malformedResponse }
                buckets.append(try bucket(value, fallbackID: key))
            }
        }
        if buckets.isEmpty {
            guard let single = response["rateLimits"] as? [String: Any] else { throw ClientError.malformedResponse }
            buckets = [try bucket(single, fallbackID: "codex")]
        }
        guard Set(buckets.map(\.id)).count == buckets.count else { throw ClientError.malformedResponse }
        return QuotaSnapshot(observedAt: observedAt, buckets: buckets, accountID: try optionalString(response["accountId"]))
    }

    private nonisolated static func bucket(_ value: [String: Any], fallbackID: String) throws -> QuotaBucket {
        let id = try optionalString(value["limitId"]) ?? fallbackID
        guard !id.isEmpty, id.utf8.count <= 256, !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ClientError.malformedResponse
        }
        return QuotaBucket(id: id, name: try optionalString(value["limitName"]),
            modelID: try optionalString(value["normalModelSlug"]), primary: try window(value["primary"]),
            secondary: try window(value["secondary"]))
    }
    private nonisolated static func optionalString(_ raw: Any?) throws -> String? {
        guard let raw, !(raw is NSNull) else { return nil }
        guard let value = raw as? String, value.utf8.count <= 256,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw ClientError.malformedResponse }
        return value
    }
    private nonisolated static func numeric(_ raw: Any?) -> Double? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
    private nonisolated static func window(_ raw: Any?) throws -> QuotaWindow? {
        guard let raw, !(raw is NSNull) else { return nil }
        guard let value = raw as? [String: Any], let used = numeric(value["usedPercent"]), (0...100).contains(used) else {
            throw ClientError.malformedResponse
        }
        var duration: Int?
        if let rawDuration = value["windowDurationMins"], !(rawDuration is NSNull) {
            guard let number = numeric(rawDuration), number > 0, number < Double(Int.max), number.rounded() == number else {
                throw ClientError.malformedResponse
            }
            duration = Int(number)
        }
        var reset: Date?
        if let rawReset = value["resetsAt"], !(rawReset is NSNull) {
            guard let epoch = numeric(rawReset), epoch >= 0, epoch <= 253_402_300_799, epoch.rounded() == epoch else {
                throw ClientError.malformedResponse
            }
            reset = Date(timeIntervalSince1970: epoch)
        }
        return QuotaWindow(usedPercent: used, windowDurationMins: duration, resetsAt: reset)
    }

    private nonisolated static func exchange(executableURL: URL, cancellation: RequestCancellation, request: Request) throws -> Data {
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let deadline = DispatchTime.now().uptimeNanoseconds + 20_000_000_000
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            // Bounded grace period, then kill. Do not wait indefinitely for a stubborn child.
            let end = DispatchTime.now().uptimeNanoseconds + 200_000_000
            while process.isRunning && DispatchTime.now().uptimeNanoseconds < end { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            try? input.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
        }
        try process.run()
        try input.fileHandleForReading.close()
        try output.fileHandleForWriting.close()
        let inputFD = input.fileHandleForWriting.fileDescriptor
        let outputFD = output.fileHandleForReading.fileDescriptor
        guard fcntl(inputFD, F_SETNOSIGPIPE, 1) == 0,
              fcntl(outputFD, F_SETFL, fcntl(outputFD, F_GETFL) | O_NONBLOCK) == 0 else { throw ClientError.unavailable }
        try send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "build_spirit_quota", "title": "Build Spirit", "version": "1.0"],
            "capabilities": ["experimentalApi": false, "requestAttestation": false]
        ]], to: input.fileHandleForWriting)
        var reader = LineReader(fd: outputFD, deadline: deadline, cancellation: cancellation)
        _ = try reader.response(id: 1)
        try send(["method": "initialized"], to: input.fileHandleForWriting)
        try send(["id": 2, "method": request.method, "params": request.parameters], to: input.fileHandleForWriting)
        let result = try reader.response(id: 2)
        return try JSONSerialization.data(withJSONObject: result)
    }
    private nonisolated static func send(_ object: [String: Any], to handle: FileHandle) throws {
        var bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        bytes.append(10)
        try handle.write(contentsOf: bytes)
    }

    private final class RequestCancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() { lock.withLock { cancelled = true } }
        var isCancelled: Bool { lock.withLock { cancelled } }
    }
    private struct LineReader {
        let fd: Int32
        let deadline: UInt64
        let cancellation: RequestCancellation
        var buffered = Data()
        var totalBytes = 0
        mutating func response(id: Int) throws -> [String: Any] {
            while true {
                if cancellation.isCancelled { throw CancellationError() }
                guard DispatchTime.now().uptimeNanoseconds < deadline else { throw ClientError.timeout }
                if let newline = buffered.firstIndex(of: 10) {
                    let line = buffered[..<newline]
                    buffered.removeSubrange(...newline)
                    guard !line.isEmpty else { continue }
                    guard let raw = try? JSONSerialization.jsonObject(with: line), let object = raw as? [String: Any] else {
                        throw ClientError.malformedResponse
                    }
                    guard numeric(object["id"]) == Double(id) else { continue } // Notifications/unrelated IDs are ignored.
                    if object["error"] != nil { throw ClientError.serverRejected }
                    guard let result = object["result"] as? [String: Any] else { throw ClientError.malformedResponse }
                    return result
                }
                guard buffered.count <= 262_144 else { throw ClientError.oversizedResponse }
                var descriptor = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0)
                let ready = poll(&descriptor, 1, 50)
                if ready < 0 { if errno == EINTR { continue }; throw ClientError.unavailable }
                guard ready > 0 else { continue }
                var chunk = [UInt8](repeating: 0, count: 16_384)
                let count = Darwin.read(fd, &chunk, chunk.count)
                if count < 0 { if errno == EAGAIN || errno == EINTR { continue }; throw ClientError.unavailable }
                guard count > 0 else { throw ClientError.unavailable }
                totalBytes += count
                guard totalBytes <= 1_048_576 else { throw ClientError.oversizedResponse }
                buffered.append(contentsOf: chunk.prefix(count))
            }
        }
    }
}
