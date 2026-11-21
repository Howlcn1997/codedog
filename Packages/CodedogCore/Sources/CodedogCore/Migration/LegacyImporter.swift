import Foundation

/// 从旧版 Electron codedog 的 `projects.json` 一次性迁移用户数据。
/// 只迁移有价值的部分：收藏、分组与标签（转为分类）、备注、归档（转为隐藏）、项目编辑器、最近打开、全局偏好。
public enum LegacyImporter {
    struct Legacy: Decodable {
        struct Group: Decodable { var id: String; var name: String }
        struct Project: Decodable {
            var name: String?
            var path: String
            var group: String?
            var tags: [String]?
            var notes: String?
            var favorite: Bool?
            var archived: Bool?
            var lastOpened: Double?
            var ide: String?
        }
        var root: String?
        var ide: String?
        var terminal: String?
        var launcherShortcut: String?
        var groups: [Group]?
        var projects: [Project]?
    }

    static let builtinGroups = ["company": "公司项目", "personal": "个人项目", "temporary": "临时项目"]

    /// 把旧数据合并进 library。`suggestedRoots` 用于判断哪些项目需要标记为"手动添加"。
    public static func migrate(data: Data, into library: inout Library, suggestedRoots: [String]) throws {
        let legacy = try JSONDecoder().decode(Legacy.self, from: data)

        var roots = library.scanRoots
        if let root = legacy.root, !root.isEmpty {
            let r = FolderScanner.normalize(root)
            if !roots.contains(r) { roots.append(r) }
        }
        for r in suggestedRoots where !roots.contains(r) { roots.append(r) }
        library.scanRoots = roots

        let customGroups = Dictionary((legacy.groups ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        func categoryID(_ name: String) -> UUID {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if let existing = library.categories.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) { return existing.id }
            let c = Category(name: trimmed)
            library.categories.append(c)
            return c.id
        }

        for p in legacy.projects ?? [] {
            let path = FolderScanner.normalize(p.path)
            var names: [String] = []
            if let g = p.group, let name = builtinGroups[g] ?? customGroups[g] { names.append(name) }
            names += (p.tags ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let ids = names.map(categoryID)
            let inRoot = roots.contains { path.hasPrefix($0 + "/") || path == $0 }

            library.updateMeta(path) { m in
                m.favorite = m.favorite || (p.favorite ?? false)
                m.hidden = m.hidden || (p.archived ?? false)
                for id in ids where !m.categories.contains(id) { m.categories.append(id) }
                if m.notes.isEmpty, let n = p.notes { m.notes = n }
                if m.editor == nil, let ide = p.ide, !ide.isEmpty { m.editor = KnownApps.editor(named: ide) }
                if m.lastOpened == nil, let ms = p.lastOpened, ms > 0 { m.lastOpened = Date(timeIntervalSince1970: ms / 1000) }
                if !inRoot { m.pinned = true }
            }
        }

        if library.preferences.editor == nil, let ide = legacy.ide { library.preferences.editor = KnownApps.editor(named: ide) }
        if library.preferences.terminal == nil, legacy.terminal == "warp" {
            library.preferences.terminal = KnownApps.terminals.first { $0.name == "Warp" }
        }
        if let s = legacy.launcherShortcut, !s.isEmpty {
            library.preferences.launcherShortcut = s
                .replacingOccurrences(of: "CommandOrControl", with: "cmd")
                .replacingOccurrences(of: "Command", with: "cmd")
                .replacingOccurrences(of: "Control", with: "ctrl")
                .replacingOccurrences(of: "Alt", with: "option")
                .lowercased()
        }
        library.migratedLegacy = true
    }
}
