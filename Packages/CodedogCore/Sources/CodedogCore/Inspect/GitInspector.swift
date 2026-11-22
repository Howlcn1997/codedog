import Foundation

/// 只读 Git 信息：只在项目自身含 `.git` 时检测，不 fetch。
public enum GitInspector {
    public static func inspect(path: String) async -> GitInfo? {
        await inspectChecked(path: path)?.info
    }

    /// `complete` 为 false 表示有命令超时或无法运行，结果不完整，不应被当作缓存复用。
    static func inspectChecked(path: String) async -> (info: GitInfo, complete: Bool)? {
        guard FileManager.default.fileExists(atPath: path + "/.git") else { return nil }
        async let status = try? ShellRunner.run("git", ["-C", path, "status", "--porcelain=v1", "--branch", "--untracked-files=normal"], timeout: .seconds(20))
        async let log = try? ShellRunner.run("git", ["-C", path, "log", "--since=1.year", "--max-count=20000", "--format=%cI%x1f%ae%x1f%s"], timeout: .seconds(20))
        async let email = try? ShellRunner.run("git", ["-C", path, "config", "user.email"], timeout: .seconds(5))
        async let last = try? ShellRunner.run("git", ["-C", path, "log", "-1", "--format=%cI"], timeout: .seconds(5))
        async let remote = try? ShellRunner.run("git", ["-C", path, "config", "--get", "remote.origin.url"], timeout: .seconds(5))
        async let touched = try? ShellRunner.run("git", ["-C", path, "log", "-8", "--name-only", "--format="], timeout: .seconds(10))
        async let worktrees = listWorktrees(path: path)

        var info = GitInfo()
        // try? 得到 nil 说明命令超时或没能启动（非零退出码不算，比如没有远程时 config 返回 1）
        var complete = true
        for r in [await status, await log, await email, await remote, await touched] where r == nil { complete = false }
        if let s = await status, s.ok { applyStatus(s.stdout, to: &info) }
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
        info.worktrees = await worktrees
        return (info, complete)
    }

    /// 只刷新工作区状态（分支、未提交文件、worktree），用于提交历史没变的项目。
    public static func refreshStatus(path: String, _ info: inout GitInfo) async {
        async let worktrees = listWorktrees(path: path)
        if let s = try? await ShellRunner.run("git", ["-C", path, "status", "--porcelain=v1", "--branch", "--untracked-files=normal"], timeout: .seconds(20)), s.ok {
            applyStatus(s.stdout, to: &info)
        }
        if let w = await worktrees { info.worktrees = w }
    }

    /// 附属工作树；命令失败返回 nil（保留旧值）。
    static func listWorktrees(path: String) async -> [GitWorktree]? {
        guard let r = try? await ShellRunner.run("git", ["-C", path, "worktree", "list", "--porcelain"], timeout: .seconds(5)), r.ok else { return nil }
        return parseWorktrees(r.stdout, mainPath: path)
    }

    /// 解析 `git worktree list --porcelain`：空行分隔的块，第一块是主工作区（跳过），bare 仓库也跳过。
    static func parseWorktrees(_ text: String, mainPath: String) -> [GitWorktree] {
        let main = FolderScanner.normalize(mainPath)
        var result: [GitWorktree] = []
        for (i, block) in text.components(separatedBy: "\n\n").enumerated() {
            var wt = GitWorktree(path: "")
            var bare = false
            for line in block.split(separator: "\n") {
                if line.hasPrefix("worktree ") { wt.path = String(line.dropFirst("worktree ".count)) }
                else if line.hasPrefix("branch ") {
                    let ref = line.dropFirst("branch ".count)
                    wt.branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : String(ref)
                }
                else if line == "bare" { bare = true }
                else if line.hasPrefix("prunable") { wt.prunable = true }
            }
            guard !wt.path.isEmpty, !bare, i > 0 || wt.path != main, FolderScanner.normalize(wt.path) != main else { continue }
            result.append(wt)
        }
        return result
    }

    static func applyStatus(_ stdout: String, to info: inout GitInfo) {
        let lines = stdout.split(separator: "\n")
        if let head = lines.first, head.hasPrefix("## ") { info.branch = parseBranch(String(head.dropFirst(3))) }
        info.dirtyFiles = lines.filter { !$0.hasPrefix("## ") }.count
        info.changedFiles = RecentFiles.parseStatus(lines)
    }

    /// 提交历史指纹：HEAD、当前分支 ref、reflog、packed-refs、config 的修改时间。
    /// `.git` 不是目录（worktree、子模块）时返回 nil，表示无法判断、需要完整检测。
    static func historyFingerprint(path: String) -> [Double]? {
        let git = path + "/.git"
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: git, isDirectory: &isDir), isDir.boolValue else { return nil }
        var files = ["HEAD", "logs/HEAD", "packed-refs", "config", "refs/heads"]
        if let head = try? String(contentsOfFile: git + "/HEAD", encoding: .utf8), head.hasPrefix("ref: ") {
            files.append(head.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return files.map { DiscoveryService.mtime(git + "/" + $0) }
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
