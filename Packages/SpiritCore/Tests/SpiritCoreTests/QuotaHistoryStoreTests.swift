import Foundation
import Testing
@testable import SpiritCore

struct QuotaHistoryStoreTests {
    private func file() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("quota.json")
    }
    private func sample(_ seconds: Double, accountID: String? = "account-a") -> QuotaSnapshot {
        QuotaSnapshot(observedAt: Date(timeIntervalSince1970: seconds), buckets: [QuotaBucket(id: "codex", secondary: QuotaWindow(usedPercent: 12, windowDurationMins: 10080))], accountID: accountID)
    }

    @Test func atomicMetadataPersistsAcrossRestartWithPrivatePermissions() async throws {
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try QuotaHistoryStore(url: url)
        try await store.record(sample(100))
        try await store.record(sample(200))
        let reopened = try QuotaHistoryStore(url: url)
        #expect(await reopened.snapshots().map(\.observedAt) == [Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 200)])
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let files = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(files == ["quota.json"])
    }

    @Test func malformedHistoryIsReportedAndNotOverwritten() throws {
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = Data("invalid existing history".utf8)
        try original.write(to: url)
        #expect(throws: (any Error).self) { try QuotaHistoryStore(url: url) }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func retentionIncludesEightDayBoundaryAndDropsOlderSamples() async throws {
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try QuotaHistoryStore(url: url)
        try await store.record(sample(99))
        try await store.record(sample(100))
        try await store.record(sample(691300))
        #expect(await store.snapshots().map(\.observedAt) == [Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 691300)])
        let reopened = try QuotaHistoryStore(url: url)
        #expect(await reopened.snapshots().count == 2)
    }

    @Test func failedAtomicWriteDoesNotChangeInMemoryHistory() async throws {
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try QuotaHistoryStore(url: url)
        try await store.record(sample(100))
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        await #expect(throws: (any Error).self) { try await store.record(sample(200)) }
        #expect(await store.snapshots().map(\.observedAt) == [Date(timeIntervalSince1970: 100)])
    }

    @Test func loadedHistoryAndNextWriteAreBoundedToTwelveThousandSamples() async throws {
        struct Fixture: Encodable { let version: Int; let snapshots: [QuotaSnapshot] }
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try JSONEncoder().encode(Fixture(version: 1, snapshots: (0...12000).map { sample(Double($0)) })).write(to: url)
        let store = try QuotaHistoryStore(url: url)
        #expect(await store.snapshots().count == 12000)
        #expect(await store.snapshots().first?.observedAt == Date(timeIntervalSince1970: 1))
        try await store.record(sample(12001))
        let reopened = try QuotaHistoryStore(url: url)
        #expect(await reopened.snapshots().count == 12000)
        #expect(await reopened.snapshots().first?.observedAt == Date(timeIntervalSince1970: 2))
    }

    @Test func accountSwitchIncludingKnownToUnknownReplacesHistoryAtomically() async throws {
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try QuotaHistoryStore(url: url)
        try await store.record(sample(100))
        try await store.record(sample(200))
        try await store.record(sample(300, accountID: "account-b"))
        #expect(await store.snapshots().count == 1)
        #expect(await store.snapshots().first?.accountID == "account-b")
        try await store.record(sample(400, accountID: nil))
        let reopened = try QuotaHistoryStore(url: url)
        #expect(await reopened.snapshots().count == 1)
        #expect(await reopened.snapshots().first?.accountID == nil)
        #expect(await reopened.snapshots().first?.observedAt == Date(timeIntervalSince1970: 400))
    }

    @Test func oversizedArchiveIsRejectedWithoutReadingOrReplacingContents() throws {
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data().write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 8 * 1024 * 1024 + 1)
        try handle.close()
        #expect(throws: QuotaHistoryStoreError.invalidMetadata) { try QuotaHistoryStore(url: url) }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.size] as? NSNumber)?.intValue == 8 * 1024 * 1024 + 1)
    }
}
