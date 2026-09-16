import SwiftUI
import SpiritCore

struct DashboardView: View {
    @ObservedObject var model: CompanionModel
    @State private var days = 7
    @State private var tab = 0
    var openSettings: () -> Void = {}
    private var query: DashboardQuery { DashboardQuery(snapshot: model.dashboard.filtered(for: model.selectedProvider), days: days) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                PixelText("빌드정령", size: 20)
                HStack(spacing: 2) {
                    ForEach(SpiritProvider.allCases, id: \.self) { provider in
                        Button(provider.displayName) { model.selectedProvider = provider }
                            .buttonStyle(DashboardButtonStyle(selected: model.selectedProvider == provider))
                            .accessibilityAddTraits(model.selectedProvider == provider ? .isSelected : [])
                    }
                }.accessibilityLabel("제공자")
                Spacer(minLength: 8)
                HStack(spacing: 2) {
                    ForEach(Array(["사용량", "도구 활용"].enumerated()), id: \.offset) { index, title in
                        Button(title) { tab = index }
                            .buttonStyle(DashboardButtonStyle(selected: tab == index))
                            .accessibilityAddTraits(tab == index ? .isSelected : [])
                    }
                }
                Button("설정", action: openSettings)
            }.padding(.horizontal, 18).padding(.vertical, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if tab == 0 {
                        if model.selectedProvider == .codex {
                            QuotaView(model: model)
                            accountActivity.frame(maxWidth: .infinity)
                        } else {
                            providerActivity
                        }
                    } else {
                        HStack { DashboardSectionTitle(title: "도구 활용"); Spacer(); periodPicker }
                        toolsPanel
                    }
                    if let error = model.dashboardError { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
                }.padding(18).frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }
        }.background(DashboardTheme.canvas).frame(minWidth: 880, minHeight: 620).buttonStyle(DashboardButtonStyle())
    }

    private var providerActivity: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                DashboardSectionTitle(title: model.selectedProvider.displayName + " 활동")
                Spacer()
                periodPicker
            }
            Text(model.providerStatus(for: model.selectedProvider))
                .font(.system(size: 13))
            HStack(spacing: 28) {
                activityCount("관측 세션", count: query.sessions.count)
                activityCount("작업 중", count: query.workingCount)
                activityCount("확인 필요", count: query.attentionCount)
            }
            Divider()
            Text("계정 한도·토큰 사용량 조회 미지원").font(.system(size: 14, weight: .medium))
            Text("수신한 작업 상태와 도구 이벤트를 표시합니다. 계정 잔여량과 비용은 제공하지 않습니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if query.events.isEmpty {
                Text("관측 기록이 없습니다. 설정에서 CLI 연결을 확인하세요.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.dashboardPanel()
    }

    private func activityCount(_ label: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            PixelText("\(count)", size: 32)
        }
    }

    private var periodPicker: some View {
        HStack(spacing: 2) {
            ForEach([1, 7, 30], id: \.self) { value in
                Button(value == 1 ? "오늘" : "\(value)일") { days = value }
                    .buttonStyle(DashboardButtonStyle(selected: days == value))
                    .accessibilityAddTraits(days == value ? .isSelected : [])
            }
        }.accessibilityLabel("집계 기간")
    }

    private var accountActivity: some View {
        VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                DashboardSectionTitle(title: "사용 기록", note: "최근 26주")
                AccountTokenHeatmap(buckets: model.accountUsageDaily)
            }.frame(maxWidth: .infinity)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 138)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    DashboardSectionTitle(title: "일평균")
                    Spacer(minLength: 4)
                    periodPicker
                }
                HStack(alignment: .center, spacing: 6) {
                    PixelText(accountAverage.map { compact($0) } ?? "—", size: 32)
                    Text("토큰").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Text(accountAverage == nil ? "기록 대기" : "\(accountPeriod.count)일 기록 기준")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .help("선택한 \(days)일 중 기록이 제공된 날짜 수를 기준으로 계산합니다.")
                if let total = model.accountUsage?.lifetimeTokens {
                    Text("누적 \(compact(Double(total))) 토큰")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        if let error = model.accountUsageError {
            Text(error).font(.system(size: 11)).foregroundStyle(.red)
        }
        }.dashboardPanel()
    }

    private var accountPeriod: [CodexDailyUsageBucket] {
        let calendar = Calendar(identifier: .gregorian), today = Calendar(identifier: .gregorian).startOfDay(for: Date())
        let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: today)!
        let formatter: DateFormatter = {
            let value = DateFormatter(); value.calendar = calendar; value.locale = Locale(identifier: "en_US_POSIX"); value.dateFormat = "yyyy-MM-dd"
            return value
        }()
        let low = formatter.string(from: cutoff), high = formatter.string(from: today)
        return model.accountUsageDaily.filter { $0.startDate >= low && $0.startDate <= high }
    }
    private var accountAverage: Double? {
        guard !accountPeriod.isEmpty else { return nil }
        return accountPeriod.reduce(0.0) { $0 + Double($1.tokens) } / Double(accountPeriod.count)
    }

    private func compact(_ value: Double) -> String { value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US"))) }
    private var toolsPanel: some View {
        let events = query.events.filter { $0.kind == .toolFinished }, mcp = query.events.filter { $0.kind == .toolFinished && $0.payload.toolCategory == "mcp" }
        return VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    DashboardSectionTitle(title: "MCP 도구 완료"); PixelText("\(mcp.count)회", size: 32)
                    Text("수신한 MCP 완료 이벤트 수입니다. 서버·도구별 이름과 결과는 아직 관측하지 않습니다.").font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).dashboardPanel()
                VStack(alignment: .leading, spacing: 12) {
                    DashboardSectionTitle(title: "Skills 활용"); Text("실행 관측 미지원").font(DashboardTheme.pixel(20))
                    Text("현재 훅은 스킬 실행 정보를 제공하지 않습니다.").font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).dashboardPanel()
            }
            VStack(alignment: .leading, spacing: 16) {
                DashboardSectionTitle(title: "도구 범주별 관측")
                ForEach(["mcp", "shell", "fileEdit", "agent", "other"], id: \.self) { category in
                    HStack { Text(category).font(.system(size: 13, design: .monospaced)); Spacer(); Text("\(events.filter { $0.payload.toolCategory == category }.count)회").monospacedDigit() }
                }
                Text("앱이 실행 중에 수신한 완료 이벤트만 집계합니다.").font(.system(size: 12)).foregroundStyle(.secondary)
            }.dashboardPanel()
        }
    }
}

