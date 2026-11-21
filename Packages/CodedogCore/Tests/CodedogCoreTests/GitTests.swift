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

    @Test func shellTimeout() async {
        await #expect(throws: ShellError.self) {
            _ = try await ShellRunner.run("sleep", ["5"], timeout: .milliseconds(200))
        }
    }
}
