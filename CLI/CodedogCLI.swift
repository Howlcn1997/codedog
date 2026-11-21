import ArgumentParser
import CodedogCore
import Foundation

@main
struct CodedogCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "codedog",
        abstract: "在终端里查找并打开你的项目。",
        version: Codedog.version,
        subcommands: [Open.self, PathCommand.self, List.self, Add.self, Scan.self],
        defaultSubcommand: Open.self
    )
}

/// 解析查询：精确名称优先，其次唯一搜索结果；多个候选时列到 stderr。
func resolve(_ query: String, in snapshot: LibrarySnapshot) throws -> ProjectItem {
    let visible = snapshot.items.filter { !$0.meta.hidden }
    let r = ProjectSearch.resolve(visible, query: query, document: \.searchDocument, by: LibrarySnapshot.defaultOrder)
    if let item = r.item { return item }
    var stderr = StandardError()
    if r.candidates.isEmpty {
        print("没有找到匹配“\(query)”的项目。", to: &stderr)
    } else {
        print("“\(query)”匹配到 \(r.candidates.count) 个项目，请说得更具体些：", to: &stderr)
        for c in r.candidates.prefix(10) { print("  \(c.project.name)\t\(c.project.path)", to: &stderr) }
    }
    throw ExitCode.failure
}

struct StandardError: TextOutputStream {
    mutating func write(_ string: String) { FileHandle.standardError.write(Data(string.utf8)) }
}

struct Open: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "用编辑器打开项目（默认命令）。")
    @Argument(help: "项目名称或搜索词。") var query: [String]
    @Flag(name: .shortAndLong, help: "在终端中打开。") var terminal = false
    @Flag(name: .shortAndLong, help: "在访达中显示。") var finder = false

    func run() async throws {
        let store = LibraryStore()
        let snapshot = await LibrarySnapshot.load(store: store)
        let item = try resolve(query.joined(separator: " "), in: snapshot)
        let path = item.project.path
        if finder {
            Opener.revealInFinder(path)
        } else if terminal {
            try await Opener.openInTerminal(path, terminal: snapshot.library.preferences.terminal)
        } else {
            try await Opener.openInEditor(path, editor: snapshot.library.editor(for: path))
        }
        try await store.mutate { $0.recordOpen(path) }
        print(path)
    }
}

struct PathCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "path", abstract: "输出项目的绝对路径，例如 cd \"$(codedog path web)\"。")
    @Argument(help: "项目名称或搜索词。") var query: [String]

    func run() async throws {
        print(try resolve(query.joined(separator: " "), in: await LibrarySnapshot.load()).project.path)
    }
}

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "列出项目（可带搜索词）。")
    @Argument(help: "搜索词。") var query: [String] = []
    @Flag(help: "包含已隐藏的项目。") var all = false

    func run() async throws {
        let snapshot = await LibrarySnapshot.load()
        let items = snapshot.items.filter { all || !$0.meta.hidden }
        for r in ProjectSearch.search(items, query: query.joined(separator: " "), document: \.searchDocument, by: LibrarySnapshot.defaultOrder) {
            let p = r.item.project
            print([p.name, p.kind.displayName, p.path, r.match.reasons.first ?? ""].joined(separator: "\t"))
        }
    }
}

struct Add: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "把目录加入 codedog（不在扫描目录里的项目）。")
    @Argument(help: "项目目录，默认当前目录。") var directory: String = FileManager.default.currentDirectoryPath

    func run() async throws {
        let path = FolderScanner.normalize(directory)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            var e = StandardError(); print("目录不存在：\(path)", to: &e); throw ExitCode.failure
        }
        let lib = try await LibraryStore().mutate { lib in
            let inRoot = lib.scanRoots.contains { path.hasPrefix($0 + "/") || path == $0 }
            if !inRoot { lib.updateMeta(path) { $0.pinned = true } }
        }
        let inRoot = lib.scanRoots.contains { path.hasPrefix($0 + "/") || path == $0 }
        print(inRoot ? "已在扫描目录中：\(path)" : "已添加：\(path)")
    }
}

/// 只读扫描，输出发现的项目（调试用，不写任何文件）。
struct Scan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "扫描目录并列出发现的项目（只读）。", shouldDisplay: false)

    @Argument(help: "扫描目录，默认使用建议目录。") var roots: [String] = []
    @Flag(help: "试跑旧版 projects.json 迁移并输出结果（不写盘）。") var legacy = false

    func run() async throws {
        let roots = self.roots.isEmpty ? FolderScanner.suggestedRoots() : self.roots.map(FolderScanner.normalize)
        let clock = ContinuousClock()
        let start = clock.now
        let projects = await DiscoveryService.scan(roots: roots, pinned: [])
            .sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
        let elapsed = clock.now - start
        for p in projects {
            let stacks = p.stacks.map(\.displayName).joined(separator: ",")
            let git = p.git.map { "\($0.branch ?? "-")\($0.dirtyFiles > 0 ? " *\($0.dirtyFiles)" : "")" } ?? ""
            print([p.name, p.kind.displayName, stacks, git, p.path].joined(separator: "\t"))
        }
        let kinds = Dictionary(grouping: projects, by: \.kind).map { "\($0.key.displayName) \($0.value.count)" }.sorted()
        print("\n根目录：\(roots.joined(separator: ", "))")
        print("共 \(projects.count) 个项目，用时 \(elapsed.formatted(.units(allowed: [.seconds, .milliseconds])))；\(kinds.joined(separator: "，"))")

        if legacy, let data = try? Data(contentsOf: Codedog.legacyURL) {
            var lib = Library()
            try LegacyImporter.migrate(data: data, into: &lib, suggestedRoots: roots)
            let found = Set(projects.map(\.path))
            let missing = lib.meta.keys.filter { !found.contains($0) }
            print("迁移：扫描目录 \(lib.scanRoots)，分类 \(lib.categories.map(\.name))，元数据 \(lib.meta.count) 条，其中未被扫描到 \(missing.count) 条")
            for m in missing.sorted() { print("  未扫描到：\(m)\(lib.meta[m]!.pinned ? "（手动添加）" : "")") }
        }
    }
}
