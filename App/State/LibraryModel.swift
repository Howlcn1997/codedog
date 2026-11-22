import AppKit
import CodedogCore
import SwiftUI
import Foundation
import Observation

/// 主窗口状态：用户数据、扫描结果、筛选与搜索。
@MainActor @Observable
final class LibraryModel {
    // 这几项是派生数据（items / visible）的来源，变化时清掉缓存
    private(set) var library = Library() { didSet { invalidateDerived() } }
    private(set) var projects: [DiscoveredProject] = [] { didSet { invalidateDerived() } }
    private(set) var isScanning = false
    private(set) var lastScan: Date?
    private(set) var aiIndex: [String: [ToolUsage]] = [:] { didSet { invalidateDerived() } }
    private(set) var running: [String: Set<AITool>] = [:] { didSet { invalidateDerived() } }
    private(set) var sizes: [String: SizeInfo] = SizeCache.load().sizes { didSet { invalidateDerived() } }
    private(set) var isMeasuring = false
    private(set) var availableUpdate: UpdateChecker.Release?
    private(set) var isCheckingUpdate = false
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
    /// 文件夹卡片缩放（⌘+ / ⌘- / ⌘0），按用户偏好记住
    var cardScale: Double = LibraryModel.storedCardScale {
        didSet { UserDefaults.standard.set(cardScale, forKey: "cardScale") }
    }
    static let cardScaleRange: ClosedRange<Double> = 0.7...1.6
    private static var storedCardScale: Double {
        let v = UserDefaults.standard.double(forKey: "cardScale")
        return v == 0 ? 1 : min(max(v, cardScaleRange.lowerBound), cardScaleRange.upperBound)
    }
    /// 正在查看详情的项目
    var detailID: String?
    /// 设置已从磁盘读入（含首次启动的自动配置）。之前 `library` 只是默认值，不能据此判断"没有扫描目录"。
    private(set) var isLoaded = false
    #if DEBUG
    /// 调试：主窗口按"没有扫描目录"显示引导页，只影响界面，不改设置文件。
    /// 启动时设 CODEDOG_DEBUG_NOROOTS=1，或在 CODEDOG_SNAPSHOT_ACTIONS 里用 noroots / noroots:off。
    var debugNoRoots = ProcessInfo.processInfo.environment["CODEDOG_DEBUG_NOROOTS"] == "1"
    #endif

    @ObservationIgnored private let store = LibraryStore()
    @ObservationIgnored private var watcher: FSEventsWatcher?
    @ObservationIgnored private var pendingEvents = Set<String>()
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var aiWatcher: FSEventsWatcher?
    @ObservationIgnored private var aiTask: Task<Void, Never>?
    @ObservationIgnored private var lastAIBuild = Date.distantPast
    /// 每个智能体会话跑在哪个终端里，续上时回到同一个终端
    @ObservationIgnored private var agentTerminals = AgentTerminals.load()

    // MARK: 派生数据

    /// items / visible 的缓存。每次读取都重新组装、过滤、排序全部项目，点一下卡片（改 selectedID、detailID）
    /// 整个项目库视图重算时要跑好几遍，打开详情面板明显变慢。
    @ObservationIgnored private var itemsCache: [ProjectItem]?
    @ObservationIgnored private var visibleCache: (key: VisibleKey, value: [(item: ProjectItem, match: SearchMatch)])?

    private struct VisibleKey: Equatable {
        var selection: SidebarSelection?
        var searchText: String
        var timeRange: TimeRange
        var pulse: Pulse?
        var sortOrder: SortOrder
    }

    private func invalidateDerived() {
        itemsCache = nil
        visibleCache = nil
    }

    var items: [ProjectItem] {
        // 先读一遍来源属性，保证观察关系照常建立（缓存命中时也一样）
        let lib = library, ps = projects, ai = aiIndex, run = running, sz = sizes
        if let itemsCache { return itemsCache }
        let value = lib.items(from: ps, tools: ai, running: run, sizes: sz)
        itemsCache = value
        return value
    }

