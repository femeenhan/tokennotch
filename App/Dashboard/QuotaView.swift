import SwiftUI
import SpiritCore

struct QuotaView: View {
    @ObservedObject var model: CompanionModel
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        PixelText("남은 사용량", size: 20)
                    }
                    Spacer()
                    Button(model.quotaRefreshing ? "조회 중…" : "새로고침") { model.refreshQuota(force: true) }
                        .disabled(model.quotaRefreshing || !model.quotaMonitoringEnabled)
                }
                observationStatus(now: context.date)
                if let error = model.quotaError { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
                HStack(alignment: .top, spacing: 12) {
                    quotaCard(model.generalQuotaBucket, title: "Astra · Sol", subtitle: "일반 사용 한도", now: context.date)
                    quotaCard(model.quota?.buckets.first { $0.id == "codex_bengalfox" || $0.name?.localizedCaseInsensitiveContains("spark") == true }, title: "Spark", subtitle: "별도 사용 한도", now: context.date)
                }
                trends(now: context.date)
            }
        }.buttonStyle(PixelButtonStyle())
    }

    private func quotaCard(_ bucket: QuotaBucket?, title: String, subtitle: String, now: Date) -> some View {
        let available = bucket.map(windows) ?? []
        let main = available.first { $0.windowDurationMins == 10080 } ?? available.first
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                PixelText(title, size: 20)
                Spacer()
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(main.map(windowLabel) ?? "주간").font(.system(size: 10)).foregroundStyle(.secondary)
                    PixelText(percent(main?.remainingPercent), size: main?.remainingPercent == nil ? 20 : 38)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(main.map { resetText($0.resetsAt, now: now) } ?? "조회 대기").font(DashboardTheme.pixel(11))
                    Text(main?.resetsAt.map { $0.formatted(.dateTime.month().day().hour().minute()) } ?? "리셋 시각 미제공")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            if let main {
                PixelMeter(remaining: main.remainingPercent).frame(height: 8)
            } else {
                Text(model.quotaRefreshing ? "계정 한도 조회 중" : "계정 응답에 한도가 없습니다.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Divider()
            ForEach(Array(available.filter { $0.windowDurationMins != main?.windowDurationMins }.enumerated()), id: \.offset) { _, value in
                HStack {
                    Text(windowLabel(value)).font(.system(size: 11))
                    Spacer()
                    Text(percent(value.remainingPercent)).font(.system(size: 11)).monospacedDigit()
                    Text(resetText(value.resetsAt, now: now)).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                PixelMeter(remaining: value.remainingPercent).frame(height: 4)
                    .help(value.resetsAt.map { "다음 리셋 " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "리셋 시각 미제공")
            }
            if title == "Astra · Sol" { Text("Astra·Sol 공유 한도").font(.system(size: 10)).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, minHeight: 145, alignment: .topLeading).pixelPanel()
    }

    private func observationStatus(now: Date) -> some View {
        HStack(spacing: 7) {
            Rectangle().fill(fresh(now) ? DashboardTheme.accent : Color.secondary).frame(width: 6, height: 6)
            if !model.quotaMonitoringEnabled {
                Text("자동 조회 중지됨").font(.system(size: 12)).foregroundStyle(.secondary)
            } else if let date = model.quota?.observedAt {
                Text("\(fresh(now) ? "자동 갱신" : "이전 관측값") · 마지막 확인 \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else { Text(model.quotaRefreshing ? "로그인된 계정의 한도를 확인하고 있습니다." : "아직 계정 한도를 확인하지 못했습니다.").font(.system(size: 12)).foregroundStyle(.secondary) }
            Spacer()
            if !compact && model.quotaMonitoringEnabled { Text("약 1분마다 조회").font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }

    private func weekly(now: Date) -> some View {
        let window = window(minutes: 10080)
        return VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            HStack { Text("주간 남은 양").font(DashboardTheme.pixel()); Spacer(); Text("계정 전체").font(.system(size: 11)).foregroundStyle(.secondary) }
            PixelText(percent(window?.remainingPercent), size: compact ? 48 : 72)
            if let window {
                PixelMeter(remaining: window.remainingPercent).frame(height: compact ? 10 : 16)
                Text(resetText(window.resetsAt, now: now)).font(DashboardTheme.pixel(compact ? 14 : 18))
                if let date = window.resetsAt {
                    Text("다음 리셋 \(date.formatted(.dateTime.month().day().weekday().hour().minute())) · \(TimeZone.current.abbreviation() ?? TimeZone.current.identifier)")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if window.resetsAt.map({ $0 <= now }) == true { Text("리셋 예정 시각이 지났습니다. 새 조회 결과를 기다려 주세요.").font(.system(size: 12)).foregroundStyle(.secondary) }
            } else {
                Text(model.quota == nil ? "계정 한도를 조회하면 표시됩니다." : "이번 계정 응답에 주간 한도가 없습니다.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).pixelPanel()
    }

    private func shortWindow(minutes: Int, label: String, now: Date) -> some View {
        let value = window(minutes: minutes)
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(label) 남은 양").font(DashboardTheme.pixel(14))
            if let value {
                PixelText(percent(value.remainingPercent), size: 32)
                Text(resetText(value.resetsAt, now: now)).font(.system(size: 12)).foregroundStyle(.secondary)
                if let date = value.resetsAt { Text(date, format: .dateTime.month().day().hour().minute()).font(.system(size: 11)).foregroundStyle(.secondary) }
            } else {
                Text(model.quota == nil ? "조회 대기" : "미제공").font(DashboardTheme.pixel(20))
                Text("\(label) 한도가 별도로\n제공될 때 표시합니다.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).pixelPanel()
    }

    private func trends(now: Date) -> some View {
        let matching = model.quotaHistory.last?.accountID == model.quota?.accountID && model.quotaHistory.last?.observedAt == model.quota?.observedAt
        let trend = QuotaTrend(history: matching ? model.quotaHistory : [], bucketID: "codex", now: now)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 18) {
                PixelText("한도 소모 추세", size: 18)
                Text("최근 60분").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text(trend.todayUsedPercentagePoints.map { String(format: "오늘 관측 −%.1f%%p", $0) } ?? "오늘 관측 대기")
                    .help("오늘 첫 관측부터의 일반 계정 잔여율 감소입니다.")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            QuotaHistoryChart(history: matching ? model.quotaHistory : [])
            if let warning = model.quotaHistoryError { Text(warning).font(.system(size: 12)).foregroundStyle(.secondary) }
            if fresh(now), model.quotaHistoryError == nil, model.quotaHistory.last?.observedAt == model.quota?.observedAt, let risk = trend.riskMessage {
                Text(risk).font(.system(size: 11, weight: .medium)).foregroundStyle(DashboardTheme.accent)
                    .help("복잡한 작업을 마무리한 뒤 Sol 전환이나 추론 강도 조절을 고려하세요.")
            }
        }.pixelPanel()
    }

    private func trendMetric(_ title: String, value: Double?, note: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(value.map { String(format: "%.1f%%p", $0) } ?? "관측 대기").font(.system(size: compact ? 18 : 24, weight: .medium, design: .monospaced))
            Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func windows(_ bucket: QuotaBucket) -> [QuotaWindow] { [bucket.primary, bucket.secondary].compactMap { $0 } }
    private func window(minutes: Int) -> QuotaWindow? { model.generalQuotaBucket.flatMap { windows($0).first { $0.windowDurationMins == minutes } } }
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
                smallChart(samples("codex"), title: "Astra · Sol 공유 한도", color: DashboardTheme.accent)
                smallChart(samples("codex_bengalfox"), title: "Spark 한도", color: DashboardTheme.cache)
            }
        }.help("각 그래프는 개별 확대 축입니다. 선의 높이·기울기를 모델 간 절대 사용량으로 비교하지 마세요.")
    }

    private func smallChart(_ samples: [(Date, Double)], title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
            if samples.count >= 2, let first = samples.first, let last = samples.last, last.0 > first.0 {
                let lower = lowerBound(samples)
                let upper = lower + axisSpan(samples)
                HStack {
                    Text("\(percent(first.1)) → \(percent(last.1))")
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
                    }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
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
                        }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                Text("잔여율 \(percent(lower))-\(percent(upper)) 확대 / 가로축 관측 시각")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            } else {
                Text("관측 대기").font(.system(size: 14, design: .monospaced)).foregroundStyle(.secondary)
                Text("같은 리셋 구간의 연속 관측이 2회 이상 필요합니다.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
            let cells = 28
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
    static let size = CGSize(width: 240, height: 156)
    @ObservedObject var model: CompanionModel
    let openDashboard: () -> Void
    var tailOnLeft = true
    var tailY: CGFloat = 78
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let weekly = [model.generalQuotaBucket?.primary, model.generalQuotaBucket?.secondary]
                .compactMap { $0 }.first { $0.windowDurationMins == 10080 }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("주간 남은 양").font(DashboardTheme.pixel(12))
                    Spacer()
                    if weekly != nil && !model.quotaIsFresh(at: context.date) {
                        Text("이전 값").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                PixelText(weekly?.remainingPercent.map {
                    $0.formatted(.number.precision(.fractionLength(0...1))) + "%"
                } ?? "확인 대기", size: weekly?.remainingPercent == nil ? 24 : 40)
                if let remaining = weekly?.remainingPercent {
                    PixelMeter(remaining: remaining).frame(height: 6)
                }
                Button("대시보드 열기", action: openDashboard)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }.padding(14)
                .padding(.leading, tailOnLeft ? 20 : 0)
                .padding(.trailing, tailOnLeft ? 0 : 20)
        }.frame(width: Self.size.width, height: Self.size.height)
            .background {
                let shape = PixelSpeechBubble(tailOnLeft: tailOnLeft, tailY: tailY)
                shape.fill(Color.primary.opacity(0.18)).offset(x: 2, y: 2)
                shape.fill(Color(nsColor: .windowBackgroundColor))
                shape.stroke(Color.primary.opacity(0.75), style: StrokeStyle(lineWidth: 3, lineJoin: .miter))
            }
            .buttonStyle(PixelButtonStyle(fontSize: 12, horizontalPadding: 8, verticalPadding: 6))
    }
}

/// Integer-aligned, stepped corners and tail. No rounded popover chrome.
struct PixelSpeechBubble: Shape {
    var tailOnLeft: Bool
    var tailY: CGFloat
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let y = min(max(24, (tailY / 6).rounded() * 6), h - 24)
        let points: [CGPoint] = [
            CGPoint(x: 28, y: 2), CGPoint(x: w - 8, y: 2),
            CGPoint(x: w - 8, y: 8), CGPoint(x: w - 2, y: 8),
            CGPoint(x: w - 2, y: h - 8), CGPoint(x: w - 8, y: h - 8),
            CGPoint(x: w - 8, y: h - 2), CGPoint(x: 28, y: h - 2),
            CGPoint(x: 28, y: h - 8), CGPoint(x: 22, y: h - 8),
            CGPoint(x: 22, y: y + 12), CGPoint(x: 16, y: y + 12),
            CGPoint(x: 16, y: y + 6), CGPoint(x: 10, y: y + 6),
            CGPoint(x: 10, y: y), CGPoint(x: 4, y: y),
            CGPoint(x: 4, y: y - 6), CGPoint(x: 10, y: y - 6),
            CGPoint(x: 10, y: y - 12), CGPoint(x: 22, y: y - 12),
            CGPoint(x: 22, y: 8), CGPoint(x: 28, y: 8)
        ]
        var path = Path()
        for (index, point) in points.enumerated() {
            let mapped = CGPoint(x: rect.minX + (tailOnLeft ? point.x : w - point.x), y: rect.minY + point.y)
            if index == 0 { path.move(to: mapped) } else { path.addLine(to: mapped) }
        }
        path.closeSubpath()
        return path
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
