import Foundation

/// 按 Anthropic API 公开价格估算 Claude 模型费用（美元 / 百万 token）。
/// 缓存写入按惯例估算：5 分钟缓存 = 输入价 × 1.25，1 小时缓存 = 输入价 × 2。
/// 非 Claude 模型没有可靠的公开价格，返回 nil，界面显示"—"。
public enum Pricing {
    struct Price { var input: Double; var output: Double; var cacheRead: Double }

    /// 前缀匹配，较具体的放前面。价格表更新于 2026-11。
    static let table: [(prefix: String, price: Price)] = [
        ("claude-fable-5-2", Price(input: 8, output: 40, cacheRead: 0.20)),
        ("claude-mythos-5-2", Price(input: 8, output: 40, cacheRead: 0.20)),
        ("claude-fable-5", Price(input: 10, output: 50, cacheRead: 1.0)),
        ("claude-mythos-5", Price(input: 10, output: 50, cacheRead: 1.0)),
        ("claude-opus-5-5", Price(input: 4, output: 20, cacheRead: 0.20)),
        ("claude-opus-5", Price(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-8", Price(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-7", Price(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-6", Price(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-sonnet-5-5", Price(input: 2, output: 10, cacheRead: 0.10)),
        ("claude-sonnet-5", Price(input: 2, output: 10, cacheRead: 0.20)),
        ("claude-sonnet-4-6", Price(input: 3, output: 15, cacheRead: 0.30)),
        ("claude-haiku-5-5", Price(input: 0.10, output: 0.50, cacheRead: 0.01)),
        ("claude-haiku-4-5", Price(input: 1, output: 5, cacheRead: 0.10)),
    ]

    static func price(for model: String) -> Price? {
        let m = model.lowercased()
        return table.first { m.hasPrefix($0.prefix) }?.price
    }

    public static func cost(model: String, usage u: TokenUsage) -> Double? {
        guard let p = price(for: model) else { return nil }
        let perM = 1_000_000.0
        return (Double(u.input) * p.input
            + Double(u.output) * p.output
            + Double(u.cacheRead) * p.cacheRead
            + Double(u.cacheWrite5m) * p.input * 1.25
            + Double(u.cacheWrite1h) * p.input * 2) / perM
    }

    /// `claude-opus-5-5` → `Opus 5.5`；`claude-sonnet-4-6-20250101` → `Sonnet 4.6`；其他原样返回。
    public static func displayName(_ model: String) -> String {
        guard model.hasPrefix("claude-") else { return model }
        let parts = model.dropFirst(7).split(separator: "-")
        guard let family = parts.first else { return model }
        let version = parts.dropFirst().prefix { $0.count <= 2 && $0.allSatisfy(\.isNumber) }
        let name = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? name : "\(name) \(version.joined(separator: "."))"
    }
}
