import SwiftUI
import SpiritCore

struct QuotaView: View {
    @ObservedObject var model: CompanionModel
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        DashboardSectionTitle(title: "남은 사용량")
                        Spacer()
                        observationStatus(now: context.date)
                        Button(model.quotaRefreshing ? "조회 중…" : "새로고침") { model.refreshQuota(force: true) }
                            .disabled(model.quotaRefreshing || !model.quotaMonitoringEnabled)
                    }
                    if let error = model.quotaError { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(quotaItems) { item in
                            quotaMetric(item, now: context.date)
                        }
                    }
                }.dashboardPanel()
                trends(now: context.date)
            }
        }.buttonStyle(DashboardButtonStyle())
    }

    private struct QuotaItem: Identifiable {
        let id: String
        let title: String
        let window: QuotaWindow?
    }

    private var quotaItems: [QuotaItem] {
        let buckets: [(String, QuotaBucket?)] = [
            ("Astra · Sol", model.generalQuotaBucket),
            ("Spark", model.quota?.buckets.first { $0.id == "codex_bengalfox" || $0.name?.localizedCaseInsensitiveContains("spark") == true })
        ]
        return buckets.flatMap { title, bucket -> [QuotaItem] in
            let available = (bucket.map(windows) ?? []).sorted {
                ($0.windowDurationMins ?? 0) > ($1.windowDurationMins ?? 0)
            }
            if available.isEmpty { return [QuotaItem(id: title, title: title, window: nil)] }
            return available.enumerated().map { index, window in
                QuotaItem(id: "\(title)-\(index)", title: title, window: window)
            }
        }
    }

    private func quotaMetric(_ item: QuotaItem, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(item.title).font(.system(size: 12, weight: .semibold))
                if let window = item.window {
                    Text(windowLabel(window)).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }.help(item.title == "Astra · Sol" ? "Astra와 Sol이 함께 사용하는 계정 한도입니다." : "Spark의 별도 사용 한도입니다.")
            PixelText(item.window?.remainingPercent.map { percent($0) } ?? "—", size: 32)
            PixelMeter(remaining: item.window?.remainingPercent).frame(height: 8)
            Text(item.window.map { resetText($0.resetsAt, now: now) } ?? (model.quotaRefreshing ? "조회 중" : "미제공"))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                .help(item.window?.resetsAt.map { "다음 리셋 " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "리셋 시각 미제공")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func observationStatus(now: Date) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(Color.secondary).frame(width: 6, height: 6)
            if !model.quotaMonitoringEnabled {
                Text("자동 조회 중지")
            } else if let date = model.quota?.observedAt {
                Text("\(fresh(now) ? "마지막 확인" : "이전 값") \(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))")
            } else {
                Text(model.quotaRefreshing ? "조회 중" : "확인 대기")
            }
        }.font(.system(size: 11)).foregroundStyle(.secondary)
            .help(model.quotaMonitoringEnabled ? "로그인된 계정의 한도를 약 1분마다 자동 조회합니다." : "자동 조회가 중지되었습니다.")
    }

    private func trends(now: Date) -> some View {
        let matching = model.quotaHistory.last?.accountID == model.quota?.accountID && model.quotaHistory.last?.observedAt == model.quota?.observedAt
        let trend = QuotaTrend(history: matching ? model.quotaHistory : [], bucketID: "codex", now: now)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 18) {
                DashboardSectionTitle(title: "잔여량 추세", note: "최근 60분 · 주간")
                Spacer()
                if fresh(now), model.quotaHistoryError == nil, model.quotaHistory.last?.observedAt == model.quota?.observedAt, let risk = trend.riskMessage {
                    Text("Astra·Sol 소진 예상").font(.system(size: 11, weight: .medium)).foregroundStyle(DashboardTheme.accent)
                        .help(risk)
                }
            }
            QuotaHistoryChart(history: matching ? model.quotaHistory : [])
            if let warning = model.quotaHistoryError { Text(warning).font(.system(size: 12)).foregroundStyle(.secondary) }
        }.dashboardPanel()
    }

    private func windows(_ bucket: QuotaBucket) -> [QuotaWindow] { [bucket.primary, bucket.secondary].compactMap { $0 } }
    private func percent(_ number: Double?) -> String { number.map { $0.formatted(.number.precision(.fractionLength(0...1))) + "%" } ?? "확인 대기" }
    private func windowLabel(_ window: QuotaWindow) -> String {
        switch window.windowDurationMins { case 300: "5시간"; case 1440: "일간"; case 10080: "주간"; case let minutes?: "\(minutes)분"; case nil: "기간 미제공" }
    }
    private func resetText(_ date: Date?, now: Date) -> String {
        guard let date else { return "리셋 시각 미제공" }
        let minutes = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes == 0 { return "리셋 시각 경과" }
        let days = minutes / 1440, hours = minutes % 1440 / 60, rest = minutes % 60
        return "리셋까지 " + (days > 0 ? "\(days)일 " : "") + (hours > 0 ? "\(hours)시간 " : "") + "\(rest)분"
    }
    private func fresh(_ now: Date) -> Bool {
        model.quotaIsFresh(at: now)
    }
}

