import Foundation
import SpiritCore

extension CompanionModel {
    func configureQuotaHistory(at url: URL) {
        do {
            let store = try QuotaHistoryStore(url: url)
            quotaHistoryStore = store
            quotaHistoryWork = Task { [weak self] in
                let history = await store.snapshots()
                self?.quotaHistory = history
                if self?.quota == nil { self?.quota = history.last }
            }
        } catch {
            quotaHistoryError = "이전 사용량 관측을 불러오지 못했습니다. 새 조회는 계속 사용할 수 있습니다."
        }
    }

    func refreshQuota(force: Bool = false) {
        guard quotaAutomaticAllowed, quotaMonitoringEnabled, !quotaRefreshing, let client = quotaClient,
              Date().timeIntervalSince(quotaLastAttempt) >= (force ? 5 : 60) else { return }
        quotaLastAttempt = Date()
        quotaRefreshing = true
        let historyWork = quotaHistoryWork
        quotaTask = Task { [weak self] in
            await historyWork?.value
            defer { self?.quotaRefreshing = false }
            do {
                let snapshot = try await client.read()
                guard let self, self.quotaMonitoringEnabled else { return }
                self.quota = snapshot
                self.quotaHasSuccessfulRead = true
                self.quotaError = nil
                self.restoreAccountUsage(for: snapshot.accountID)
                if let store = self.quotaHistoryStore {
                    do {
                        try await store.record(snapshot)
                        self.quotaHistory = await store.snapshots()
                        self.quotaHistoryError = nil
                    } catch {
                        self.quotaHistoryError = "사용량은 갱신했지만 추세 기록을 저장하지 못했습니다."
                    }
                }
                do {
                    let usage = try await client.fetchUsage()
                    guard self.quotaMonitoringEnabled else { return }
                    self.accountUsage = usage
                    self.accountUsageError = usage.dailyBuckets == nil ? "현재 응답에 일별 기록이 없습니다. 보관된 기록을 표시합니다." : nil
                    self.mergeAccountUsage(usage, accountID: snapshot.accountID)
                } catch {
                    self.accountUsageError = "일별 토큰 기록을 갱신하지 못했습니다. 남은 한도 조회는 정상입니다."
                }
            } catch {
                self?.quotaError = "계정 한도를 조회하지 못했습니다. Codex 로그인·네트워크 상태를 확인하고 다시 시도하세요."
            }
        }
    }

    private struct DailyArchive: Codable {
        var accountID: String
        var buckets: [CodexDailyUsageBucket]
    }

    private func restoreAccountUsage(for accountID: String?) {
        guard let accountID else {
            accountUsage = nil
            accountUsageDaily = []
            UserDefaults.standard.removeObject(forKey: "accountUsageDaily")
            return
        }
        let data = UserDefaults.standard.data(forKey: "accountUsageDaily")
        let archive = data.flatMap { try? JSONDecoder().decode(DailyArchive.self, from: $0) }
        if archive?.accountID != accountID {
            accountUsage = nil
            accountUsageDaily = []
            UserDefaults.standard.removeObject(forKey: "accountUsageDaily")
        } else { accountUsageDaily = archive?.buckets ?? [] }
    }

    private func mergeAccountUsage(_ usage: CodexAccountUsage, accountID: String?) {
        guard let buckets = usage.dailyBuckets else { return }
        var byDate = Dictionary(accountUsageDaily.map { ($0.startDate, $0) }, uniquingKeysWith: { _, new in new })
        for bucket in buckets { byDate[bucket.startDate] = bucket }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let cutoff = Calendar.current.date(byAdding: .day, value: -181, to: Date())!
        let oldest = formatter.string(from: cutoff), newest = formatter.string(from: Date())
        accountUsageDaily = byDate.values.filter { $0.startDate >= oldest && $0.startDate <= newest }.sorted { $0.startDate < $1.startDate }.suffix(182).map { $0 }
        if let accountID, let data = try? JSONEncoder().encode(DailyArchive(accountID: accountID, buckets: accountUsageDaily)) {
            UserDefaults.standard.set(data, forKey: "accountUsageDaily")
        }
    }

    var generalQuotaBucket: QuotaBucket? {
        quota?.buckets.first { $0.id == "codex" }
    }

    var generalQuotaTrend: QuotaTrend {
        QuotaTrend(history: quotaHistory, bucketID: "codex")
    }

    func quotaIsFresh(at now: Date) -> Bool {
        guard quotaHasSuccessfulRead, quotaMonitoringEnabled, quotaError == nil,
              let quota, now.timeIntervalSince(quota.observedAt) < 180 else { return false }
        let weekly = generalQuotaBucket.flatMap { bucket in
            [bucket.primary, bucket.secondary].compactMap { $0 }.first { $0.windowDurationMins == 10080 }
        }
        return weekly?.resetsAt.map { $0 > now } ?? true
    }
}

extension CompanionModel {
    /// Claude has no quota API: tokens come from local transcripts, limits from the statusLine bridge file.
    func refreshClaudeUsage(force: Bool = false, now: Date = Date()) {
        let modified = (try? claudeRateLimitsURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if modified != claudeRateLimitsModified {
            claudeRateLimitsModified = modified
            claudeRateLimits = ClaudeRateLimits.read(from: claudeRateLimitsURL)
        }
        guard !claudeUsageReading, force || now.timeIntervalSince(claudeUsageLastRead) >= 30 else { return }
        claudeUsageReading = true
        claudeUsageLastRead = now
        let reader = claudeUsageReader
        Task { [weak self] in
            let usage = await reader.read()
            self?.claudeTokenUsage = usage
            self?.claudeUsageReading = false
        }
    }

    var claudeTodayTokens: Int? {
        guard let usage = claudeTokenUsage else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        return usage.daily.first { $0.startDate == today }?.tokens ?? 0
    }

    /// Remaining share of the tightest Claude window that has not reset yet.
    func claudeRemainingQuota(at now: Date) -> Double? { claudeRateLimits?.remainingFraction(at: now) }

    func claudeWindow(_ minutes: Int, at now: Date) -> QuotaWindow? {
        let window = minutes == 300 ? claudeRateLimits?.fiveHour : claudeRateLimits?.sevenDay
        guard let window, window.resetsAt.map({ $0 > now }) ?? true else { return nil }
        return window
    }
}
