import Testing
import Foundation
@testable import SpiritCore

@Suite struct TokenCostEstimateTests {
    @Test func cachedInputAndReasoningAreNotDoubleCharged() {
        let record = UsageRecord(id: "delta", sessionID: "s", modelID: "gpt-6-astra", occurredAt: .now,
            inputTokens: 1_000_000, outputTokens: 100_000, cachedInputTokens: 800_000,
            reasoningOutputTokens: 50_000, totalTokens: 1_100_000, scope: .delta, attribution: .observedDelta)
        let estimate = TokenCostEstimate(records: [record])
        #expect(abs(estimate.totalUSD - 7.8) < 0.00001)
        #expect(estimate.pricedTokens == 1_100_000)
    }
    @Test func unknownPriceAndCacheStayUnpricedAndCumulativeIsExcluded() {
        func record(_ id: String, model: String?, cache: Int?, scope: UsageRecord.Scope) -> UsageRecord {
            UsageRecord(id: id, sessionID: "s", modelID: model, occurredAt: .now,
                inputTokens: 100, outputTokens: 10, cachedInputTokens: cache, totalTokens: 110,
                scope: scope, attribution: .observedDelta)
        }
        let estimate = TokenCostEstimate(records: [record("spark", model: "gpt-5.3-codex-spark", cache: 20, scope: .delta),
            record("missing", model: "gpt-6-astra", cache: nil, scope: .delta),
            record("total", model: "gpt-6-astra", cache: 20, scope: .sessionTotal)])
        #expect(estimate.totalUSD == 0)
        #expect(estimate.pricedTokens == 0)
        #expect(estimate.unpricedTokens == 220)
    }
}
