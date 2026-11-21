import Foundation

/// 一次性读取的库快照（CLI 使用；App 自己维护实时状态）。
public struct LibrarySnapshot: Sendable {
    public var library: Library
    public var items: [LibraryItem]

    /// 优先读缓存；缓存为空时现场扫描（不写缓存，避免与 App 竞争）。
    public static func load(store: LibraryStore = LibraryStore()) async -> LibrarySnapshot {
        let library = await store.reload()
        var projects = ProjectCache.load().projects
        if projects.isEmpty {
            let roots = library.scanRoots.isEmpty ? FolderScanner.suggestedRoots() : library.scanRoots
            projects = await DiscoveryService.scan(roots: roots, pinned: library.pinnedPaths)
        }
        return LibrarySnapshot(library: library, items: library.items(from: projects))
    }

    /// 默认排序：常用度 → 最近活动 → 名称。
    public static func defaultOrder(_ a: LibraryItem, _ b: LibraryItem) -> Bool {
        let fa = a.frecency(), fb = b.frecency()
        if fa != fb { return fa > fb }
        let la = a.lastActivity ?? .distantPast, lb = b.lastActivity ?? .distantPast
        if la != lb { return la > lb }
        return a.project.name.localizedStandardCompare(b.project.name) == .orderedAscending
    }
}

extension Library {
    public var pinnedPaths: [String] { meta.filter(\.value.pinned).map(\.key).sorted() }

    /// 记录一次打开。
    public mutating func recordOpen(_ path: String, at date: Date = .now) {
        updateMeta(path) {
            $0.lastOpened = date
            $0.openCount += 1
        }
    }
}
