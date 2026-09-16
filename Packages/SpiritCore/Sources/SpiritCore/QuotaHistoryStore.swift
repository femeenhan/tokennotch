import Foundation
import Darwin

public enum QuotaHistoryStoreError: Error, Sendable {
    case unsupportedVersion
    case invalidMetadata
}

/// Private, bounded quota metadata only; no session logs or content are accessed.
public actor QuotaHistoryStore {
    private struct Archive: Codable {
        let version: Int
        let snapshots: [QuotaSnapshot]
    }
    private let url: URL
    private var history: [QuotaSnapshot]

    public init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber, size.int64Value <= 8 * 1024 * 1024 else {
                throw QuotaHistoryStoreError.invalidMetadata
            }
            let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
            guard archive.version == 1 else { throw QuotaHistoryStoreError.unsupportedVersion }
            for snapshot in archive.snapshots { try Self.validate(snapshot) }
            history = Self.bounded(archive.snapshots)
        } else {
            history = []
        }
    }

    public func snapshots() -> [QuotaSnapshot] { history }

    public func record(_ snapshot: QuotaSnapshot) throws {
        try Self.validate(snapshot)
        // A bucket identifier is not an account identity. Never bridge an account switch,
        // including known-to-unknown transitions, with prior usage observations.
        var candidate = history.last?.accountID == snapshot.accountID
            ? history.filter { $0.observedAt != snapshot.observedAt } : []
        candidate.append(snapshot)
        candidate = Self.bounded(candidate)
        let data = try JSONEncoder().encode(Archive(version: 1, snapshots: candidate))
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        let temporary = directory.appendingPathComponent(".quota-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary)
        // Same-directory POSIX rename atomically publishes a complete, already private file.
        guard rename(temporary.path, url.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        history = candidate
    }

    private static func bounded(_ snapshots: [QuotaSnapshot]) -> [QuotaSnapshot] {
        let sorted = snapshots.sorted { $0.observedAt < $1.observedAt }
        guard let latest = sorted.last else { return [] }
        let cutoff = latest.observedAt.addingTimeInterval(-8 * 86400)
        return Array(sorted.filter { $0.observedAt >= cutoff }.suffix(12000))
    }

    private static func validate(_ snapshot: QuotaSnapshot) throws {
        guard snapshot.observedAt.timeIntervalSince1970.isFinite else { throw QuotaHistoryStoreError.invalidMetadata }
        for bucket in snapshot.buckets {
            for window in [bucket.primary, bucket.secondary].compactMap({ $0 }) {
                guard window.usedPercent.isFinite, (0...100).contains(window.usedPercent),
                      window.windowDurationMins.map({ $0 > 0 }) ?? true,
                      window.resetsAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true else {
                    throw QuotaHistoryStoreError.invalidMetadata
                }
            }
        }
    }
}
