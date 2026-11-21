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
        async let git = GitInspector.inspect(path: path)
        return DiscoveredProject(
            path: path,
            name: (path as NSString).lastPathComponent,
            stacks: c.stacks,
            kind: c.kind,
            markers: markers,
            description: c.description,
            readmeFile: c.readmeFile,
            createdAt: attrs?[.creationDate] as? Date,
            modifiedAt: latestModification(in: path),
            git: await git)
    }

    /// 完整扫描：扫描目录 + 手动添加的项目。
    public static func scan(roots: [String], pinned: [String], concurrency: Int = 8) async -> [DiscoveredProject] {
        let paths = await Task.detached(priority: .utility) {
            FolderScanner.findProjects(in: roots)
        }.value
        let all = (paths + pinned.map(FolderScanner.normalize)).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return await inspectAll(all, concurrency: concurrency)
    }

    public static func inspectAll(_ paths: [String], concurrency: Int = 8) async -> [DiscoveredProject] {
        await withTaskGroup(of: DiscoveredProject?.self) { group in
            var results: [DiscoveredProject] = []
            var iterator = paths.makeIterator()
            for _ in 0..<max(1, concurrency) {
                guard let p = iterator.next() else { break }
                group.addTask { await inspect(path: p) }
            }
            for await r in group {
                if let r { results.append(r) }
                if let p = iterator.next() { group.addTask { await inspect(path: p) } }
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
