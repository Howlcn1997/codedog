import Foundation

/// 在扫描目录里查找项目。遇到项目标记即视为项目，不再往下钻。
public enum FolderScanner {
    public struct Options: Sendable {
        public var maxDepth = 5
        public var maxProjects = 3000
        public init() {}
    }

    /// 出现任一即为项目。
    static let markerFiles: Set<String> = [
        ".git", "package.json", "deno.json", "go.mod", "go.work", "pyproject.toml", "requirements.txt", "setup.py",
        "Pipfile", "Cargo.toml", "Package.swift", "pom.xml", "build.gradle", "build.gradle.kts", "Gemfile",
        "composer.json", "pubspec.yaml", "CMakeLists.txt", "index.html",
        ".codedog-workspace.json", // 旧版"项目组"目录，整体视为一个项目
    ]
    static let markerExtensions: Set<String> = ["xcodeproj", "xcworkspace"]

    /// 永远不进入的目录。
    static let skippedNames: Set<String> = [
        "node_modules", "dist", "build", "out", "target", "vendor", "Pods", "DerivedData", "venv", "env",
        "__pycache__", "site-packages", "Library", "Applications", "Music", "Movies", "Pictures", "Photos Library.photoslibrary",
    ]

    /// 返回某目录的项目标记；不是项目时返回空数组。
    public static func markers(at path: String) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        return names.filter { name in
            markerFiles.contains(name) || markerExtensions.contains((name as NSString).pathExtension)
        }.sorted()
    }

    /// 广度优先扫描，返回项目路径（已规范化、去重）。
    public static func findProjects(in roots: [String], options: Options = Options()) -> [String] {
        let fm = FileManager.default
        var found: [String] = []
        var seen = Set<String>()
        var queue: [(String, Int)] = roots.map { (normalize($0), 0) }
        var index = 0

        while index < queue.count, found.count < options.maxProjects {
            let (dir, depth) = queue[index]
            index += 1
            guard seen.insert(dir).inserted else { continue }
            // git worktree 是主仓库的附属检出，不单独算项目，也不往下钻。
            if isGitWorktree(dir) { continue }

            if !markers(at: dir).isEmpty {
                found.append(dir)
                continue
            }
            guard depth < options.maxDepth, let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names.sorted() where !name.hasPrefix(".") && !skippedNames.contains(name) {
                let child = dir + "/" + name
                var isDir: ObjCBool = false
                // 不跟随符号链接，避免环与重复。
                guard let attrs = try? fm.attributesOfItem(atPath: child),
                      attrs[.type] as? FileAttributeType == .typeDirectory,
                      fm.fileExists(atPath: child, isDirectory: &isDir), isDir.boolValue,
                      !name.hasSuffix(".app"), !name.hasSuffix(".bundle"), !name.hasSuffix(".framework")
                else { continue }
                queue.append((child, depth + 1))
            }
        }
        return found
    }

    /// `.git` 为文件且指向 `<主仓库>/.git/worktrees/<名字>` 时为 worktree（子模块指向 `.git/modules/`，不算）。
    public static func isGitWorktree(_ path: String) -> Bool {
        let gitPath = path + "/.git"
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDir), !isDir.boolValue,
              let content = try? String(contentsOfFile: gitPath, encoding: .utf8),
              let line = content.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") })
        else { return false }
        let gitdir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        return gitdir.contains("/.git/worktrees/")
    }

    public static func normalize(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(filePath: expanded).standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
            .replacingOccurrences(of: "/$", with: "", options: .regularExpression)
    }

    /// 首次启动时建议的扫描目录（存在才返回）。
    public static func suggestedRoots(home: String = NSHomeDirectory()) -> [String] {
        ["codespace", "code", "Code", "Projects", "projects", "Developer", "src", "workspace", "work", "dev", "github", "GitHub", "repos"]
            .map { home + "/" + $0 }
            .filter { var d: ObjCBool = false; return FileManager.default.fileExists(atPath: $0, isDirectory: &d) && d.boolValue }
            .map(normalize)
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }
}
