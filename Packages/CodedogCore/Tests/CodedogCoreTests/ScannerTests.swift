import Foundation
import Testing
@testable import CodedogCore

@Suite struct ScannerTests {
    @Test func findsProjectsAndStopsAtProjectRoot() throws {
        let f = try Fixture()
        try f.file("company/api/go.mod", "module x\n\ngo 1.22\n")
        try f.file("company/api/sub/package.json", "{}")          // 项目内部，不应再算
        try f.file("personal/site/index.html", "<html></html>")
        try f.dir("personal/repo/.git")
        try f.file("personal/node_modules/x/package.json", "{}")  // 依赖目录跳过
        try f.file("personal/.hidden/package.json", "{}")         // 隐藏目录跳过
        try f.file("a/b/c/d/e/f/package.json", "{}")              // 超过深度 5

        let found = FolderScanner.findProjects(in: [f.root]).map { String($0.dropFirst(f.root.count + 1)) }
        #expect(Set(found) == ["company/api", "personal/site", "personal/repo"])
    }

    @Test func skipsGitWorktreesButKeepsSubmoduleStyleRepos() throws {
        let f = try Fixture()
        try f.dir("main/.git/worktrees/feature")
        try f.file("main-feature/.git", "gitdir: \(f.root)/main/.git/worktrees/feature\n")
        try f.file("main-feature/package.json", "{}")
        try f.file("main-feature/nested/package.json", "{}")       // worktree 内部也不钻
        try f.file("other/.git", "gitdir: ../main/.git/modules/other\n")
        let found = FolderScanner.findProjects(in: [f.root]).map { String($0.dropFirst(f.root.count + 1)) }
        #expect(Set(found) == ["main", "other"])
    }

    @Test func legacyWorkspaceIsOneProject() throws {
        let f = try Fixture()
        try f.file("workspaces/ws-1/.codedog-workspace.json", "{}")
        try f.file("workspaces/ws-1/design/demo/index.html", "")
        let found = FolderScanner.findProjects(in: [f.root])
        #expect(found == [f.root + "/workspaces/ws-1"])
    }

    @Test func rootItselfCanBeAProject() throws {
        let f = try Fixture()
        try f.file("Cargo.toml", "[package]\n")
        #expect(FolderScanner.findProjects(in: [f.root]) == [f.root])
    }

    @Test func respectsMaxProjects() throws {
        let f = try Fixture()
        for i in 0..<10 { try f.file("p\(i)/package.json", "{}") }
        var o = FolderScanner.Options()
        o.maxProjects = 3
        #expect(FolderScanner.findProjects(in: [f.root], options: o).count == 3)
    }

    @Test func noiseFilter() {
        #expect(DiscoveryService.isNoise("/a/p/node_modules/x/index.js"))
        #expect(DiscoveryService.isNoise("/a/p/.git/objects/ab/cd"))
        #expect(!DiscoveryService.isNoise("/a/p/.git/HEAD"))
        #expect(!DiscoveryService.isNoise("/a/p/.git/refs/heads/main"))
        #expect(!DiscoveryService.isNoise("/a/p/src/main.go"))
    }

    @Test func affectedProjectsMapsEventsToOwners() {
        let projects: Set = ["/r/a", "/r/b"]
        #expect(DiscoveryService.affectedProjects(events: ["/r/a/src/x.ts", "/r/b/.git/HEAD"], projects: projects, roots: ["/r"]) == ["/r/a", "/r/b"])
        #expect(DiscoveryService.affectedProjects(events: ["/r/new/package.json"], projects: projects, roots: ["/r"]) == nil)
        #expect(DiscoveryService.affectedProjects(events: ["/r/a/node_modules/q"], projects: projects, roots: ["/r"]) == [])
    }
}
