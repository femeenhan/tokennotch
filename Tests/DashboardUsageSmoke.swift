import AppKit
import SwiftUI
import SpiritCore

@main @MainActor enum DashboardUsageSmoke {
    static func main() throws {
        _ = NSApplication.shared
        DashboardTheme.registerFonts()
        let model = CompanionModel()
        let now = Date()
        model.quota = QuotaSnapshot(observedAt: now, buckets: [
            QuotaBucket(id: "codex", primary: QuotaWindow(usedPercent: 67, windowDurationMins: 10080, resetsAt: now.addingTimeInterval(345600))),
            QuotaBucket(id: "codex_bengalfox", primary: QuotaWindow(usedPercent: 0, windowDurationMins: 300, resetsAt: now.addingTimeInterval(14400)), secondary: QuotaWindow(usedPercent: 3, windowDurationMins: 10080, resetsAt: now.addingTimeInterval(345600)))
        ], accountID: "fixture")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        model.accountUsageDaily = (0..<182).map { day in
            CodexDailyUsageBucket(startDate: formatter.string(from: Calendar.current.date(byAdding: .day, value: -day, to: now)!), tokens: (day % 9) * 123456)
        }
        model.quotaHasSuccessfulRead = true
        model.quotaHistory = (0..<60).map { minute in
            QuotaSnapshot(observedAt: now.addingTimeInterval(Double(minute - 59) * 60), buckets: [
                QuotaBucket(id: "codex", primary: QuotaWindow(usedPercent: 64 + Double(minute) / 59 * 3, windowDurationMins: 10080, resetsAt: now.addingTimeInterval(345600))),
                QuotaBucket(id: "codex_bengalfox", secondary: QuotaWindow(usedPercent: 3, windowDurationMins: 10080, resetsAt: now.addingTimeInterval(345600)))
            ], accountID: "fixture")
        }
        model.dashboardLoading = false
        model.dashboard = DashboardSnapshot(sessions: [DashboardSession(id: "fixture", status: .idle, startedAt: now, lastObservedAt: now)], usage: [
            UsageRecord(id: "astra", sessionID: "fixture", modelID: "gpt-6-astra", occurredAt: now, inputTokens: 1_000_000, outputTokens: 100_000, cachedInputTokens: 800_000, totalTokens: 1_100_000, scope: .delta, attribution: .observedDelta),
            UsageRecord(id: "spark", sessionID: "fixture", modelID: "gpt-5.3-codex-spark", occurredAt: now, inputTokens: 250_000, outputTokens: 20_000, cachedInputTokens: 100_000, totalTokens: 270_000, scope: .delta, attribution: .observedDelta)
        ])
        precondition(DashboardQuery(snapshot: model.dashboard, days: 7).tokenSummary.exactRecords.count == 2)
        let populatedQuota = model.quota
        let populatedDaily = model.accountUsageDaily
        for state in ["populated", "four-windows", "empty"] {
            model.quota = populatedQuota
            model.accountUsageDaily = populatedDaily
            if state == "empty" {
                model.quota = nil
                model.accountUsageDaily = []
            } else if state == "four-windows", let quota = populatedQuota {
                model.quota = QuotaSnapshot(observedAt: now, buckets: [
                    QuotaBucket(id: "codex", primary: quota.buckets[0].primary,
                                secondary: QuotaWindow(usedPercent: 12.5, windowDurationMins: 300, resetsAt: now.addingTimeInterval(14400))),
                    quota.buckets[1]
                ], accountID: "fixture")
            }
        for scheme in [ColorScheme.light, .dark] {
          for size in [CGSize(width: 880, height: 620), CGSize(width: 960, height: 740)] {
            let host = NSHostingView(rootView: DashboardView(model: model).preferredColorScheme(scheme))
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [], backing: .buffered, defer: false)
            window.contentView = host
            window.display(); host.layoutSubtreeIfNeeded()
            let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: image)
            try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/build-spirit-dashboard-\(state)-\(scheme)-\(Int(size.width)).png"))
            precondition(host.bounds.size == size)
            window.contentView = nil
          }
        }
        }
        print("PASS: populated, four-window and empty dashboard render at two sizes in both appearances")
    }
}
