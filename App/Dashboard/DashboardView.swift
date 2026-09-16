import SwiftUI
import SpiritCore

struct DashboardView: View {
    @ObservedObject var model: CompanionModel
    @State private var days = 7
    @State private var tab = 0
    @State private var showConsumptionDetails = false
    var openSettings: () -> Void = {}
    private var query: DashboardQuery { DashboardQuery(snapshot: model.dashboard, days: days) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                PixelText("빌드정령")
                Rectangle().fill(DashboardTheme.accent).frame(width: 3, height: 24)
                ForEach(Array(["사용량", "도구 활용"].enumerated()), id: \.offset) { index, title in
                    Button { tab = index } label: { Text(title).foregroundStyle(tab == index ? DashboardTheme.accent : Color.primary) }
                }
                Spacer()
                Button("설정", action: openSettings)
            }.padding(.horizontal, 18).padding(.vertical, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if tab == 0 {
                        QuotaView(model: model)
                        HStack(alignment: .top, spacing: 12) {
                            accountActivity.frame(maxWidth: .infinity)
                            tokenConsumption.frame(maxWidth: .infinity)
                        }
                    } else {
                        HStack { PixelText("도구 활용", size: 28); Spacer(); periodPicker }
                        toolsPanel
                    }
                    if let error = model.dashboardError { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
                }.padding(18).frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }
        }.background(DashboardTheme.canvas).frame(minWidth: 880, minHeight: 620).buttonStyle(PixelButtonStyle(fontSize: 12, horizontalPadding: 10, verticalPadding: 6))
    }

    private var periodPicker: some View {
        Picker("집계 기간", selection: $days) { Text("오늘").tag(1); Text("7일").tag(7); Text("30일").tag(30) }
            .pickerStyle(.segmented).labelsHidden().frame(width: 150)
    }

    private var accountActivity: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { PixelText("사용량 히트맵", size: 18); Text("26주").font(DashboardTheme.pixel(11)).foregroundStyle(.secondary); Spacer(); periodPicker }
            AccountTokenHeatmap(buckets: model.accountUsageDaily)
            HStack {
                    Text("일평균").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(accountAverage.map { compact($0) + " 토큰 / 일" } ?? "기록 대기")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                    Spacer()
                    Text("\(accountPeriod.count)일 기록 기준").font(.system(size: 10)).foregroundStyle(.secondary)
                        .help("선택한 \(days)일 중 기록이 제공된 날짜 수를 기준으로 계산합니다.")
            }
            HStack {
                Text("빈 칸: 기록 미제공").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                if let total = model.accountUsage?.lifetimeTokens { Text("누적 \(compact(Double(total))) 토큰").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            if let error = model.accountUsageError { Text(error).font(.system(size: 12)).foregroundStyle(.secondary) }
        }.pixelPanel()
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

    private var tokenConsumption: some View {
        let summary = query.tokenSummary
        let records = summary.exactRecords
        let input = records.reduce(0.0) { $0 + Double($1.inputTokens) }, output = records.reduce(0.0) { $0 + Double($1.outputTokens) }
        let cacheKnown = !records.isEmpty && records.allSatisfy { $0.cachedInputTokens != nil }
        let cache = records.reduce(0.0) { $0 + Double($1.cachedInputTokens ?? 0) }
        let estimate = TokenCostEstimate(records: records)
        let groups = Dictionary(grouping: records, by: { $0.modelID ?? "모델 미분류" }).sorted { $0.key < $1.key }
        return VStack(alignment: .leading, spacing: 8) {
            HStack { PixelText("소비 내역", size: 18); Spacer(); Text("로그 / \(days)일").font(.system(size: 10)).foregroundStyle(.secondary) }
            if records.isEmpty {
                Text("모델별 소비를 보려면 로그를 연결하세요.").font(.system(size: 12))
                Text("한도와 히트맵은 자동으로 조회됩니다.").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                HStack {
                    PixelText(compact(input + output) + " 토큰", size: 26)
                    Spacer()
                    Text(estimate.pricedTokens > 0 ? "≈ " + dollars(estimate.totalUSD) : "환산 미제공").font(DashboardTheme.pixel(16))
                }
                Text("\(estimate.isPartial ? "부분 " : "")API 환산 참고액").font(.system(size: 10)).foregroundStyle(.secondary)
                DisclosureGroup("입출력·모델별 상세", isExpanded: $showConsumptionDetails) {
                VStack(alignment: .leading, spacing: 10) {
                TokenStackedBar(values: cacheKnown ? [input - cache, cache, output] : [input, 0, output]).frame(height: 18)
                HStack(spacing: 22) {
                    consumptionLabel("입력", value: cacheKnown ? input - cache : input, color: DashboardTheme.input)
                    consumptionLabel("캐시 읽기", value: cacheKnown ? cache : nil, color: DashboardTheme.cache)
                    consumptionLabel("출력", value: output, color: DashboardTheme.output)
                }
                Text("캐시 읽기는 입력에 포함되고 추론은 출력에 포함됩니다. 캐시 쓰기는 미수집입니다.").font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach(groups, id: \.key) { name, values in
                    let total = values.reduce(0.0) { $0 + Double($1.totalTokens) }, cost = TokenCostEstimate(records: values)
                    HStack(spacing: 14) {
                        PixelText(modelLabel(name), size: 16).frame(width: 170, alignment: .leading)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.primary.opacity(0.08))
                                Rectangle().fill(DashboardTheme.accent).frame(width: geometry.size.width * total / max(1, input + output))
                            }
                        }.frame(height: 12)
                        Text(compact(total)).font(DashboardTheme.pixel(13)).frame(width: 65, alignment: .trailing)
                        Text(cost.pricedTokens > 0 ? "≈ " + dollars(cost.totalUSD) : "환산 미제공").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 100, alignment: .trailing)
                    }.padding(.vertical, 8)
                }
                Divider()
                HStack {
                    PixelText("API 환산 참고액", size: 18); Spacer()
                    PixelText(estimate.pricedTokens > 0 ? "≈ " + dollars(estimate.totalUSD) : "계산 가능한 기록 없음", size: 28)
                }
                if estimate.pricedTokens > 0 {
                    TokenStackedBar(values: [estimate.inputUSD, estimate.cachedInputUSD, estimate.outputUSD]).frame(height: 12)
                    Text("입력 \(dollars(estimate.inputUSD))   캐시 읽기 \(dollars(estimate.cachedInputUSD))   출력 \(dollars(estimate.outputUSD))").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    let observedDays = Set(records.map { Calendar.current.startOfDay(for: $0.occurredAt) }).count
                    Text("로그 기록이 있는 \(observedDays)일의 일평균 환산 ≈ \(dollars(estimate.totalUSD / Double(max(1, observedDays)))) / 일")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                }
                Text("\(estimate.isPartial ? "단가 확인 모델만 합산 · " : "")Standard 기본 단가 기준입니다. 구독 결제액·한도 소모량과 다르며 캐시 쓰기, 장문·Fast 요율, 도구 비용은 반영하지 않습니다.").font(.system(size: 11)).foregroundStyle(.secondary)
                HStack {
                    Text("단가 확인 2026-09-16").foregroundStyle(.secondary)
                    Link("Astra 단가", destination: URL(string: "https://developers.openai.com/api/docs/models/gpt-6-astra")!)
                    Link("Sol 단가", destination: URL(string: "https://developers.openai.com/api/docs/models/gpt-5.6-sol")!)
                }.font(.system(size: 11))
                }
                }
            }
            if summary.excludedRecordCount > 0 || summary.cumulativeOnlySessionCount > 0 {
                Text("날짜·모델을 확정할 수 없는 누적값과 관측 누락 구간은 상세 합계에서 제외합니다.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button(model.selectedUsageFilename == nil ? "로그 연결…" : "다른 로그…") { model.selectUsageLog() }
                if model.selectedUsageFilename != nil { Button("수집 중지") { model.stopUsageCollection() } }
                Spacer(); Text(model.usageStatus).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.pixelPanel()
    }
    private func consumptionLabel(_ title: String, value: Double?, color: Color) -> some View {
        HStack(spacing: 7) { Rectangle().fill(color).frame(width: 8, height: 8); Text(title + " " + (value.map(compact) ?? "미수집")).font(.system(size: 12)).monospacedDigit() }
    }
    private func compact(_ value: Double) -> String { value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US"))) }
    private func dollars(_ value: Double) -> String { String(format: "$%.2f", value) }
    private func modelLabel(_ name: String) -> String {
        switch name { case "gpt-6-astra": "Astra"; case "gpt-5.6-sol", "gpt-5.6": "Sol"; case "gpt-5.3-codex-spark": "Spark"; default: name }
    }
    private var toolsPanel: some View {
        let events = query.events.filter { $0.kind == .toolFinished }, mcp = query.events.filter { $0.kind == .toolFinished && $0.payload.toolCategory == "mcp" }
        return VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    PixelText("MCP 도구 완료"); PixelText("\(mcp.count)회", size: 48)
                    Text("수신한 MCP 완료 이벤트 수입니다. 서버·도구별 이름과 결과는 아직 관측하지 않습니다.").font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).pixelPanel()
                VStack(alignment: .leading, spacing: 12) {
                    PixelText("Skills 활용"); Text("실행 관측 미지원").font(DashboardTheme.pixel(20))
                    Text("현재 훅은 스킬 실행 정보를 제공하지 않습니다.").font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).pixelPanel()
            }
            VStack(alignment: .leading, spacing: 16) {
                PixelText("도구 범주별 관측")
                ForEach(["mcp", "shell", "fileEdit", "agent", "other"], id: \.self) { category in
                    HStack { Text(category).font(.system(size: 13, design: .monospaced)); Spacer(); Text("\(events.filter { $0.payload.toolCategory == category }.count)회").monospacedDigit() }
                }
                Text("앱이 실행 중에 수신한 완료 이벤트만 집계합니다.").font(.system(size: 12)).foregroundStyle(.secondary)
            }.pixelPanel()
        }
    }
}

