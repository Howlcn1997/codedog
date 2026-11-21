import Foundation
import Testing
@testable import CodedogCore

@Suite struct RecentFilesTests {
    @Test func noiseFilter() {
        #expect(RecentFiles.isNoise("package-lock.json"))
        #expect(RecentFiles.isNoise("web/pnpm-lock.yaml"))
        #expect(RecentFiles.isNoise("dist/app.js"))
        #expect(RecentFiles.isNoise("node_modules/x/index.js"))
        #expect(RecentFiles.isNoise(".github/workflows/ci.yml"))
        #expect(RecentFiles.isNoise("assets/logo.png"))
        #expect(RecentFiles.isNoise("vendor.min.js"))
        #expect(RecentFiles.isNoise(".prettierignore"))
        #expect(!RecentFiles.isNoise("App/Views/FolderCard.swift"))
        #expect(!RecentFiles.isNoise("README.md"))
    }

    @Test func parsesPorcelain() {
        let lines: [Substring] = ["## main", " M src/a.ts", "?? notes.md", "A  b.go", "R  old.txt -> new.txt", " D gone.js", "?? newdir/", "?? \"with space.md\""]
        let refs = RecentFiles.parseStatus(lines)
        #expect(refs.map(\.path) == ["src/a.ts", "notes.md", "b.go", "new.txt", "gone.js", "with space.md"])
        #expect(refs.map(\.status) == [.modified, .untracked, .added, .renamed, .deleted, .untracked])
    }

    @Test func collectPrefersChangedThenCommitted() throws {
        let f = try Fixture()
        try f.file("src/old.ts", "a")
        try f.file("src/new.ts", "b")
        try f.file("committed.go", "c")
        try f.file("package-lock.json", "{}")
        // 让 new.ts 比 old.ts 新
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: f.root + "/src/old.ts")
        let changed = [FileRef(path: "src/old.ts", status: .modified), FileRef(path: "src/new.ts", status: .untracked),
                       FileRef(path: "package-lock.json", status: .modified), FileRef(path: "removed.ts", status: .deleted)]
        let refs = RecentFiles.collect(project: f.root, changed: changed, committed: ["committed.go", "src/new.ts", "deleted-later.ts"], isGit: true)
        #expect(refs.map(\.path) == ["src/new.ts", "src/old.ts", "committed.go"])
        #expect(refs.last?.status == .committed)
    }

    @Test func nonGitUsesMtime() throws {
        let f = try Fixture()
        try f.file("index.html", "<h1>x</h1>")
        try f.file("css/style.css", "body{}")
        try f.file("node_modules/x.js", "")
        let refs = RecentFiles.collect(project: f.root, changed: [], committed: [], isGit: false)
        #expect(Set(refs.map(\.path)) == ["index.html", "css/style.css"])
    }

    @Test func htmlEntryPrefersIndex() throws {
        let f = try Fixture()
        try f.file("about.html", "")
        try f.file("index.html", "")
        let r = ProjectClassifier.classify(path: f.root, markers: FolderScanner.markers(at: f.root))
        #expect(r.htmlEntry == "index.html")
        let g = try Fixture()
        try g.file("demo.html", "")
        try g.file("package.json", "{}")
        #expect(ProjectClassifier.classify(path: g.root, markers: FolderScanner.markers(at: g.root)).htmlEntry == "demo.html")
    }
}