private struct AccountTokenHeatmap: View {
    let buckets: [CodexDailyUsageBucket]
    var body: some View {
        let calendar = Calendar(identifier: .gregorian), today = Calendar(identifier: .gregorian).startOfDay(for: Date())
        let formatter: DateFormatter = {
            let value = DateFormatter(); value.calendar = calendar; value.locale = Locale(identifier: "en_US_POSIX"); value.dateFormat = "yyyy-MM-dd"
            return value
        }()
        let byDate = Dictionary(buckets.map { ($0.startDate, $0.tokens) }, uniquingKeysWith: { _, new in new })
        let peak = Double(buckets.map(\.tokens).max() ?? 1)
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let cellSize = max(1, (geometry.size.width - 50) / 26)
                HStack(alignment: .top, spacing: 2) {
                    ForEach(0..<26, id: \.self) { week in
                        VStack(spacing: 2) {
                            ForEach(0..<7, id: \.self) { day in
                                let date = calendar.date(byAdding: .day, value: week * 7 + day - 181, to: today)!, key = formatter.string(from: date)
                                let tokens = byDate[key]
                                cell(key: key, tokens: tokens, peak: peak, side: cellSize)
                            }
                        }
                    }
                }
            }.aspectRatio(26.0 / 7.0, contentMode: .fit)
            HStack(spacing: 5) {
                Text("적음").font(.system(size: 10)).foregroundStyle(.secondary)
                ForEach([0.1, 0.35, 0.6, 1.0], id: \.self) { alpha in Rectangle().fill(DashboardTheme.accent.opacity(alpha)).frame(width: 10, height: 10) }
                Text("많음").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text("빈 칸: 기록 미제공").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
    private func cell(key: String, tokens: Int?, peak: Double, side: CGFloat) -> some View {
        let alpha: Double = tokens.map { $0 == 0 ? 0.1 : 0.25 + 0.75 * sqrt(Double($0) / max(1, peak)) } ?? 0
        let description = key + " " + (tokens.map { $0.formatted() + " 토큰" } ?? "기록 미제공")
        return Rectangle().fill(DashboardTheme.accent.opacity(alpha)).frame(width: side, height: side)
            .overlay(Rectangle().stroke(Color.primary.opacity(tokens == nil ? 0.12 : 0.04), lineWidth: 1))
            .help(description).accessibilityLabel(description)
    }
}