private struct TokenStackedBar: View {
    let values: [Double]
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    Rectangle().fill([DashboardTheme.input, DashboardTheme.cache, DashboardTheme.output][index]).frame(width: geometry.size.width * max(0, value) / max(0.000001, values.reduce(0, +)))
                }
            }
        }.overlay(Rectangle().stroke(Color.primary.opacity(0.5), lineWidth: 1))
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
            HStack(alignment: .top, spacing: 2) {
                ForEach(0..<26, id: \.self) { week in
                    VStack(spacing: 2) {
                        ForEach(0..<7, id: \.self) { day in
                            let date = calendar.date(byAdding: .day, value: week * 7 + day - 181, to: today)!, key = formatter.string(from: date)
                            let tokens = byDate[key]
                            cell(key: key, tokens: tokens, peak: peak)
                        }
                    }
                }
            }
            HStack(spacing: 5) {
                Text("적음").font(.system(size: 10)).foregroundStyle(.secondary)
                ForEach([0.1, 0.35, 0.6, 1.0], id: \.self) { alpha in Rectangle().fill(DashboardTheme.cache.opacity(alpha)).frame(width: 10, height: 10) }
                Text("많음").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
    private func cell(key: String, tokens: Int?, peak: Double) -> some View {
        let alpha: Double = tokens.map { $0 == 0 ? 0.1 : 0.25 + 0.75 * sqrt(Double($0) / max(1, peak)) } ?? 0
        let description = key + " " + (tokens.map { $0.formatted() + " 토큰" } ?? "기록 미제공")
        return Rectangle().fill(DashboardTheme.cache.opacity(alpha)).frame(width: 9, height: 9)
            .overlay(Rectangle().stroke(Color.primary.opacity(tokens == nil ? 0.12 : 0.04), lineWidth: 1))
            .help(description).accessibilityLabel(description)
    }
}
