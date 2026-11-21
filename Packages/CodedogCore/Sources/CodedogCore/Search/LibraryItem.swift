import Foundation

/// 扫描结果 + 用户元数据的组合视图，App 与 CLI 共用。
public struct LibraryItem: Sendable, Hashable, Identifiable {
    public var project: DiscoveredProject
    public var meta: ProjectMeta
    public var categoryNames: [String]

    public var id: String { project.path }

    public init(project: DiscoveredProject, meta: ProjectMeta, categoryNames: [String]) {
        self.project = project
        self.meta = meta
        self.categoryNames = categoryNames
    }

    public var searchDocument: SearchDocument {
        SearchDocument(
            name: project.name,
            categories: categoryNames,
            description: project.description,
            notes: meta.notes,
            path: project.path,
            remote: project.git?.remote,
            stacks: project.stacks.map(\.displayName),
            kind: project.kind.displayName,
            dependencies: project.dependencies,
            readme: project.readmeText)
    }

    /// 最近感知到的活动：自己打开过、提交、文件修改中最晚的一个。
    public var lastActivity: Date? {
        [meta.lastOpened, project.lastActivity].compactMap { $0 }.max()
    }

    /// 常用度：打开次数按距今天数衰减（半衰期约 7 天），用于启动器排序。
    public func frecency(now: Date = .now) -> Double {
        guard let last = meta.lastOpened else { return 0 }
        let days = max(0, now.timeIntervalSince(last) / 86_400)
        return Double(max(meta.openCount, 1)) * pow(0.5, days / 7)
    }
}

extension Library {
    public func items(from projects: [DiscoveredProject]) -> [LibraryItem] {
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return projects.map { p in
            let m = meta(for: p.path)
            return LibraryItem(project: p, meta: m, categoryNames: m.categories.compactMap { names[$0] })
        }
    }

    /// 按优先级选择编辑器：本次指定 > 项目设置 > 全局默认。
    public func editor(for path: String, override: AppRef? = nil) -> AppRef? {
        override ?? meta(for: path).editor ?? preferences.editor
    }
}
