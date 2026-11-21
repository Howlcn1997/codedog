import Foundation

/// 某种语言在项目里的代码量（字节）。
public struct LanguageShare: Codable, Sendable, Hashable {
    public var name: String
    public var bytes: Int
    /// 语言代表色（GitHub linguist 配色），0xRRGGBB
    public var color: UInt32

    public init(name: String, bytes: Int, color: UInt32) {
        self.name = name
        self.bytes = bytes
        self.color = color
    }
}

/// 语言分布：按扩展名把文件大小归到语言上（类似 GitHub linguist 的简化版）。
/// Git 项目用 `git ls-tree` 统计已提交的文件（一条命令拿到全部大小）；非 Git 项目遍历目录。
/// 只统计编程/标记语言，JSON、Markdown、YAML 等数据和文档不计入。
public enum LanguageStats {
    struct Language { var name: String; var color: UInt32 }

    static let byExtension: [String: Language] = {
        let table: [(String, UInt32, [String])] = [
            ("Swift", 0xF05138, ["swift"]),
            ("Objective-C", 0x438EFF, ["m"]),
            ("Objective-C++", 0x6866FB, ["mm"]),
            ("C", 0x555555, ["c"]),
            ("C++", 0xF34B7D, ["cpp", "cc", "cxx", "hpp", "hh", "hxx"]),
            ("C#", 0x178600, ["cs"]),
            ("Go", 0x00ADD8, ["go"]),
            ("Rust", 0xDEA584, ["rs"]),
            ("Java", 0xB07219, ["java"]),
            ("Kotlin", 0xA97BFF, ["kt", "kts"]),
            ("Scala", 0xC22D40, ["scala"]),
            ("Groovy", 0x4298B8, ["groovy", "gradle"]),
            ("Python", 0x3572A5, ["py", "pyi"]),
            ("Jupyter Notebook", 0xDA5B0B, ["ipynb"]),
            ("Ruby", 0x701516, ["rb"]),
            ("PHP", 0x4F5D95, ["php"]),
            ("Perl", 0x0298C3, ["pl", "pm"]),
            ("JavaScript", 0xF1E05A, ["js", "mjs", "cjs", "jsx"]),
            ("TypeScript", 0x3178C6, ["ts", "tsx", "mts", "cts"]),
            ("Vue", 0x41B883, ["vue"]),
            ("Svelte", 0xFF3E00, ["svelte"]),
            ("Astro", 0xFF5A03, ["astro"]),
            ("HTML", 0xE34C26, ["html", "htm"]),
            ("CSS", 0x563D7C, ["css"]),
            ("SCSS", 0xC6538C, ["scss", "sass"]),
            ("Less", 0x1D365D, ["less"]),
            ("Shell", 0x89E051, ["sh", "bash", "zsh", "fish"]),
            ("PowerShell", 0x012456, ["ps1"]),
            ("Lua", 0x000080, ["lua"]),
            ("Dart", 0x00B4AB, ["dart"]),
            ("Elixir", 0x6E4A7E, ["ex", "exs"]),
            ("Erlang", 0xB83998, ["erl"]),
            ("Haskell", 0x5E5086, ["hs"]),
            ("Clojure", 0xDB5855, ["clj", "cljs", "cljc"]),
            ("R", 0x198CE7, ["r"]),
            ("Julia", 0xA270BA, ["jl"]),
            ("Zig", 0xEC915C, ["zig"]),
            ("Nim", 0xFFC200, ["nim"]),
            ("OCaml", 0xEF7A08, ["ml", "mli"]),
            ("Solidity", 0xAA6746, ["sol"]),
            ("Metal", 0x8F14E9, ["metal"]),
            ("GLSL", 0x5686A5, ["glsl", "vert", "frag"]),
        ]
        var map: [String: Language] = [:]
        for (name, color, exts) in table { for e in exts { map[e] = Language(name: name, color: color) } }
        return map
    }()

    static let byFilename: [String: Language] = [
        "Dockerfile": Language(name: "Dockerfile", color: 0x384D54),
        "Makefile": Language(name: "Makefile", color: 0x427819),
    ]

    /// `.h` 归属：项目里有 Objective-C 就算 Objective-C，有 C++ 就算 C++，否则算 C。
    static let headerOwners = ["Objective-C", "Objective-C++", "C++", "C"]

    public static func collect(path: String, isGit: Bool) async -> [LanguageShare] {
        let files: [(String, Int)]
        if isGit, let tracked = await gitFiles(path: path) {
            files = tracked
        } else {
            files = walk(path: path)
        }
        return tally(files)
    }

    /// 文件列表（相对路径, 字节）→ 各语言占比，从大到小。
    static func tally(_ files: [(String, Int)]) -> [LanguageShare] {
        var bytes: [String: Int] = [:]
        var colors: [String: UInt32] = [:]
        var headers = 0
        for (rel, size) in files where size > 0 && !isExcluded(rel) {
            let name = (rel as NSString).lastPathComponent
            let ext = (name as NSString).pathExtension.lowercased()
            if ext == "h" { headers += size; continue }
            guard let lang = byFilename[name] ?? byExtension[ext] else { continue }
            bytes[lang.name, default: 0] += size
            colors[lang.name] = lang.color
        }
        if headers > 0 {
            let owner = headerOwners.first { bytes[$0] != nil } ?? "C"
            bytes[owner, default: 0] += headers
            colors[owner] = byExtension.values.first { $0.name == owner }?.color ?? 0x555555
        }
        return bytes.map { LanguageShare(name: $0.key, bytes: $0.value, color: colors[$0.key] ?? 0x8B8B8B) }
            .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.name < $1.name }
    }

    /// 依赖、构建产物、压缩文件、隐藏目录、第三方代码不计入。
    static func isExcluded(_ rel: String) -> Bool {
        if RecentFiles.isNoise(rel) { return true }
        let parts = rel.split(separator: "/")
        return parts.dropLast().contains { $0 == "third_party" || $0 == "third-party" || $0 == "external" || $0 == "generated" }
    }

    /// `git ls-tree -r -l -z HEAD`：`<mode> <type> <sha> <size>\t<path>\0`。仓库还没有提交时返回 nil。
    static func gitFiles(path: String) async -> [(String, Int)]? {
        guard let r = try? await ShellRunner.run("git", ["-C", path, "ls-tree", "-r", "-l", "-z", "--full-tree", "HEAD"], timeout: .seconds(20)), r.ok else { return nil }
        return parseLsTree(r.stdout)
    }

    static func parseLsTree(_ text: String) -> [(String, Int)] {
        text.split(separator: "\0").compactMap { entry in
            guard let tab = entry.firstIndex(of: "\t") else { return nil }
            let meta = entry[..<tab].split(separator: " ", omittingEmptySubsequences: true)
            guard meta.count == 4, meta[1] == "blob", let size = Int(meta[3]) else { return nil }
            return (String(entry[entry.index(after: tab)...]), size)
        }
    }

    /// 非 Git 项目：遍历目录（跳过隐藏目录与依赖目录），最多看 20000 个文件。
    static func walk(path: String, limit: Int = 20_000) -> [(String, Int)] {
        let root = URL(filePath: path, directoryHint: .isDirectory)
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [(String, Int)] = []
        let prefix = root.path(percentEncoded: false).count
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isDirectory == true {
                if FolderScanner.skippedNames.contains(url.lastPathComponent) { e.skipDescendants() }
                continue
            }
            guard v.isRegularFile == true else { continue }
            out.append((String(url.path(percentEncoded: false).dropFirst(prefix)), v.fileSize ?? 0))
            if out.count >= limit { break }
        }
        return out
    }
}
