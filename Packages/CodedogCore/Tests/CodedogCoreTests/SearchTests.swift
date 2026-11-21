import Foundation
import Testing
@testable import CodedogCore

@Suite struct SearchTests {
    struct P { var id: String; var doc: SearchDocument }
    func p(_ id: String, _ name: String, deps: [String] = [], readme: String? = nil, categories: [String] = [], path: String = "/projects/example") -> P {
        P(id: id, doc: SearchDocument(name: name, categories: categories, path: path, dependencies: deps, readme: readme))
    }
    func ids(_ items: [P], _ q: String) -> [String] { ProjectSearch.search(items, query: q, document: \.doc).map(\.item.id) }

    // 移植自 tests/search.test.mjs
    @Test func readmeAndDependencyMatchesAreRankedAndExplained() {
        let items = [
            p("readme", "toolbox", readme: "支持图片压缩和格式转换"),
            p("dependency", "worker", deps: ["sharp"]),
            p("name", "sharp-images"),
        ]
        let readme = ProjectSearch.search(items, query: "图片压缩", document: \.doc)
        #expect(readme.map(\.item.id) == ["readme"])
        #expect(readme[0].match.reasons[0].hasPrefix("README："))
        #expect(readme[0].match.reasons[0].contains("图片压缩"))

        let sharp = ProjectSearch.search(items, query: "SHARP", document: \.doc)
        #expect(sharp.map(\.item.id) == ["name", "dependency"])
        #expect(sharp[1].match.reasons[0] == "依赖：sharp")
    }

    // 移植自 tests/search.test.mjs
    @Test func emptyQueryPreservesOrder() {
        #expect(ids([p("second", "Zulu"), p("first", "Alpha")], "") == ["second", "first"])
    }

    @Test func fuzzyNameMatch() {
        #expect(ids([p("a", "codedog"), p("b", "other")], "cdg") == ["a"])
    }

    @Test func everyTermMustMatch() {
        let items = [p("a", "lottie-web", categories: ["公司项目"]), p("b", "lottie-player")]
        #expect(ids(items, "lottie 公司") == ["a"])
    }

    @Test func fullWidthIsNormalized() {
        #expect(ids([p("a", "ABC")], "ａｂｃ") == ["a"])
    }

    @Test func worstTermRankWins() {
        // a：两个词都命中名称（rank 0）；b：一个命中名称、一个命中依赖（rank 2）
        let items = [p("b", "api", deps: ["redis"]), p("a", "api-redis")]
        #expect(ids(items, "api redis") == ["a", "b"])
    }

    @Test func comparatorBreaksTies() {
        let items = [p("z", "zeta-tool"), p("a", "alpha-tool")]
        let r = ProjectSearch.search(items, query: "tool", document: \.doc) { $0.doc.name < $1.doc.name }
        #expect(r.map(\.item.id) == ["a", "z"])
    }

    @Test func readmeSnippetWindow() {
        let text = String(repeating: "前", count: 40) + "目标词" + String(repeating: "后", count: 80)
        let s = ProjectSearch.readmeSnippet(text, terms: ["目标词"])
        #expect(s.hasPrefix("…") && s.hasSuffix("…"))
        #expect(s.contains("目标词"))
        #expect(s.count == 24 + 3 + 46 + 2)
    }

    @Test func readmeSnippetLocatesHitAfterNormalizationChangesLength() {
        // "ﬁ"（连字）规范化为 "fi"，长度变化不能影响定位
        let text = String(repeating: "ﬁ", count: 60) + "飞书" + String(repeating: "x", count: 60)
        let s = ProjectSearch.readmeSnippet(text, terms: ["飞书"])
        #expect(s.hasPrefix("…ﬁ"))
        #expect(s.contains("飞书"))
    }

    @Test func resolvePrefersExactName() {
        let items = [p("a", "web"), p("b", "web-admin")]
        #expect(ProjectSearch.resolve(items, query: "WEB", document: \.doc).item?.id == "a")
        #expect(ProjectSearch.resolve(items, query: "admin", document: \.doc).item?.id == "b")
        let ambiguous = ProjectSearch.resolve(items, query: "we", document: \.doc)
        #expect(ambiguous.item == nil && ambiguous.candidates.count == 2)
    }

    @Test func frecencyDecays() {
        var m = ProjectMeta()
        m.openCount = 4
        m.lastOpened = Date(timeIntervalSinceNow: -7 * 86_400)
        let item = LibraryItem(project: DiscoveredProject(path: "/x", name: "x"), meta: m, categoryNames: [])
        #expect(abs(item.frecency() - 2) < 0.01)
    }
}