    func item(_ id: String?) -> ProjectItem? {
        guard let id, let p = projects.first(where: { $0.path == id }) else { return nil }
        return library.items(from: [p], tools: aiIndex, running: running, sizes: sizes).first
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
        case .color(let c): return all.filter { !$0.meta.hidden && $0.meta.color == c }
        }
    }

    /// 最终展示的项目与搜索命中（按来源数据和筛选条件缓存）。
    var visible: [(item: ProjectItem, match: SearchMatch)] {
        let key = VisibleKey(selection: selection, searchText: searchText, timeRange: timeRange, pulse: pulse, sortOrder: sortOrder)
        _ = items   // 建立对来源数据的观察
        if let visibleCache, visibleCache.key == key { return visibleCache.value }
        let value = computeVisible()
        visibleCache = (key, value)
        return value
    }

    private func computeVisible() -> [(item: ProjectItem, match: SearchMatch)] {
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
        case .all: String(localized: "全部项目")
        case .smart(let f): f.title
        case .category(let id): library.categories.first { $0.id == id }?.name ?? String(localized: "分类")
        case .kind(let k): k.displayName
        case .tool(let t): t.displayName
        case .color(let c): FolderPalette.name(c)
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
        case .color(let c): return all.filter { !$0.meta.hidden && $0.meta.color == c }.count
        }
    }

    /// 用过的文件夹颜色（按调色板顺序）。
    var colorsPresent: [String] {
        let used = Set(items.filter { !$0.meta.hidden }.compactMap(\.meta.color))
        return FolderPalette.all.map(\.id).filter(used.contains)
    }

    /// 出现过的项目类型（按固定顺序）。
    var kindsPresent: [ProjectKind] {
        let present = Set(projects.map(\.kind))
        return ProjectKind.allCases.filter(present.contains)
    }

    func count(_ p: Pulse) -> Int { scopedItems.filter { p.contains($0) }.count }

    /// 调整卡片缩放：+1 放大一档，-1 缩小一档，0 恢复默认。
    func zoomCards(_ step: Int) {
        let next = step == 0 ? 1 : (cardScale + Double(step) * 0.1)
        let clamped = (min(max(next, Self.cardScaleRange.lowerBound), Self.cardScaleRange.upperBound) * 10).rounded() / 10
        guard clamped != cardScale || step == 0 else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { cardScale = clamped }
        toast = String(localized: "卡片大小 \(Int((clamped * 100).rounded()))%")
    }

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
        isLoaded = true
        startWatching()
        startAIWatching()
        await rescan()
        Task { await self.pollRunning() }
    }

    // MARK: 占用空间

    /// 后台统计占用空间：缺失或超过 24 小时的才重新统计。`force` 时全部重算。
    func measureSizes(force: Bool = false, only: [String]? = nil) async {
        guard !isMeasuring else { return }
        let stale = Date.now.addingTimeInterval(-24 * 3600)
        let targets = (only ?? projects.map(\.path)).filter { p in force || only != nil || (sizes[p]?.measuredAt ?? .distantPast) < stale }
        guard !targets.isEmpty else { return }
        isMeasuring = true
        defer { isMeasuring = false }
        let results = await DiskUsage.measureAll(targets)
        sizes.merge(results) { $1 }
        let known = Set(projects.map(\.path))
        let snapshot = SizeCache(sizes: sizes.filter { known.contains($0.key) })
        Task.detached(priority: .background) { try? snapshot.save() }
    }

    /// 移到废纸篓并重新统计相关项目。返回提示文案。
    func clean(_ items: [CleanupItem]) async {
        let result = await Task.detached(priority: .userInitiated) { DependencyCleaner.clean(items) }.value
        let projects = Array(Set(items.map(\.project)))
        await measureSizes(only: projects)
        let freed = ByteCountFormatter.string(fromByteCount: result.freed, countStyle: .file)
        if result.failures.isEmpty {
            toast = String(localized: "已移到废纸篓，释放 \(freed)")
        } else {
            errorMessage = String(localized: "释放了 \(freed)，但有 \(result.failures.count) 个目录没有清理：\n") + result.failures.prefix(5).map { "· \($0.1)" }.joined(separator: "\n")
        }
    }

    // MARK: 更新

    /// 检查新版本。自动检查每天最多一次；手动检查总会执行并给出结果提示。
    func checkForUpdates(manual: Bool = false) async {
        let prefs = library.preferences
        if !manual {
            guard prefs.checkForUpdates else { return }
            if let last = prefs.lastUpdateCheck, Date.now.timeIntervalSince(last) < 24 * 3600 { return }
        }
        isCheckingUpdate = true
        defer { isCheckingUpdate = false }
        let release = await UpdateChecker.latest()
        setPreferences { $0.lastUpdateCheck = .now }
        if let release, UpdateChecker.isNewer(release.version, than: Codedog.version) {
            availableUpdate = release
            if manual { toast = String(localized: "发现新版本 \(release.version)") }
        } else if manual {
            toast = release == nil ? String(localized: "暂时无法连接 GitHub，请稍后再试") : String(localized: "已经是最新版本（\(Codedog.version)）")
        }
    }

    // MARK: 新建项目

    func createProject(name: String, in parent: String, gitInit: Bool, readme: Bool) async -> Bool {
        do {
            let path = try await ProjectCreator.create(name: name, in: parent, gitInit: gitInit, readme: readme)
            let inRoot = library.scanRoots.contains { path.hasPrefix($0 + "/") }
            if !inRoot { update { $0.updateMeta(path) { $0.pinned = true } } }
            if let p = await DiscoveryService.inspect(path: path) {
                projects.removeAll { $0.path == path }
                projects.append(p)
                saveCache()
            }
            withAnimation { detailID = path }
            toast = String(localized: "已创建 \(name)")
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: AI 工具

    func refreshAI() async {
        lastAIBuild = .now
        aiIndex = await AIIndex.build(projects: projects.map(\.path))
        await updateRunning()
    }

    /// 每 10 秒刷新一次运行中的智能体（读取进程表，开销很小）。
    private func pollRunning() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10))
            await updateRunning()
        }
    }

    /// 读一次进程表：更新"运行中"，顺便记下每个智能体所在的终端。
    private func updateRunning() async {
        let procs = await Task.detached { RunningAgents.processes() }.value
        let now = procs.reduce(into: [String: Set<AITool>]()) { $0[$1.cwd, default: []].insert($1.tool) }
        if now != running { running = now }
        if agentTerminals.record(procs) {
            let snapshot = agentTerminals
            Task.detached { snapshot.save() }
        }
    }

    /// 续上这个会话该用的终端：记录里有就用记录的（例如上次在 Warp 里跑的就回 Warp），否则用偏好设置里的终端。
    func terminal(for tool: AITool, session: SessionSummary?, project: String) -> AppRef? {
        if let id = agentTerminals.terminal(tool: tool, cwd: session?.cwd, project: project),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return AppRef(bundleID: id, name: KnownApps.displayName(bundleID: id, fallback: url.deletingPathExtension().lastPathComponent))
        }
        return library.preferences.terminal
    }

    /// 续上会话的按钮提示，例如"在 Codex 中打开"、"在 Warp 里用 Claude Code 接着上次的会话"。
    func resumeHelp(_ item: ProjectItem, tool: AITool) -> String {
        let session = item.tools.first { $0.tool == tool }?.lastSession
        if tool == .codex && CodexDesktop.shouldOpen(session) { return String(localized: "在 Codex 中打开") }
        let name = terminal(for: tool, session: session, project: item.id)?.name ?? KnownApps.defaultTerminal.name
        return String(localized: "在\(name)里用 \(tool.displayName) 接着上次的会话")
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
            if legacy != nil { toast = String(localized: "已从旧版 codedog 导入收藏、分类和备注") }
        } catch {
            errorMessage = String(localized: "保存设置失败：\(error.localizedDescription)")
        }
    }

    // MARK: 扫描

    /// 重新扫描。默认增量（指纹没变的项目复用缓存）；`full` 时全部重新检测。
    func rescan(full: Bool = false) async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        let found = await DiscoveryService.scan(roots: library.scanRoots, pinned: library.pinnedPaths, previous: full ? [] : projects)
        projects = found
        lastScan = .now
        saveCache()
        await refreshAI()
        Task { await measureSizes() }
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
            do { library = try await store.mutate(body) } catch { errorMessage = String(localized: "保存失败：\(error.localizedDescription)") }
        }
    }

    func toggleFavorite(_ path: String) { update { $0.updateMeta(path) { $0.favorite.toggle() } } }
    func setHidden(_ path: String, _ hidden: Bool) { update { $0.updateMeta(path) { $0.hidden = hidden } } }
    func setNotes(_ path: String, _ notes: String) { update { $0.updateMeta(path) { $0.notes = notes } } }
    func setColor(_ path: String, _ color: String?) {
        update { $0.updateMeta(path) { $0.color = color } }
        // 当前正在看的颜色分类空了，就回到全部项目
        if case .color(let c) = selection, count(.color(c)) == 0 { selection = .all }
    }
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
                // Codex 桌面版发起的会话回桌面版（没有会话时在项目里新开）；命令行发起的和 Claude Code 在终端里续上，
                // 终端优先用这个会话上次所在的那个（Warp、iTerm2…），没记录才用偏好设置里的
                case .resume(.codex) where CodexDesktop.shouldOpen(lastSession):
                    try await CodexDesktop.open(sessionID: lastSession?.id, path: path)
                case .resumeSession(let session) where session.tool == .codex && CodexDesktop.shouldOpen(session):
                    try await CodexDesktop.open(sessionID: session.id, path: path)
                case .newSession(.codex) where CodexDesktop.isInstalled:
                    try await CodexDesktop.open(sessionID: nil, path: path)
                case .resume(let tool):
                    if let cmd = AgentLauncher.resumeCommand(tool: tool, sessionID: lastSession?.id) {
                        try AgentLauncher.run(cmd, in: lastSession?.cwd ?? path, terminal: terminal(for: tool, session: lastSession, project: path))
                    }
                case .resumeSession(let session):
                    if let cmd = AgentLauncher.resumeCommand(tool: session.tool, sessionID: session.id) {
                        try AgentLauncher.run(cmd, in: session.cwd ?? path, terminal: terminal(for: session.tool, session: session, project: path))
                    }
                case .newSession(let tool):
                    if let cmd = AgentLauncher.resumeCommand(tool: tool, sessionID: nil) {
                        try AgentLauncher.run(cmd, in: path, terminal: terminal(for: tool, session: nil, project: path))
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
        toast = String(localized: "已复制路径")
    }
}
