import Foundation

/// 对任意本机应用的引用（编辑器、终端）。
public struct AppRef: Codable, Sendable, Hashable {
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
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

    public init() {}

    public var isEmpty: Bool { self == ProjectMeta() }
}

public struct Preferences: Codable, Sendable, Hashable {
    public var editor: AppRef?
    public var terminal: AppRef?
    public var launcherShortcut: String = "cmd+shift+space"
    public var menuBarResident = true

    public init() {}
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
