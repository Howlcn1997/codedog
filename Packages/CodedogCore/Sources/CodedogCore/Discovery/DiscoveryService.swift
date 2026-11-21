import Foundation

/// 扫描调度：发现项目 → 并发检测 → 增量刷新。
public enum DiscoveryService {
    /// 检测单个项目（只读文件 + git）。路径不存在时返回 nil。
    public static func inspect(path: String) async -> DiscoveredProject? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
        let markers = FolderScanner.markers(at: path)
        let c = ProjectClassifier.classify(path: path, markers: markers)
        let attrs = try? fm.attributesOfItem(atPath: path)
        async let languages = LanguageStats.collect(path: path, isGit: markers.contains(".git"))
        let checked = await GitInspector.inspectChecked(path: path)
        let gitInfo = checked?.info
        var project = DiscoveredProject(
            path: path,
            name: (path as NSString).lastPathComponent,
            stacks: c.stacks,
            frameworks: c.frameworks,
            kind: c.kind,
            markers: markers,
            description: c.description,
            readmeFile: c.readmeFile,
            readmeText: c.readmeText,
            dependencies: c.dependencies,
            createdAt: attrs?[.creationDate] as? Date,
            modifiedAt: latestModification(in: path),
            git: gitInfo)
        project.htmlEntry = c.htmlEntry
        project.recentFiles = RecentFiles.collect(project: path, changed: gitInfo?.changedFiles ?? [],
                                                  committed: gitInfo?.recentlyCommittedFiles ?? [], isGit: gitInfo != nil)
        project.languages = await languages
        // Git 信息不完整时不留指纹，下次扫描会重新完整检测
        project.fingerprint = checked?.complete == false ? nil : fingerprint(path: path)
        return project
    }

    /// 检测逻辑变化时加 1，让旧缓存全部失效。
    static let fingerprintVersion: Double = 3

    /// 项目指纹：根目录（增删条目）与顶层文件（README、package.json 等）的修改时间 + Git 提交历史指纹。
    /// 不看子目录，子目录里改代码只影响工作区状态，`refresh` 会单独刷新。
    /// 只对 Git 项目生成；非 Git 项目检测本身很便宜，始终完整检测。
    static func fingerprint(path: String) -> [Double]? {
        guard let history = GitInspector.historyFingerprint(path: path) else { return nil }
        let url = URL(filePath: path, directoryHint: .isDirectory)
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys)) ?? []
        let top = files.compactMap { u -> Double? in
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isDirectory != true else { return nil }
            return v.contentModificationDate?.timeIntervalSince1970
        }.max() ?? -1
        return [fingerprintVersion, mtime(path), top] + history
    }

    static func mtime(_ path: String) -> Double {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
    }

    /// 增量检测：指纹没变的 Git 项目复用缓存，只重新跑一次 `git status` 刷新工作区状态；否则完整检测。
    public static func refresh(_ cached: DiscoveredProject) async -> DiscoveredProject? {
        let path = cached.path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
        guard let old = cached.fingerprint, var git = cached.git, fingerprint(path: path) == old else {
            return await inspect(path: path)
        }
        await GitInspector.refreshStatus(path: path, &git)
        var project = cached
        project.git = git
        project.modifiedAt = latestModification(in: path)
        project.recentFiles = RecentFiles.collect(project: path, changed: git.changedFiles,
                                                  committed: git.recentlyCommittedFiles, isGit: true)
        project.scannedAt = .now
        // 重新计算，带上最新的目录修改时间
        project.fingerprint = fingerprint(path: path)
        return project
    }

    /// 扫描：重新发现目录里的项目 + 手动添加的项目。传入上次的结果 `previous` 时增量检测（见 `refresh`）。
    public static func scan(roots: [String], pinned: [String], previous: [DiscoveredProject] = [], concurrency: Int = 8) async -> [DiscoveredProject] {
        let paths = await Task.detached(priority: .utility) {
            FolderScanner.findProjects(in: roots)
        }.value
        let all = (paths + pinned.map(FolderScanner.normalize)).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let cached = Dictionary(previous.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        return await concurrentMap(all, concurrency: concurrency) { p in
            if let c = cached[p] { await refresh(c) } else { await inspect(path: p) }
        }
    }

    public static func inspectAll(_ paths: [String], concurrency: Int = 8) async -> [DiscoveredProject] {
        await concurrentMap(paths, concurrency: concurrency) { await inspect(path: $0) }
    }

    private static func concurrentMap(_ paths: [String], concurrency: Int, _ body: @escaping @Sendable (String) async -> DiscoveredProject?) async -> [DiscoveredProject] {
        await withTaskGroup(of: DiscoveredProject?.self) { group in
            var results: [DiscoveredProject] = []
            var iterator = paths.makeIterator()
            for _ in 0..<max(1, concurrency) {
                guard let p = iterator.next() else { break }
                group.addTask { await body(p) }
            }
            for await r in group {
                if let r { results.append(r) }
                if let p = iterator.next() { group.addTask { await body(p) } }
            }
            return results
        }
    }

    /// 文件变化后需要重新检测的项目路径；返回 nil 表示目录结构变化，需要重新发现。
    public static func affectedProjects(events: [String], projects: Set<String>, roots: [String]) -> Set<String>? {
        var affected = Set<String>()
        for event in events {
            if isNoise(event) { continue }
            if let owner = owningProject(event, in: projects) {
                affected.insert(owner)
            } else if roots.contains(where: { event.hasPrefix($0 + "/") || event == $0 }) {
                return nil
            }
        }
        return affected
    }

    static func owningProject(_ path: String, in projects: Set<String>) -> String? {
        var candidate = path
        while candidate.count > 1 {
            if projects.contains(candidate) { return candidate }
            candidate = (candidate as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// 忽略依赖目录、构建产物、git 对象等高频变化。
    static func isNoise(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        for (i, part) in parts.enumerated() {
            if FolderScanner.skippedNames.contains(String(part)) { return true }
            if part == ".git" {
                let rest = parts.dropFirst(i + 1)
                guard let first = rest.first else { return false }
                return !(first == "HEAD" || first == "index" || first == "refs")
            }
            if part == ".DS_Store" { return true }
        }
        return false
    }

    /// 顶层条目（排除依赖目录与隐藏文件）的最新修改时间。
    static func latestModification(in path: String) -> Date? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: path) else { return nil }
        return names.lazy
            .filter { !$0.hasPrefix(".") && !FolderScanner.skippedNames.contains($0) }
            .compactMap { (try? fm.attributesOfItem(atPath: path + "/" + $0))?[.modificationDate] as? Date }
            .max()
    }
}
