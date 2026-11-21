import Foundation

/// 只读 Git 信息：只在项目自身含 `.git` 时检测，不 fetch。
public enum GitInspector {
    public static func inspect(path: String) async -> GitInfo? {
        guard FileManager.default.fileExists(atPath: path + "/.git") else { return nil }
        async let status = try? ShellRunner.run("git", ["-C", path, "status", "--porcelain=v1", "--branch", "--untracked-files=normal"], timeout: .seconds(20))
        async let log = try? ShellRunner.run("git", ["-C", path, "log", "--since=1.year", "--max-count=20000", "--format=%cI%x1f%ae%x1f%s"], timeout: .seconds(20))
        async let email = try? ShellRunner.run("git", ["-C", path, "config", "user.email"], timeout: .seconds(5))
        async let last = try? ShellRunner.run("git", ["-C", path, "log", "-1", "--format=%cI"], timeout: .seconds(5))
        async let remote = try? ShellRunner.run("git", ["-C", path, "config", "--get", "remote.origin.url"], timeout: .seconds(5))
        async let touched = try? ShellRunner.run("git", ["-C", path, "log", "-8", "--name-only", "--format="], timeout: .seconds(10))

        var info = GitInfo()
        if let s = await status, s.ok {
            let lines = s.stdout.split(separator: "\n")
            if let head = lines.first, head.hasPrefix("## ") { info.branch = parseBranch(String(head.dropFirst(3))) }
            info.dirtyFiles = lines.filter { !$0.hasPrefix("## ") }.count
            info.changedFiles = RecentFiles.parseStatus(lines)
        }
        if let t = await touched, t.ok {
            var seen = Set<String>()
            info.recentlyCommittedFiles = t.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty && seen.insert($0).inserted }
        }
        let me = (await email)?.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if let l = await log, l.ok {
            let parsed = parseLog(l.stdout, myEmail: me)
            info.recentCommits = Array(parsed.commits.prefix(10))
            info.commitDays = parsed.days
            info.lastCommitAt = parsed.commits.first?.date
        }
        if info.lastCommitAt == nil, let l = await last, l.ok {
            info.lastCommitAt = DayKey.parseISO(l.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let r = await remote, r.ok {
            let url = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            info.remote = url.isEmpty ? nil : url
        }
        return info
    }

    /// 解析 `%cI<US>%ae<US>%s`。邮箱为空时把所有提交都算作"我的"。
    static func parseLog(_ text: String, myEmail: String) -> (commits: [Commit], days: [String: Int]) {
        var commits: [Commit] = []
        var days: [String: Int] = [:]
        for line in text.split(separator: "\n") {
            let f = line.split(separator: "\u{1f}", maxSplits: 2, omittingEmptySubsequences: false)
            guard f.count == 3, let date = DayKey.parseISO(String(f[0])) else { continue }
            let mine = myEmail.isEmpty || f[1].lowercased() == myEmail
            commits.append(Commit(date: date, subject: String(f[2]), mine: mine))
            if mine { days[DayKey.string(date), default: 0] += 1 }
        }
        return (commits, days)
    }

    /// `main...origin/main [ahead 1]` → `main`；`No commits yet on main` → `main`；`HEAD (no branch)` → `HEAD`
    static func parseBranch(_ raw: String) -> String {
        var s = raw
        if s.hasPrefix("No commits yet on ") { s = String(s.dropFirst("No commits yet on ".count)) }
        if s.hasPrefix("HEAD (no branch)") { return "HEAD" }
        let name = s.components(separatedBy: "...").first ?? s
        return name.split(separator: " ").first.map(String.init) ?? name
    }
}
