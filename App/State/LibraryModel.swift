import AppKit
import CodedogCore
import Foundation
import Observation

/// 主窗口状态：用户数据、扫描结果、筛选与搜索。
@MainActor @Observable
final class LibraryModel {
    private(set) var library = Library()
    private(set) var projects: [DiscoveredProject] = []
    private(set) var isScanning = false
    private(set) var lastScan: Date?
    private(set) var aiIndex: [String: [ToolUsage]] = [:]
    private(set) var running: [String: Set<AITool>] = [:]
    var errorMessage: String?
    var toast: String?

    // 导航与筛选
    var selection: SidebarSelection? = .all
    var searchText = ""
    var timeRange: TimeRange = .all
    var pulse: Pulse?
    var sortOrder: SortOrder = .activity
    var viewMode: ViewMode = .grid
    var selectedID: String?
    /// 正在查看详情的项目
    var detailID: String?

    @ObservationIgnored private let store = LibraryStore()
    @ObservationIgnored private var watcher: FSEventsWatcher?
    @ObservationIgnored private var pendingEvents = Set<String>()
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var aiWatcher: FSEventsWatcher?
    @ObservationIgnored private var aiTask: Task<Void, Never>?
    @ObservationIgnored private var lastAIBuild = Date.distantPast

    // MARK: 派生数据

    var items: [ProjectItem] { library.items(from: projects, tools: aiIndex, running: running) }

    func item(_ id: String?) -> ProjectItem? {
        guard let id, let p = projects.first(where: { $0.path == id }) else { return nil }
        return library.items(from: [p], tools: aiIndex, running: running).first
    }

    var selectedItem: ProjectItem? { item(selectedID) }
    var detailItem: ProjectItem? { item(detailID) }

    /// 出现过的 AI 工具（按固定顺序）。
    var toolsPresent: [AITool] {
        let present = Set(aiIndex.values.flatMap { $0.map(\.tool) })
        return AITool.allCases.filter(present.contains)
    }

    /// 当前侧栏选择下的项目（不含时间与搜索筛选）。
    var scopedItems: [ProjectItem] {
        let all = items
        switch selection ?? .all {
        case .all: return all.filter { !$0.meta.hidden }
        case .smart(.hidden): return all.filter { $0.meta.hidden }
        case .smart(let f): return all.filter { !$0.meta.hidden && f.contains($0) }
        case .category(let id): return all.filter { !$0.meta.hidden && $0.meta.categories.contains(id) }
        case .kind(let k): return all.filter { !$0.meta.hidden && $0.project.kind == k }
        case .tool(let t): return all.filter { !$0.meta.hidden && $0.tools.contains { $0.tool == t } }
        }
    }

    /// 最终展示的项目与搜索命中。
    var visible: [(item: ProjectItem, match: SearchMatch)] {
        var base = scopedItems
        if let pulse { base = base.filter { pulse.contains($0) } }
        if let cutoff = timeRange.cutoff {
            base = base.filter { ($0.lastActivity ?? .distantPast) >= cutoff }
        }
        let order = sortOrder
        return ProjectSearch.search(base, query: searchText, document: \.searchDocument, by: order.areInIncreasingOrder)
    }

    var title: String {
        switch selection ?? .all {
        case .all: "全部项目"
        case .smart(let f): f.title
        case .category(let id): library.categories.first { $0.id == id }?.name ?? "分类"
        case .kind(let k): k.displayName
        case .tool(let t): t.displayName
        }
    }

    func count(_ s: SidebarSelection) -> Int {
        let all = items
        switch s {
        case .all: return all.filter { !$0.meta.hidden }.count
        case .smart(.hidden): return all.filter { $0.meta.hidden }.count
        case .smart(let f): return all.filter { !$0.meta.hidden && f.contains($0) }.count
        case .category(let id): return all.filter { !$0.meta.hidden && $0.meta.categories.contains(id) }.count
        case .kind(let k): return all.filter { !$0.meta.hidden && $0.project.kind == k }.count
        case .tool(let t): return all.filter { !$0.meta.hidden && $0.tools.contains { $0.tool == t } }.count
        }
    }

    /// 出现过的项目类型（按固定顺序）。
    var kindsPresent: [ProjectKind] {
        let present = Set(projects.map(\.kind))
        return ProjectKind.allCases.filter(present.contains)
    }

    func count(_ p: Pulse) -> Int { scopedItems.filter { p.contains($0) }.count }

    // MARK: 启动

    func start() async {
        guard !started else { return }
        started = true
        library = await store.reload()
        let cache = ProjectCache.load()
        projects = cache.projects
        lastScan = cache.lastScan

        if !library.migratedLegacy && library.scanRoots.isEmpty {
            await firstRunSetup()
        }
        startWatching()
        startAIWatching()
        await rescan()
        Task { await self.pollRunning() }
    }