private struct QuotaHistoryChart: View {
    let history: [QuotaSnapshot]
    private func samples(_ id: String) -> [(Date, Double)] {
        let now = Date()
        let recent = history.filter { $0.observedAt <= now && $0.observedAt >= now.addingTimeInterval(-3600) }
        guard let latest = recent.last, let account = latest.accountID, !account.isEmpty,
              let window = weekly(latest, id: id), let reset = window.resetsAt,
              let remaining = window.remainingPercent else { return [] }
        var suffix: [(Date, Double)] = [(latest.observedAt, remaining)]
        for snapshot in recent.dropLast().reversed() {
            guard snapshot.accountID == account, let value = weekly(snapshot, id: id),
                  let date = value.resetsAt, abs(date.timeIntervalSince(reset)) <= 5,
                  let remaining = value.remainingPercent, let next = suffix.last,
                  snapshot.observedAt < next.0,
                  next.0.timeIntervalSince(snapshot.observedAt) <= 300,
                  remaining >= next.1 else { break }
            suffix.append((snapshot.observedAt, remaining))
        }
        return Array(suffix.reversed())
    }
    private func weekly(_ snapshot: QuotaSnapshot, id: String) -> QuotaWindow? {
        guard let bucket = snapshot.buckets.first(where: { $0.id == id }) else { return nil }
        return [bucket.primary, bucket.secondary].compactMap { $0 }.first { $0.windowDurationMins == 10080 }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 22) {
                smallChart(samples("codex"), title: "Astra · Sol", color: DashboardTheme.accent)
                smallChart(samples("codex_bengalfox"), title: "Spark", color: DashboardTheme.accent)
            }
        }.help("각 그래프는 개별 확대 축입니다. 선의 높이·기울기를 모델 간 절대 사용량으로 비교하지 마세요.")
    }

    private func smallChart(_ samples: [(Date, Double)], title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if samples.count >= 2, let first = samples.first, let last = samples.last, last.0 > first.0 {
                let lower = lowerBound(samples)
                let upper = lower + axisSpan(samples)
                HStack {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 4)
                    Text(first.1 == last.1 ? "변화 없음" : "\(number(first.1 - last.1))%p 감소")
                }.font(.system(size: 11, design: .monospaced))
                HStack(alignment: .top, spacing: 5) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(percent(upper))
                        Spacer(minLength: 0)
                        Text(percent((upper + lower) / 2))
                        Spacer(minLength: 0)
                        Text(percent(lower))
                    }.font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        .frame(width: 42, height: 64)
                    VStack(spacing: 5) {
                        GeometryReader { geometry in
                            ZStack {
                                ForEach([0.0, 0.5, 1.0], id: \.self) { level in
                                    Path { path in
                                        let y = 2 + (geometry.size.height - 4) * level
                                        path.move(to: CGPoint(x: 0, y: y))
                                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                                    }.stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                }
                                trace(samples, lower: lower, upper: upper, size: geometry.size)
                                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineJoin: .miter))
                            }
                        }.frame(height: 64)
                        HStack {
                            Text(first.0, format: .dateTime.hour().minute())
                            Spacer(minLength: 2)
                            Text(last.0, format: .dateTime.hour().minute())
                        }.font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                .help("잔여율 \(percent(lower))-\(percent(upper)) 확대 · 가로축은 관측 시각입니다.")
            } else {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text("관측 대기").font(.system(size: 14, design: .monospaced)).foregroundStyle(.secondary)
                    .help("같은 리셋 구간의 연속 관측이 2회 이상 필요합니다.")
                Spacer(minLength: 0)
            }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
    }

    private func axisSpan(_ samples: [(Date, Double)]) -> Double {
        min(100, max(4, (samples.map(\.1).max() ?? 0) - (samples.map(\.1).min() ?? 0) + 1))
    }
    private func lowerBound(_ samples: [(Date, Double)]) -> Double {
        let midpoint = ((samples.map(\.1).max() ?? 0) + (samples.map(\.1).min() ?? 0)) / 2
        let span = axisSpan(samples)
        return min(max(0, midpoint - span / 2), 100 - span)
    }
    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
    private func percent(_ value: Double) -> String { number(value) + "%" }

    private func trace(_ samples: [(Date, Double)], lower: Double, upper: Double, size: CGSize) -> Path {
        Path { path in
            guard let first = samples.first, let last = samples.last, last.0 > first.0 else { return }
            for (index, sample) in samples.enumerated() {
                let point = CGPoint(x: size.width * sample.0.timeIntervalSince(first.0) / last.0.timeIntervalSince(first.0),
                                    y: 2 + (size.height - 4) * (1 - (sample.1 - lower) / (upper - lower)))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
}

struct PixelMeter: View {
    let remaining: Double?
    var body: some View {
        GeometryReader { geometry in
            let cells = max(1, Int((geometry.size.width + 3) / 11))
            HStack(spacing: 3) {
                ForEach(0..<cells, id: \.self) { index in
                    Rectangle().fill(Double(index) < (remaining ?? 0) / 100 * Double(cells) ? DashboardTheme.accent : Color.primary.opacity(0.08))
                        .frame(width: max(0, (geometry.size.width - CGFloat(cells - 1) * 3) / CGFloat(cells)))
                }
            }
        }.accessibilityLabel("남은 한도 \(remaining.map { String(format: "%.1f", $0) } ?? "미확인") 퍼센트")
    }
}

struct QuotaQuickView: View {
    static let size = CGSize(width: 188, height: 96)
    @ObservedObject var model: CompanionModel
    var provider: SpiritProvider = .codex
    let openDashboard: () -> Void
    var tailOnLeft = true
    var tailY: CGFloat = 48

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let weekly = provider == .codex ? [model.generalQuotaBucket?.primary, model.generalQuotaBucket?.secondary]
                .compactMap { $0 }.first { $0.windowDurationMins == 10080 } : nil
            VStack(alignment: .leading, spacing: 6) {
                if provider == .codex {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("주간 잔여").font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 0)
                        Text(weekly?.remainingPercent.map {
                            $0.formatted(.number.precision(.fractionLength(0...1))) + "%"
                        } ?? "확인 대기")
                        .font(.system(size: weekly?.remainingPercent == nil ? 12 : 19, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    }
                    GeometryReader { geometry in
                        Capsule().fill(Color(nsColor: SpiritSpeechView.ink).opacity(0.1))
                        if let remaining = weekly?.remainingPercent {
                            Capsule().fill(Color(nsColor: SpiritSpeechView.outline))
                                .frame(width: geometry.size.width * min(100, max(0, remaining)) / 100)
                        }
                    }.frame(height: 4)
                        .accessibilityLabel("주간 남은 한도 \(weekly?.remainingPercent.map { String(format: "%.1f%%", $0) } ?? "미확인")")
                } else {
                    Text(provider.displayName).font(.system(size: 12, weight: .semibold))
                    Text(model.providerStatus(for: provider)).font(.system(size: 11)).lineLimit(1)
                        .help(model.providerStatus(for: provider))
                }
                HStack(spacing: 4) {
                    if provider != .codex {
                        Text("조회 미지원").font(.system(size: 10))
                    } else if weekly != nil && !model.quotaIsFresh(at: context.date) {
                        Text("이전 값").font(.system(size: 10))
                    }
                    Spacer(minLength: 0)
                    Button(action: openDashboard) {
                        HStack(spacing: 3) {
                            Text("대시보드")
                            Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                        }.font(.system(size: 11, weight: .medium))
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("대시보드 열기")
                }
            }
            .foregroundStyle(Color(nsColor: SpiritSpeechView.ink))
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
        }.frame(width: Self.size.width, height: Self.size.height)
            .background {
                CompanionBubbleBackground(tailOnLeft: tailOnLeft, tailY: tailY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

/// Reuse the character dialogue's native drawing, including its colors and tail.
private struct CompanionBubbleBackground: NSViewRepresentable {
    var tailOnLeft: Bool
    var tailY: CGFloat
    func makeNSView(context: Context) -> SpiritSpeechView {
        let view = SpiritSpeechView(frame: .zero)
        view.message = ""
        view.setAccessibilityElement(false)
        return view
    }
    func updateNSView(_ view: SpiritSpeechView, context: Context) {
        view.tailOnLeft = tailOnLeft
        view.tailY = tailY
        view.needsDisplay = true
    }
}

@MainActor
final class UsageBubblePanel: NSPanel {
    var dismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { dismiss?() } else { super.keyDown(with: event) }
    }
}
