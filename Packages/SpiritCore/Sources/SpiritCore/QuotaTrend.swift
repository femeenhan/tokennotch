import Foundation

/// Observed account/bucket changes, never attributed to a session or inferred model.
public struct QuotaTrend: Sendable {
    public let todayUsedPercentagePoints: Double?
    public let recentUsedPercentagePoints: Double?
    public let recentObservationMinutes: Int?
    public let riskMessage: String?
    public let weeklyWindow: QuotaWindow?
    public let remainingDays: Double?
    public let sampleCount: Int

    public init(history: [QuotaSnapshot], bucketID: String, now: Date = Date(), calendar: Calendar = .current) {
        func weekly(_ snapshot: QuotaSnapshot) -> QuotaWindow? {
            guard let bucket = snapshot.buckets.first(where: { $0.id == bucketID }),
                  let window = [bucket.secondary, bucket.primary].compactMap({ $0 })
                    .first(where: { $0.windowDurationMins == 10080 }),
                  window.usedPercent.isFinite, (0...100).contains(window.usedPercent) else { return nil }
            return window
        }
        let observations = history.filter { $0.observedAt <= now }.sorted { $0.observedAt < $1.observedAt }
        let samples: [(date: Date, window: QuotaWindow)] = observations
            .compactMap { snapshot in
                guard let window = weekly(snapshot) else { return nil }
                return (snapshot.observedAt, window)
            }
        sampleCount = samples.count
        // The latest raw observation controls availability, not the last supported one.
        guard let latest = observations.last, let latestWindow = weekly(latest) else {
            weeklyWindow = nil
            remainingDays = nil
            todayUsedPercentagePoints = nil
            recentUsedPercentagePoints = nil
            recentObservationMinutes = nil
            riskMessage = nil
            return
        }
        weeklyWindow = latestWindow
        if let reset = latestWindow.resetsAt, reset > now {
            remainingDays = reset.timeIntervalSince(now) / 86400
        } else {
            remainingDays = nil
        }

        func change(_ interval: [(date: Date, window: QuotaWindow)], minimumSeconds: Double = 0) -> Double? {
            guard interval.count >= 2, let first = interval.first, let last = interval.last,
                  let accountID = latest.accountID, !accountID.isEmpty,
                  let reset = latestWindow.resetsAt,
                  last.date.timeIntervalSince(first.date) >= minimumSeconds,
                  last.date > first.date else { return nil }
            // An intervening unsupported/missing window is a discontinuity, not a
            // record that can safely be dropped to bridge two otherwise valid samples.
            for snapshot in observations where snapshot.observedAt >= first.date && snapshot.observedAt <= last.date {
                guard snapshot.accountID == accountID, let window = weekly(snapshot),
                      let sampleReset = window.resetsAt,
                      abs(sampleReset.timeIntervalSince(reset)) <= 5, window.usedPercent.isFinite,
                      (0...100).contains(window.usedPercent) else { return nil }
            }
            var previous = first.window.usedPercent
            for sample in interval {
                // The backend's reset timestamp can jitter by a second. Anchor every
                // comparison to the latest reset so tolerances never accumulate drift.
                guard let sampleReset = sample.window.resetsAt,
                      abs(sampleReset.timeIntervalSince(reset)) <= 5,
                      sample.window.windowDurationMins == 10080,
                      sample.window.usedPercent >= previous else { return nil }
                previous = sample.window.usedPercent
            }
            return last.window.usedPercent - first.window.usedPercent
        }

        let today = samples.filter { $0.date >= calendar.startOfDay(for: now) }
        todayUsedPercentagePoints = change(today)
        let recent = samples.filter { $0.date >= now.addingTimeInterval(-3600) }
        let recentChange = change(recent, minimumSeconds: 15 * 60)
        recentUsedPercentagePoints = recentChange
        if recentChange != nil, let first = recent.first, let last = recent.last {
            recentObservationMinutes = Int(last.date.timeIntervalSince(first.date) / 60)
        } else {
            recentObservationMinutes = nil
        }

        var message: String?
        if recent.count >= 3, let increase = change(recent, minimumSeconds: 30 * 60), increase > 0,
           let first = recent.first, let last = recent.last, let reset = last.window.resetsAt,
           reset > now, now.timeIntervalSince(last.date) <= 5 * 60 {
            // Percentages are often integer-quantized. Minute-to-minute plateaus
            // are normal; compare two substantial spans rather than every poll.
            let midpoint = first.date.addingTimeInterval(last.date.timeIntervalSince(first.date) / 2)
            let split = recent.dropFirst().dropLast().filter {
                $0.date.timeIntervalSince(first.date) >= 15 * 60 &&
                last.date.timeIntervalSince($0.date) >= 15 * 60
            }.min { abs($0.date.timeIntervalSince(midpoint)) < abs($1.date.timeIntervalSince(midpoint)) }
            if let split {
                let firstRate = (split.window.usedPercent - first.window.usedPercent) / split.date.timeIntervalSince(first.date)
                let secondRate = (last.window.usedPercent - split.window.usedPercent) / last.date.timeIntervalSince(split.date)
                let minimum = min(firstRate, secondRate)
                let maximum = max(firstRate, secondRate)
                guard minimum.isFinite, maximum.isFinite, minimum > 0,
                      maximum <= minimum * 2 else {
                    riskMessage = nil
                    return
                }
                let rate = increase / last.date.timeIntervalSince(first.date)
                let secondsToDepletion = (100 - last.window.usedPercent) / rate
                if secondsToDepletion < reset.timeIntervalSince(now) {
                    message = "현재 관측 속도가 유지되면 주간 한도가 초기화 전에 소진될 수 있습니다."
                }
            }
        }
        riskMessage = message
    }
}
