import Foundation
import Testing
@testable import CodedogCore

@Suite struct GitTests {
    @Test func parseBranch() {
        #expect(GitInspector.parseBranch("main...origin/main [ahead 1]") == "main")
        #expect(GitInspector.parseBranch("feature/x") == "feature/x")
        #expect(GitInspector.parseBranch("No commits yet on dev") == "dev")
        #expect(GitInspector.parseBranch("No commits yet on master...origin/master [gone]") == "master")
        #expect(GitInspector.parseBranch("HEAD (no branch)") == "HEAD")
    }

    @Test func webURL() {
        #expect(GitInfo(remote: "git@github.com:a/b.git").webURL?.absoluteString == "https://github.com/a/b")
        #expect(GitInfo(remote: "ssh://git@host.com/a/b").webURL?.absoluteString == "https://host.com/a/b")
        #expect(GitInfo(remote: "https://github.com/a/b.git").webURL?.absoluteString == "https://github.com/a/b")
        #expect(GitInfo(remote: "/local/path").webURL == nil)
    }

    @Test func inspectsRealRepository() async throws {
        let f = try Fixture()
        try f.file("README.md", "hi")
        let env = ["GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"]
        _ = try await ShellRunner.run("git", ["init", "-q", "-b", "trunk", f.root])
        _ = try await ShellRunner.run("git", ["-C", f.root, "config", "user.email", "t@t"])
        _ = try await ShellRunner.run("git", ["-C", f.root, "add", "."])
        _ = try await ShellRunner.run("git", ["-C", f.root, "commit", "-qm", "first commit"], environment: env)
        _ = try await ShellRunner.run("git", ["-C", f.root, "remote", "add", "origin", "git@github.com:me/x.git"])
        try f.file("new.txt", "x")

        let info = try #require(await GitInspector.inspect(path: f.root))
        #expect(info.branch == "trunk")
        #expect(info.dirtyFiles == 1)
        #expect(info.recentCommits.map(\.subject) == ["first commit"])
        #expect(info.commitDays.values.reduce(0, +) == 1)
        #expect(info.lastCommitAt != nil)
        #expect(info.remote == "git@github.com:me/x.git")
    }

    @Test func incrementalRefreshReusesHistory() async throws {
        let f = try Fixture()
        try f.file("README.md", "hi")
        try f.file("src/main.txt", "v1")
        let env = ["GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"]
        _ = try await ShellRunner.run("git", ["init", "-q", "-b", "trunk", f.root])
        _ = try await ShellRunner.run("git", ["-C", f.root, "add", "."])
        _ = try await ShellRunner.run("git", ["-C", f.root, "commit", "-qm", "first"], environment: env)

        let first = try #require(await DiscoveryService.inspect(path: f.root))
        #expect(first.fingerprint != nil)

        // 历史没变：复用缓存（用一个假的提交记录验证没有重跑 git log），但工作区状态是新的
        var cached = first
        cached.git?.recentCommits = [Commit(date: .now, subject: "cached", mine: true)]
        try "v2".write(toFile: f.root + "/src/main.txt", atomically: true, encoding: .utf8)
        let reused = try #require(await DiscoveryService.refresh(cached))
        #expect(reused.git?.recentCommits.map(\.subject) == ["cached"])
        #expect(reused.git?.dirtyFiles == 1)

        // 新提交：指纹变化，完整检测
        _ = try await ShellRunner.run("git", ["-C", f.root, "add", "."])
        _ = try await ShellRunner.run("git", ["-C", f.root, "commit", "-qm", "second"], environment: env)
        let fresh = try #require(await DiscoveryService.refresh(reused))
        #expect(fresh.git?.recentCommits.map(\.subject) == ["second", "first"])
        #expect(fresh.git?.dirtyFiles == 0)
    }

    @Test func shellTimeout() async {
        await #expect(throws: ShellError.self) {
            _ = try await ShellRunner.run("sleep", ["5"], timeout: .milliseconds(200))
        }
    }
}
