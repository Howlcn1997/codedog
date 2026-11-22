import Foundation

/// 参与搜索的文本字段（与 UI、存储解耦）。
public struct SearchDocument: Sendable {
    public var name: String
    public var categories: [String] = []
    public var description: String?
    public var notes: String?
    public var path: String
    public var remote: String?
    public var stacks: [String] = []
    public var kind: String?
    public var dependencies: [String] = []
    public var readme: String?

    public init(name: String, categories: [String] = [], description: String? = nil, notes: String? = nil, path: String, remote: String? = nil, stacks: [String] = [], kind: String? = nil, dependencies: [String] = [], readme: String? = nil) {
        self.name = name
        self.categories = categories
        self.description = description
        self.notes = notes
        self.path = path
        self.remote = remote
        self.stacks = stacks
        self.kind = kind
        self.dependencies = dependencies
        self.readme = readme
    }
}

public struct SearchMatch: Sendable, Hashable {
    /// 0 = 名称/分类，1 = 描述/备注/路径/远程/技术栈/类型，2 = 依赖/README。越小越靠前。
    public var rank: Int
    /// 最多两条命中原因，例如 "依赖：sharp"、"README：…图片压缩…"。
    public var reasons: [String]

    public init(rank: Int, reasons: [String]) {
        self.rank = rank
        self.reasons = reasons
    }

    public static let none = SearchMatch(rank: 0, reasons: [])
}

/// 项目搜索：NFKC 规范化、多关键词都要命中、字段分级、名称支持子序列模糊匹配。
/// 移植自旧版 `shared/project-search.mjs`。
public enum ProjectSearch {
    public static func normalize(_ s: String) -> String {
        s.precomposedStringWithCompatibilityMapping.lowercased()
    }

    static func terms(_ query: String) -> [String] {
        normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// 子序列匹配：`cdg` 命中 `codedog`。
    static func fuzzy(_ value: String, _ term: String) -> Bool {
        var it = term.makeIterator()
        var next = it.next()
        for ch in normalize(value) where ch == next {
            next = it.next()
            if next == nil { return true }
        }
        return next == nil
    }

    private struct Field {
        var label: String
        var rank: Int
        var values: [String]
        var fuzzy = false
        var isReadme = false

        func hits(_ term: String) -> Bool {
            values.contains { ProjectSearch.normalize($0).contains(term) || (fuzzy && ProjectSearch.fuzzy($0, term)) }
        }
    }

    private static func fields(_ d: SearchDocument) -> [Field] {
        [
            Field(label: String(localized: "名称"), rank: 0, values: [d.name], fuzzy: true),
            Field(label: String(localized: "分类"), rank: 0, values: d.categories),
            Field(label: String(localized: "描述"), rank: 1, values: [d.description].compactMap { $0 }),
            Field(label: String(localized: "备注"), rank: 1, values: [d.notes].compactMap { $0 }),
            Field(label: String(localized: "路径"), rank: 1, values: [d.path]),
            Field(label: String(localized: "远程地址"), rank: 1, values: [d.remote].compactMap { $0 }),
            Field(label: String(localized: "技术栈"), rank: 1, values: d.stacks),
            Field(label: String(localized: "类型"), rank: 1, values: [d.kind].compactMap { $0 }),
            Field(label: String(localized: "依赖"), rank: 2, values: d.dependencies),
            Field(label: "README", rank: 2, values: [d.readme].compactMap { $0 }, isReadme: true),
        ].map { var f = $0; f.values = f.values.filter { !$0.isEmpty }; return f }
    }

    /// 空查询返回 rank 0、无原因；不匹配返回 nil。
    public static func match(_ doc: SearchDocument, query: String) -> SearchMatch? {
        let terms = terms(query)
        guard !terms.isEmpty else { return SearchMatch(rank: 0, reasons: []) }
        let fields = fields(doc)

        var worst = 0
        for term in terms {
            guard let best = fields.filter({ $0.hits(term) }).map(\.rank).min() else { return nil }
            worst = max(worst, best)
        }

        let matched = fields.filter { f in terms.contains { f.hits($0) } }
        let reasons = matched.prefix(2).map { f -> String in
            if f.isReadme { return String(localized: "README：\(readmeSnippet(f.values[0], terms: terms))") }
            let value = f.values.first { v in terms.contains { normalize(v).contains($0) || (f.fuzzy && fuzzy(v, $0)) } } ?? f.values[0]
            return String(localized: "\(f.label)：\(value)")
        }
        return SearchMatch(rank: worst, reasons: reasons)
    }

    /// 截取命中位置前约 24 字、后约 46 字。逐字符规范化并记录映射，保证定位准确。
    static func readmeSnippet(_ text: String, terms: [String]) -> String {
        let chars = Array(text.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        var normalized: [Character] = []
        var origin: [Int] = []  // normalized 下标 → chars 下标
        for (i, c) in chars.enumerated() {
            for n in normalize(String(c)) {
                normalized.append(n)
                origin.append(i)
            }
        }
        let positions = terms.compactMap { term -> Int? in
            let t = Array(term)
            guard !t.isEmpty, t.count <= normalized.count else { return nil }
            return (0...(normalized.count - t.count)).first { normalized[$0..<($0 + t.count)].elementsEqual(t) }
        }
        let hit = positions.min().map { origin[$0] } ?? 0
        let longest = max(terms.map(\.count).max() ?? 1, 1)
        let start = max(0, hit - 24)
        let end = min(chars.count, hit + longest + 46)
        return (start > 0 ? "…" : "") + String(chars[start..<end]) + (end < chars.count ? "…" : "")
    }

    /// 搜索并排序：有查询时先按 rank，再按调用方比较器（保持稳定）。
    public static func search<T>(_ items: [T], query: String, document: (T) -> SearchDocument, by areInIncreasingOrder: (T, T) -> Bool = { _, _ in false }) -> [(item: T, match: SearchMatch)] {
        let hasQuery = !terms(query).isEmpty
        let matched = items.enumerated().compactMap { i, item in match(document(item), query: query).map { (i, item, $0) } }
        return matched.sorted { a, b in
            if hasQuery, a.2.rank != b.2.rank { return a.2.rank < b.2.rank }
            if areInIncreasingOrder(a.1, b.1) { return true }
            if areInIncreasingOrder(b.1, a.1) { return false }
            return a.0 < b.0
        }.map { ($0.1, $0.2) }
    }

    /// CLI 用：名称精确匹配优先，其次搜索结果恰好唯一。
    public static func resolve<T>(_ items: [T], query: String, document: (T) -> SearchDocument, by order: (T, T) -> Bool = { _, _ in false }) -> (item: T?, candidates: [T]) {
        let needle = normalize(query).trimmingCharacters(in: .whitespaces)
        let exact = items.filter { normalize(document($0).name) == needle }
        if exact.count == 1 { return (exact[0], []) }
        if exact.count > 1 { return (nil, exact) }
        let results = search(items, query: query, document: document, by: order).map(\.item)
        return results.count == 1 ? (results[0], []) : (nil, results)
    }
}
