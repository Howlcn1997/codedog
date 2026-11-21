import Foundation

/// 只读 Git 信息：只在项目自身含 `.git` 时检测，不 fetch。
public enum GitInspector {
    public static func inspect(path: String) async -> GitInfo? {
        guard FileManager.default.fileExists(atPath: path + "/.git") else { return nil }
        async let status = try? ShellRunner.run("git", ["-C", path, "status", "--porcelain=v1", "--branch", "--untracked-files=normal"], timeout: .seconds(20))
        async let log = try? ShellRunner.run("git", ["-C", path, "log", "-3", "--format=%cI%x1f%s"], timeout: .seconds(10))
        async let remote = try? ShellRunner.run("git", ["-C", path, "config", "--get", "remote.origin.url"], timeout: .seconds(5))

        var info = GitInfo()
        if let s = await status, s.ok {
            let lines = s.stdout.split(separator: "\n")
            if let head = lines.first, head.hasPrefix("## ") { info.branch = parseBranch(String(head.dropFirst(3))) }
            info.dirtyFiles = lines.filter { !$0.hasPrefix("## ") }.count
        }
        if let l = await log, l.ok {
            let entries = l.stdout.split(separator: "\n").map { $0.split(separator: "\u{1f}", maxSplits: 1, omittingEmptySubsequences: false) }
            info.lastCommitAt = entries.first.flatMap { try? Date(String($0[0]), strategy: .iso8601) }
            info.recentCommits = entries.compactMap { $0.count > 1 ? String($0[1]) : nil }
        }
        if let r = await remote, r.ok {
            let url = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            info.remote = url.isEmpty ? nil : url
        }
        return info
    }

    /// `main...origin/main [ahead 1]` → `main`；`No commits yet on main` → `main`；`HEAD (no branch)` → `HEAD`
    static func parseBranch(_ s: String) -> String {
        if s.hasPrefix("No commits yet on ") { return String(s.dropFirst("No commits yet on ".count)) }
        if s.hasPrefix("HEAD (no branch)") { return "HEAD" }
        let name = s.components(separatedBy: "...").first ?? s
        return name.split(separator: " ").first.map(String.init) ?? name
    }
}
