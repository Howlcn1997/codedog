import Foundation
import Testing
@testable import CodedogCore

@Suite struct LanguageStatsTests {
    @Test func tallyGroupsByLanguageAndSkipsNoise() {
        let shares = LanguageStats.tally([
            ("src/a.ts", 300), ("src/b.tsx", 100), ("web/app.js", 200), ("web/app.min.js", 9000),
            ("node_modules/x/index.js", 5000), ("README.md", 800), ("package.json", 400), ("Makefile", 50),
            ("third_party/lib.c", 7000),
        ])
        #expect(shares.map(\.name) == ["TypeScript", "JavaScript", "Makefile"])
        #expect(shares.first?.bytes == 400)
    }

    @Test func headersFollowProjectLanguage() {
        #expect(LanguageStats.tally([("a.m", 10), ("a.h", 5)]).map(\.bytes) == [15])
        #expect(LanguageStats.tally([("a.h", 5)]).map(\.name) == ["C"])
    }

    @Test func parsesLsTree() {
        let text = "100644 blob abc     120\tsrc/a.swift\u{0}160000 commit def       -\tsub\u{0}100644 blob 123 7\tname with space.go\u{0}"
        let files = LanguageStats.parseLsTree(text)
        #expect(files.map(\.0) == ["src/a.swift", "name with space.go"])
        #expect(files.map(\.1) == [120, 7])
    }

    @Test func collectsFromGitRepository() async throws {
        let f = try Fixture()
        try f.file("main.swift", String(repeating: "x", count: 100))
        try f.file("Scripts/run.sh", "echo")
        let env = ["GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"]
        _ = try await ShellRunner.run("git", ["init", "-q", f.root])
        _ = try await ShellRunner.run("git", ["-C", f.root, "add", "."])
        _ = try await ShellRunner.run("git", ["-C", f.root, "commit", "-qm", "init"], environment: env)
        let shares = await LanguageStats.collect(path: f.root, isGit: true)
        #expect(shares.map(\.name) == ["Swift", "Shell"])
        #expect(LanguageStats.tally(LanguageStats.walk(path: f.root)).map(\.name) == ["Swift", "Shell"])
    }
}
