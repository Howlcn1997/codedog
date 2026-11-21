import Foundation

/// 项目里最近在改的文件（用于文件夹里的"纸张"）。
public struct FileRef: Codable, Sendable, Hashable {
    public enum Status: String, Codable, Sendable { case modified, added, deleted, renamed, untracked, committed, recent }

    /// 相对项目根目录的路径
    public var path: String
    public var status: Status
    public var modifiedAt: Date?

    public init(path: String, status: Status, modifiedAt: Date? = nil) {
        self.path = path
        self.status = status
        self.modifiedAt = modifiedAt
    }

    public var name: String { (path as NSString).lastPathComponent }
    public var directory: String { (path as NSString).deletingLastPathComponent }
}

public enum RecentFiles {
    static let lockfiles: Set<String> = [
        "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lockb", "go.sum", "Cargo.lock", "Podfile.lock",
        "Gemfile.lock", "composer.lock", "poetry.lock", "uv.lock", "Pipfile.lock", "Package.resolved", ".DS_Store",
    ]
    static let binaryExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "ico", "icns", "heic", "pdf", "zip", "gz", "tgz", "7z", "rar", "dmg",
        "mp3", "mp4", "mov", "wav", "woff", "woff2", "ttf", "otf", "eot", "dylib", "so", "a", "o", "class", "jar",
        "pyc", "wasm", "sqlite", "db", "map", "lockb",
    ]

    /// 锁文件、构建产物、生成文件、二进制文件、隐藏目录下的文件都不展示。
    public static func isNoise(_ relPath: String) -> Bool {
        let parts = relPath.split(separator: "/").map(String.init)
        guard let name = parts.last else { return true }
        if lockfiles.contains(name) || name.hasSuffix(".min.js") || name.hasSuffix(".min.css") { return true }
        if name.hasPrefix(".") { return true }   // .nvmrc、.prettierignore 等配置文件
        if binaryExtensions.contains((name as NSString).pathExtension.lowercased()) { return true }
        for dir in parts.dropLast() where dir.hasPrefix(".") || FolderScanner.skippedNames.contains(dir) || dir == "coverage" {
            return true
        }
        return false
    }

    /// 解析 `git status --porcelain=v1` 的文件行（不含 `##` 分支行）。
    static func parseStatus(_ lines: [Substring]) -> [FileRef] {
        lines.compactMap { line in
            guard line.count > 3, !line.hasPrefix("## ") else { return nil }
            let code = line.prefix(2)
            var path = String(line.dropFirst(3))
            if let arrow = path.range(of: " -> ") { path = String(path[arrow.upperBound...]) }
            if path.hasPrefix("\""), path.hasSuffix("\""), path.count >= 2 { path = String(path.dropFirst().dropLast()) }
            if path.hasSuffix("/") { return nil }   // 未跟踪的整个目录
            let status: FileRef.Status = switch true {
            case code == "??": .untracked
            case code.contains("D"): .deleted
            case code.contains("R"): .renamed
            case code.contains("A"): .added
            default: .modified
            }
            return FileRef(path: path, status: status)
        }
    }

    /// 组合：未提交的改动（按修改时间新到旧）→ 最近提交改过的文件 → 非 Git 项目按修改时间。最多 `limit` 个。
    public static func collect(project: String, changed: [FileRef], committed: [String], isGit: Bool, limit: Int = 5) -> [FileRef] {
        let fm = FileManager.default
        func mtime(_ rel: String) -> Date? {
            (try? fm.attributesOfItem(atPath: project + "/" + rel))?[.modificationDate] as? Date
        }
        func tooBig(_ rel: String) -> Bool {
            ((try? fm.attributesOfItem(atPath: project + "/" + rel))?[.size] as? NSNumber)?.intValue ?? 0 > 2_000_000
        }
        var out: [FileRef] = []
        var seen = Set<String>()
        let live = changed.filter { !isNoise($0.path) && $0.status != .deleted && !tooBig($0.path) }
            .map { var f = $0; f.modifiedAt = mtime(f.path); return f }
            .sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
        for f in live where seen.insert(f.path).inserted { out.append(f) }
        for rel in committed where out.count < limit && !isNoise(rel) && seen.insert(rel).inserted {
            guard let date = mtime(rel), !tooBig(rel) else { continue }   // 已删除的跳过
            out.append(FileRef(path: rel, status: .committed, modifiedAt: date))
        }
        if !isGit && out.isEmpty { out = recentByMtime(project: project, limit: limit) }
        return Array(out.prefix(limit))
    }

    /// 非 Git 项目：根目录与下一层里最近修改的文件。
    static func recentByMtime(project: String, limit: Int) -> [FileRef] {
        let fm = FileManager.default
        var found: [FileRef] = []
        func visit(_ rel: String, depth: Int) {
            let dir = rel.isEmpty ? project : project + "/" + rel
            for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where !name.hasPrefix(".") && !FolderScanner.skippedNames.contains(name) {
                let childRel = rel.isEmpty ? name : rel + "/" + name
                guard let attrs = try? fm.attributesOfItem(atPath: project + "/" + childRel) else { continue }
                if attrs[.type] as? FileAttributeType == .typeDirectory {
                    if depth < 1 { visit(childRel, depth: depth + 1) }
                } else if attrs[.type] as? FileAttributeType == .typeRegular, !isNoise(childRel),
                          (attrs[.size] as? NSNumber)?.intValue ?? 0 <= 2_000_000 {
                    found.append(FileRef(path: childRel, status: .recent, modifiedAt: attrs[.modificationDate] as? Date))
                }
            }
        }
        visit("", depth: 0)
        return Array(found.sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }.prefix(limit))
    }
}
