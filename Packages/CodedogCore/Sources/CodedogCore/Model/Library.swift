import Foundation

/// 对任意本机应用的引用（编辑器、终端）。
public struct AppRef: Codable, Sendable, Hashable {
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    private enum CodingKeys: String, CodingKey { case bundleID, name }

    /// 读取旧数据时把已知 App 的名称统一成简称（如 "Visual Studio Code" → "VS Code"）。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        name = KnownApps.displayName(bundleID: bundleID, fallback: try c.decode(String.self, forKey: .name))
    }
}

public struct Category: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var color: String?

    public init(id: UUID = UUID(), name: String, color: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
    }
}

/// 用户为某个项目添加的元数据（唯一需要持久保护的数据）。
public struct ProjectMeta: Codable, Sendable, Hashable {
    public var favorite = false
    public var hidden = false
    public var categories: [UUID] = []
    public var notes = ""
    public var editor: AppRef?
    public var lastOpened: Date?
    public var openCount = 0
    /// 用户手动添加（不在扫描目录内）的项目。
    public var pinned = false
    /// 文件夹颜色（调色板 id，如 "blue"）；nil 为默认的灰色。
    public var color: String?

    public init() {}

    public var isEmpty: Bool { self == ProjectMeta() }
}

public struct Preferences: Codable, Sendable, Hashable {
    public var editor: AppRef?
    public var terminal: AppRef?
    public var launcherShortcut: String = "cmd+shift+space"
    public var menuBarResident = true
    public var checkForUpdates = true
    public var lastUpdateCheck: Date?
    /// 外观："system" 跟随系统、"light" 亮色、"dark" 暗色。
    public var appearance = "system"

    public init() {}

    enum CodingKeys: String, CodingKey { case editor, terminal, launcherShortcut, menuBarResident, checkForUpdates, lastUpdateCheck, appearance }

    // 新增字段对旧 library.json 缺省兼容
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        editor = try c.decodeIfPresent(AppRef.self, forKey: .editor)
        terminal = try c.decodeIfPresent(AppRef.self, forKey: .terminal)
        launcherShortcut = try c.decodeIfPresent(String.self, forKey: .launcherShortcut) ?? "cmd+shift+space"
        menuBarResident = try c.decodeIfPresent(Bool.self, forKey: .menuBarResident) ?? true
        checkForUpdates = try c.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? true
        lastUpdateCheck = try c.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? "system"
    }
}

/// `library.json`：用户数据。
public struct Library: Codable, Sendable, Hashable {
    public static let currentVersion = 2

    public var version = Library.currentVersion
    public var scanRoots: [String] = []
    public var categories: [Category] = []
    public var meta: [String: ProjectMeta] = [:]
    public var preferences = Preferences()
    public var migratedLegacy = false

    public init() {}

    public func meta(for path: String) -> ProjectMeta { meta[path] ?? ProjectMeta() }

    public mutating func updateMeta(_ path: String, _ body: (inout ProjectMeta) -> Void) {
        var m = meta(for: path)
        body(&m)
        meta[path] = m.isEmpty ? nil : m
    }
}
