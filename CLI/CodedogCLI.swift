import ArgumentParser
import CodedogCore
import Foundation

@main
struct CodedogCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "codedog",
        abstract: "在终端里查找并打开你的项目。",
        version: Codedog.version,
        subcommands: [Scan.self]
    )
}

/// 只读扫描，输出发现的项目（调试用，不写任何文件）。
struct Scan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "扫描目录并列出发现的项目（只读）。")

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
