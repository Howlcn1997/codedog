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
    var errorMessage: String?
    var toast: String?

    // 导航与筛选
    var selection: SidebarSelection? = .all
    var searchText = ""
    var timeRange: TimeRange = .all
    var bucketFilter: ActivityBucket?
    var sortOrder: SortOrder = .activity
    var viewMode: ViewMode = .grid
    var selectedID: String?
    var showInspector = false

    @ObservationIgnored private let store = LibraryStore()
    @ObservationIgnored private var watcher: FSEventsWatcher?
    @ObservationIgnored private var pendingEvents = Set<String>()
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    // MARK: 派生数据

    var items: [ProjectItem] { library.items(from: projects) }

    var selectedItem: ProjectItem? {
        guard let selectedID, let p = projects.first(where: { $0.path == selectedID }) else { return nil }
        return library.items(from: [p]).first
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
        }
    }

    /// 最终展示的项目与搜索命中。
    var visible: [(item: ProjectItem, match: SearchMatch)] {
        var base = scopedItems
        if let bucket = bucketFilter {
            base = base.filter { ($0.lastActivity ?? .distantPast) >= bucket.start && ($0.lastActivity ?? .distantPast) < bucket.end }
        } else if let cutoff = timeRange.cutoff {
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
        }
    }

    /// 出现过的项目类型（按固定顺序）。
    var kindsPresent: [ProjectKind] {
        let present = Set(projects.map(\.kind))
        return ProjectKind.allCases.filter(present.contains)
    }

    /// 活跃度柱状图：更早 + 过去 11 个月 + 本月（不含本周）+ 本周。
    var activityBuckets: [ActivityBucket] {
        let cal = Calendar.current
        let now = Date.now
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? now
        var edges: [(String, Date, Date)] = []
        let oldest = cal.date(byAdding: .month, value: -11, to: monthStart)!
        edges.append(("更早", .distantPast, oldest))
        for i in stride(from: 11, through: 1, by: -1) {
            let s = cal.date(byAdding: .month, value: -i, to: monthStart)!
            let e = cal.date(byAdding: .month, value: 1, to: s)!
            let m = cal.component(.month, from: s)
            let label = m == 1 ? "\(cal.component(.year, from: s))年1月" : "\(m)月"
            edges.append((label, s, e))
        }
        // 本周跨月时，本周从月初算起，避免与上月重叠。
        let thisWeek = max(weekStart, monthStart)
        edges.append(("本月", monthStart, thisWeek))
        edges.append(("本周", thisWeek, .distantFuture))
        let dates = scopedItems.map { $0.lastActivity ?? .distantPast }
        return edges.enumerated().map { i, e in
            ActivityBucket(id: i, label: e.0, start: e.1, end: e.2, count: dates.filter { $0 >= e.1 && $0 < e.2 }.count)
        }
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
        startWatching()
        await rescan()
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
        body(&library)
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
        Task {
            do {
                switch action {
                case .editor: try await Opener.openInEditor(path, editor: editor)
                case .terminal: try await Opener.openInTerminal(path, terminal: prefs.terminal)
                case .finder: Opener.revealInFinder(path)
                case .repository: try Opener.openRepository(item.project.git)
                }
                if case .editor = action { update { $0.recordOpen(path) } }
                if case .terminal = action { update { $0.recordOpen(path) } }
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
