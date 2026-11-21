import Foundation

/// 扫描结果 + 用户元数据的组合视图，App 与 CLI 共用。
public struct ProjectItem: Sendable, Hashable, Identifiable {
    public var project: DiscoveredProject
    public var meta: ProjectMeta
    public var categoryNames: [String]
    /// 关联的 AI / 编辑工具，按最近使用排序。
    public var tools: [ToolUsage]
    /// 正在这个项目里运行的智能体。
    public var running: Set<AITool>

    public var id: String { project.path }

    public init(project: DiscoveredProject, meta: ProjectMeta, categoryNames: [String], tools: [ToolUsage] = [], running: Set<AITool> = []) {
        self.project = project
        self.meta = meta
        self.categoryNames = categoryNames
        self.tools = tools
        self.running = running
    }

    /// 有智能体答完在等你回复（48 小时内）。
    public var waiting: Bool {
        tools.contains { $0.waiting && ($0.lastAt.map { Date.now.timeIntervalSince($0) < 48 * 3600 } ?? false) }
    }

    /// 最近一次可续上的智能体会话。
    public var lastAgent: ToolUsage? { tools.first { $0.tool.isAgent && $0.lastSession != nil } }

    /// 热力图数据：提交与 AI 回复按天合并。
    public var commitDays: [String: Int] { project.git?.commitDays ?? [:] }
    public var aiDays: [String: Int] {
        tools.reduce(into: [String: Int]()) { $0.merge($1.days, uniquingKeysWith: +) }
    }

    /// 所有 AI 工具的 token 用量，按模型汇总。
    public var tokensByModel: [String: TokenUsage] {
        tools.reduce(into: [String: TokenUsage]()) { acc, t in
            for (m, u) in t.tokens { acc[m, default: TokenUsage()] += u }
        }
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
        // 忽略未来时间（时钟漂移、错误的提交日期）
        let limit = Date.now.addingTimeInterval(3600)
        return ([meta.lastOpened, project.git?.lastCommitAt, project.modifiedAt] + tools.map(\.lastAt)).compactMap { $0 }.filter { $0 <= limit }.max()
    }

    /// 常用度：打开次数按距今天数衰减（半衰期约 7 天），用于启动器排序。
    public func frecency(now: Date = .now) -> Double {
        guard let last = meta.lastOpened else { return 0 }
        let days = max(0, now.timeIntervalSince(last) / 86_400)
        return Double(max(meta.openCount, 1)) * pow(0.5, days / 7)
    }
}

extension Library {
    public func items(from projects: [DiscoveredProject], tools: [String: [ToolUsage]] = [:], running: [String: Set<AITool>] = [:]) -> [ProjectItem] {
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return projects.map { p in
            let m = meta(for: p.path)
            return ProjectItem(project: p, meta: m, categoryNames: m.categories.compactMap { names[$0] },
                               tools: tools[p.path] ?? [], running: RunningAgents.tools(for: p.path, in: running))
        }
    }

    /// 按优先级选择编辑器：本次指定 > 项目设置 > 全局默认。
    public func editor(for path: String, override: AppRef? = nil) -> AppRef? {
        override ?? meta(for: path).editor ?? preferences.editor
    }
}