    // MARK: AI 工具

    func refreshAI() async {
        lastAIBuild = .now
        aiIndex = await AIIndex.build(projects: projects.map(\.path))
        running = await Task.detached { RunningAgents.scan() }.value
    }

    /// 每 10 秒刷新一次运行中的智能体（读取进程表，开销很小）。
    private func pollRunning() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10))
            let now = await Task.detached { RunningAgents.scan() }.value
            if now != running { running = now }
        }
    }

    /// AI 日志目录变化时重建索引（至少间隔 15 秒，按文件缓存，代价很小）。
    private func startAIWatching() {
        let dirs = ([NSHomeDirectory() + "/.claude/projects", NSHomeDirectory() + "/.codex/sessions"])
            .filter { FileManager.default.fileExists(atPath: $0) }
        aiWatcher = FSEventsWatcher(paths: dirs, latency: 3) { [weak self] _ in
            Task { @MainActor in self?.scheduleAIRefresh() }
        }
    }

    private func scheduleAIRefresh() {
        guard aiTask == nil else { return }
        let wait = max(0, 15 - Date.now.timeIntervalSince(lastAIBuild))
        aiTask = Task {
            try? await Task.sleep(for: .seconds(wait))
            await refreshAI()
            aiTask = nil
        }
    }

    private func firstRunSetup() async {
        let suggested = FolderScanner.suggestedRoots()
        let legacy = try? Data(contentsOf: Codedog.legacyURL)
        do {
            library = try await store.mutate { lib in
                if let legacy { try? LegacyImporter.migrate(data: legacy, into: &lib, suggestedRoots: suggested) }
                if lib.scanRoots.isEmpty { lib.scanRoots = suggested }
                lib.migratedLegacy = true
            }
            if legacy != nil { toast = "已从旧版 codedog 导入收藏、分类和备注" }
        } catch {
            errorMessage = "保存设置失败：\(error.localizedDescription)"
        }
    }

    // MARK: 扫描

    func rescan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        let found = await DiscoveryService.scan(roots: library.scanRoots, pinned: library.pinnedPaths)
        projects = found
        lastScan = .now
        saveCache()
        await refreshAI()
        if let id = selectedID, !found.contains(where: { $0.path == id }) { selectedID = nil }
    }

    private func saveCache() {
        let cache = ProjectCache(projects: projects, lastScan: lastScan)
        Task.detached(priority: .background) { try? cache.save() }
    }

    private func startWatching() {
        watcher?.stop()
        let paths = library.scanRoots + library.pinnedPaths + [Codedog.dataDirectory.path(percentEncoded: false)]
        watcher = FSEventsWatcher(paths: paths) { [weak self] events in
            Task { @MainActor in self?.enqueue(events) }
        }
    }

    private func enqueue(_ events: [String]) {
        pendingEvents.formUnion(events)
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            await flush()
        }
    }

    private func flush() async {
        let events = Array(pendingEvents)
        pendingEvents.removeAll()
        let dataDir = Codedog.dataDirectory.path(percentEncoded: false)
        if events.contains(where: { $0.hasSuffix("/library.json") && $0.hasPrefix(dataDir) }) {
            library = await store.reload()   // CLI 等外部修改
        }
        let projectEvents = events.filter { !$0.hasPrefix(dataDir) }
        guard !projectEvents.isEmpty, !isScanning else { return }

        let known = Set(projects.map(\.path))
        if let affected = DiscoveryService.affectedProjects(events: projectEvents, projects: known, roots: library.scanRoots) {
            guard !affected.isEmpty else { return }
            let updated = await DiscoveryService.inspectAll(Array(affected))
            let byPath = Dictionary(updated.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
            projects = projects.compactMap { p in affected.contains(p.path) ? byPath[p.path] : p }
        } else {
            // 目录结构变化：重新发现，只检测新增项目。
            let roots = library.scanRoots
            let paths = await Task.detached { FolderScanner.findProjects(in: roots) }.value + library.pinnedPaths
            let current = Set(paths)
            let added = paths.filter { !known.contains($0) }
            let inspected = await DiscoveryService.inspectAll(added)
            projects = projects.filter { current.contains($0.path) } + inspected
        }
        saveCache()
    }

    // MARK: 用户数据

    func update(_ body: @escaping @Sendable (inout Library) -> Void) {
        var next = library
        body(&next)
        // 没有实际变化就不触发观察与写盘（否则绑定回写会造成界面刷新死循环）
        guard next != library else { return }
        library = next
        Task {
            do { library = try await store.mutate(body) } catch { errorMessage = "保存失败：\(error.localizedDescription)" }
        }
    }

    func toggleFavorite(_ path: String) { update { $0.updateMeta(path) { $0.favorite.toggle() } } }
    func setHidden(_ path: String, _ hidden: Bool) { update { $0.updateMeta(path) { $0.hidden = hidden } } }
    func setNotes(_ path: String, _ notes: String) { update { $0.updateMeta(path) { $0.notes = notes } } }
    func setEditor(_ path: String, _ app: AppRef?) { update { $0.updateMeta(path) { $0.editor = app } } }

    func toggleCategory(_ path: String, _ id: UUID) {
        update { $0.updateMeta(path) { m in
            if let i = m.categories.firstIndex(of: id) { m.categories.remove(at: i) } else { m.categories.append(id) }
        } }
    }

    @discardableResult
    func createCategory(_ name: String, color: String? = nil) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !library.categories.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return nil }
        let c = CodedogCore.Category(name: trimmed, color: color)
        update { $0.categories.append(c) }
        return c.id
    }

    func renameCategory(_ id: UUID, _ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update { lib in if let i = lib.categories.firstIndex(where: { $0.id == id }) { lib.categories[i].name = trimmed } }
    }

    func setCategoryColor(_ id: UUID, _ color: String?) {
        update { lib in if let i = lib.categories.firstIndex(where: { $0.id == id }) { lib.categories[i].color = color } }
    }

    func deleteCategory(_ id: UUID) {
        if selection == .category(id) { selection = .all }
        update { lib in
            lib.categories.removeAll { $0.id == id }
            for path in lib.meta.keys { lib.updateMeta(path) { $0.categories.removeAll { $0 == id } } }
        }
    }

    func setScanRoots(_ roots: [String]) {
        let normalized = roots.map(FolderScanner.normalize).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        update { $0.scanRoots = normalized }
        startWatching()
        Task { await rescan() }
    }

    func addProjects(_ urls: [URL]) {
        let paths = urls.map { FolderScanner.normalize($0.path(percentEncoded: false)) }
        let roots = library.scanRoots
        update { lib in
            for p in paths where !roots.contains(where: { p.hasPrefix($0 + "/") || p == $0 }) {
                lib.updateMeta(p) { $0.pinned = true }
            }
        }
        startWatching()
        Task { await rescan() }
    }

    func setPreferences(_ body: @escaping @Sendable (inout Preferences) -> Void) {
        update { body(&$0.preferences) }
    }

    // MARK: 打开

    func editor(for item: ProjectItem) -> AppRef? {
        library.editor(for: item.id) ?? Opener.installedEditors.first
    }

    func open(_ item: ProjectItem, _ action: OpenAction = .editor(nil)) {
        let path = item.id
        let prefs = library.preferences
        let editor: AppRef?
        if case .editor(let override) = action { editor = library.editor(for: path, override: override) } else { editor = nil }
        let lastSession = item.tools.first { if case .resume(let t) = action { return $0.tool == t } else { return false } }?.lastSession
        Task {
            do {
                switch action {
                case .resume(let tool):
                    if let cmd = AgentLauncher.resumeCommand(tool: tool, sessionID: lastSession?.id) {
                        try AgentLauncher.run(cmd, in: lastSession?.cwd ?? path, terminal: prefs.terminal)
                    }
                case .resumeSession(let session):
                    if let cmd = AgentLauncher.resumeCommand(tool: session.tool, sessionID: session.id) {
                        try AgentLauncher.run(cmd, in: session.cwd ?? path, terminal: prefs.terminal)
                    }
                case .newSession(let tool):
                    if let cmd = AgentLauncher.resumeCommand(tool: tool, sessionID: nil) {
                        try AgentLauncher.run(cmd, in: path, terminal: prefs.terminal)
                    }
                case .editor: try await Opener.openInEditor(path, editor: editor)
                case .terminal: try await Opener.openInTerminal(path, terminal: prefs.terminal)
                case .finder: Opener.revealInFinder(path)
                case .repository: try Opener.openRepository(item.project.git)
                }
                switch action {
                case .finder, .repository: break
                default: update { $0.recordOpen(path) }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func openTogether(category id: UUID) {
        guard let c = library.categories.first(where: { $0.id == id }) else { return }
        let paths = items.filter { $0.meta.categories.contains(id) && !$0.meta.hidden }.map(\.id)
        let editor = library.preferences.editor.flatMap { KnownApps.workspaceCapable.contains($0.bundleID) ? $0 : nil }
        Task {
            do { try await Opener.openTogether(name: c.name, paths: paths, editor: editor) } catch { errorMessage = error.localizedDescription }
        }
    }

    func copyPath(_ item: ProjectItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.id, forType: .string)
        toast = "已复制路径"
    }
}
