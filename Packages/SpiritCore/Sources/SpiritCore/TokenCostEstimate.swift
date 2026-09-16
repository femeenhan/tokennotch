import Foundation

/// Standard API price comparison, never a subscription bill or quota estimate.
/// Prices checked 2026-09-16 against the official Astra and Sol model pages.
/// Fast/long-context premiums, tools, and unreported cache writes are not included.
public struct TokenCostEstimate: Sendable, Equatable {
    public let inputUSD: Double
    public let cachedInputUSD: Double
    public let outputUSD: Double
    public let pricedTokens: Int
    public let unpricedTokens: Int
    public var totalUSD: Double { inputUSD + cachedInputUSD + outputUSD }
    public var isPartial: Bool { unpricedTokens > 0 }

    public init(records: [UsageRecord]) {
        var input = 0.0, cached = 0.0, output = 0.0
        var priced = 0, unpriced = 0
        for record in records where record.scope == .delta && record.attribution == .observedDelta {
            guard let rates = Self.rates(model: record.modelID), let cache = record.cachedInputTokens,
                  cache >= 0, cache <= record.inputTokens, record.inputTokens >= 0, record.outputTokens >= 0 else {
                unpriced = Self.addCount(unpriced, max(0, record.totalTokens))
                continue
            }
            input += Double(record.inputTokens - cache) * rates.input / 1_000_000
            cached += Double(cache) * rates.cache / 1_000_000
            output += Double(record.outputTokens) * rates.output / 1_000_000
            priced = Self.addCount(priced, max(0, record.totalTokens))
        }
        inputUSD = input; cachedInputUSD = cached; outputUSD = output
        pricedTokens = priced; unpricedTokens = unpriced
    }

    public static func hasPrice(model: String?) -> Bool { rates(model: model) != nil }
    private static func addCount(_ left: Int, _ right: Int) -> Int {
        let sum = left.addingReportingOverflow(right)
        return sum.overflow ? Int.max : sum.partialValue
    }
    private static func rates(model: String?) -> (input: Double, cache: Double, output: Double)? {
        switch model {
        case "gpt-6-astra": return (10, 1, 50)
        case "gpt-5.6-sol", "gpt-5.6": return (4, 0.4, 20)
        default: return nil
        }
    }
}
