import Darwin
import Foundation

/// 把 AI 会话与编辑器记录归到项目上。会话摘要按文件（大小 + 修改时间）缓存在 `ai-cache.json`。
public enum AIIndex {
    struct CachedFile: Codable {
        var size: Int
        var mtime: Date
        var summary: SessionSummary
    }

    struct Cache: Codable {
        /// 解析逻辑变化时递增，旧缓存整体作废
        static let currentVersion = 4
        var version = Cache.currentVersion
        var files: [String: CachedFile] = [:]
    }

    public static var cacheURL: URL { Codedog.dataDirectory.appending(path: "ai-cache.json") }

    /// 构建索引：项目路径 → 各工具用量。`projects` 为已知项目路径。
    public static func build(projects: [String], cacheURL: URL = AIIndex.cacheURL) async -> [String: [ToolUsage]] {
        await Task.detached(priority: .utility) {
            var cache = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder.codedog.decode(Cache.self, from: $0) } ?? Cache()
            if cache.version != Cache.currentVersion { cache = Cache() }
            let files = ClaudeCodeReader.sessionFiles().map { ($0, AITool.claudeCode) } + CodexReader.sessionFiles().map { ($0, AITool.codex) }
            var fresh: [String: CachedFile] = [:]
            let fm = FileManager.default

            // 只重读有变化的文件，并发处理
            var todo: [(String, AITool, Int, Date)] = []
            for (file, tool) in files {
                guard let attrs = try? fm.attributesOfItem(atPath: file),
                      let size = (attrs[.size] as? NSNumber)?.intValue,
                      let mtime = attrs[.modificationDate] as? Date else { continue }
                if let c = cache.files[file], c.size == size, abs(c.mtime.timeIntervalSince(mtime)) < 0.001 {
                    fresh[file] = c
                } else {
                    todo.append((file, tool, size, mtime))
                }
            }
            let parsed = await withTaskGroup(of: (String, CachedFile).self) { group in
                var out: [(String, CachedFile)] = []
                var it = todo.makeIterator()
                func add(_ g: inout TaskGroup<(String, CachedFile)>) {
                    guard let (file, tool, size, mtime) = it.next() else { return }
                    g.addTask {
                        let s = tool == .claudeCode ? ClaudeCodeReader.summarize(file: file) : CodexReader.summarize(file: file)
                        return (file, CachedFile(size: size, mtime: mtime, summary: s))
                    }
                }
                for _ in 0..<6 { add(&group) }
                for await r in group { out.append(r); add(&group) }
                return out
            }
            for (f, c) in parsed { fresh[f] = c }
            let changed = !parsed.isEmpty || fresh.count != cache.files.count
            cache.files = fresh
            if changed {
                try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? JSONEncoder.codedogCompact.encode(cache).write(to: cacheURL, options: .atomic)
            }

            let known = Set(projects)
            var index: [String: [AITool: ToolUsage]] = [:]
            for c in fresh.values {
                guard let cwd = c.summary.cwd, c.summary.lastAt != nil,
                      let owner = owner(of: FolderScanner.normalizeFast(cwd), in: known) else { continue }
                index[owner, default: [:]][c.summary.tool, default: ToolUsage(tool: c.summary.tool)].merge(c.summary)
            }
            for u in EditorUsageReader.usages() {
                guard let owner = owner(of: u.path, in: known) else { continue }
                var t = index[owner, default: [:]][u.tool] ?? ToolUsage(tool: u.tool)
                if let f = u.first { t.firstAt = min(t.firstAt ?? f, f) }
                if let l = u.last { t.lastAt = max(t.lastAt ?? l, l) }
                t.sessionCount += 1
                index[owner, default: [:]][u.tool] = t
            }
            return index.mapValues { $0.values.sorted { ($0.lastAt ?? .distantPast) > ($1.lastAt ?? .distantPast) } }
        }.value
    }

    static func owner(of path: String, in projects: Set<String>) -> String? {
        var candidate = path
        while candidate.count > 1 {
            if projects.contains(candidate) { return candidate }
            candidate = (candidate as NSString).deletingLastPathComponent
        }
        return nil
    }
}

extension JSONEncoder {
    static var codedogCompact: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension FolderScanner {
    /// 不解析符号链接的轻量规范化（日志里的 cwd 量大，避免逐个 realpath）。
    static func normalizeFast(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}

/// 检测正在运行的 AI 智能体进程（claude / codex 命令行）及其工作目录。
public enum RunningAgents {
    /// 一个正在运行的智能体进程。
    public struct Process: Sendable, Hashable {
        public var tool: AITool
        public var cwd: String
        /// 它所在的 App（顺着父进程往上找到的第一个 .app），通常是终端；tmux 等脱离终端的进程为 nil。
        public var terminal: String?
    }

    public static func scan() -> [String: Set<AITool>] {
        processes().reduce(into: [:]) { $0[$1.cwd, default: []].insert($1.tool) }
    }

    public static func processes() -> [Process] {
        var result: [Process] = []
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return result }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        for pid in pids.prefix(Int(max(0, n))) where pid > 0 {
            guard let exe = path(of: pid) else { continue }
            let tool: AITool?
            switch (exe as NSString).lastPathComponent {
            case "claude": tool = .claudeCode
            case "codex": tool = .codex
            default: tool = nil
            }
            guard let tool, let cwd = cwd(of: pid) else { continue }
            result.append(Process(tool: tool, cwd: FolderScanner.normalizeFast(cwd), terminal: hostApp(of: pid)))
        }
        return result
    }

    static func path(of pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return String(cString: buf)
    }

    static func parent(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let ppid = pid_t(info.pbi_ppid)
        return ppid > 1 && ppid != pid ? ppid : nil
    }

    /// 顺着父进程往上找，返回第一个位于 .app 包内的进程所属 App 的 bundle id（取最外层的 .app）。
    static func hostApp(of pid: pid_t) -> String? {
        var current = parent(of: pid)
        var depth = 0
        while let p = current, depth < 16 {
            if let exe = path(of: p), let range = exe.range(of: ".app/") {
                return Bundle(path: String(exe[..<range.lowerBound]) + ".app")?.bundleIdentifier
            }
            current = parent(of: p)
            depth += 1
        }
        return nil
    }

    static func cwd(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    /// 某项目（含子目录）正在运行的智能体。
    public static func tools(for project: String, in running: [String: Set<AITool>]) -> Set<AITool> {
        running.reduce(into: Set<AITool>()) { acc, kv in
            if kv.key == project || kv.key.hasPrefix(project + "/") { acc.formUnion(kv.value) }
        }
    }
}
