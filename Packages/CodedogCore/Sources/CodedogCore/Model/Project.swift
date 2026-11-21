import Foundation

/// 技术栈。按识别优先级排列。
public enum TechStack: String, Codable, Sendable, CaseIterable, Hashable {
    case swift, typescript, javascript, go, python, rust, java, kotlin, ruby, php, dart, cpp, html

    public var displayName: String {
        switch self {
        case .swift: "Swift"
        case .typescript: "TypeScript"
        case .javascript: "JavaScript"
        case .go: "Go"
        case .python: "Python"
        case .rust: "Rust"
        case .java: "Java"
        case .kotlin: "Kotlin"
        case .ruby: "Ruby"
        case .php: "PHP"
        case .dart: "Dart"
        case .cpp: "C/C++"
        case .html: "HTML"
        }
    }
}

/// 项目类型（面向人的分类，而不是语言）。
public enum ProjectKind: String, Codable, Sendable, CaseIterable, Hashable {
    case web, app, service, tool, library, other

    public var displayName: String {
        switch self {
        case .web: "网页"
        case .app: "App"
        case .service: "后端服务"
        case .tool: "工具脚本"
        case .library: "库"
        case .other: "其他"
        }
    }
}

public struct GitInfo: Codable, Sendable, Hashable {
    public var branch: String?
    public var dirtyFiles: Int
    public var remote: String?
    public var lastCommitAt: Date?
    public var recentCommits: [String]

    public init(branch: String? = nil, dirtyFiles: Int = 0, remote: String? = nil, lastCommitAt: Date? = nil, recentCommits: [String] = []) {
        self.branch = branch
        self.dirtyFiles = dirtyFiles
        self.remote = remote
        self.lastCommitAt = lastCommitAt
        self.recentCommits = recentCommits
    }

    /// `git@host:a/b.git`、`ssh://git@host/a/b` → `https://host/a/b`
    public var webURL: URL? {
        guard var r = remote?.trimmingCharacters(in: .whitespaces), !r.isEmpty else { return nil }
        if r.hasPrefix("git@"), let colon = r.firstIndex(of: ":") {
            r = "https://" + r[r.index(r.startIndex, offsetBy: 4)..<colon] + "/" + r[r.index(after: colon)...]
        } else if r.hasPrefix("ssh://") {
            r = "https://" + r.dropFirst(6).split(separator: "@", maxSplits: 1).last!
        }
        if r.hasSuffix(".git") { r.removeLast(4) }
        guard r.hasPrefix("http") else { return nil }
        return URL(string: r)
    }
}

/// 扫描得到的项目（派生数据，可随时重建）。
public struct DiscoveredProject: Codable, Sendable, Hashable, Identifiable {
    /// 规范化后的绝对路径，同时作为主键。
    public var id: String { path }
    public var path: String
    public var name: String
    public var stacks: [TechStack]
    public var kind: ProjectKind
    public var markers: [String]
    public var description: String?
    public var readmeFile: String?
    /// README 正文前 32KB，用于全文搜索。
    public var readmeText: String?
    /// 依赖名（package.json、go.mod、requirements、pyproject、Cargo.toml），用于搜索。
    public var dependencies: [String]
    public var createdAt: Date?
    public var modifiedAt: Date?
    public var git: GitInfo?
    public var scannedAt: Date

    public init(path: String, name: String, stacks: [TechStack] = [], kind: ProjectKind = .other, markers: [String] = [], description: String? = nil, readmeFile: String? = nil, readmeText: String? = nil, dependencies: [String] = [], createdAt: Date? = nil, modifiedAt: Date? = nil, git: GitInfo? = nil, scannedAt: Date = .now) {
        self.path = path
        self.name = name
        self.stacks = stacks
        self.kind = kind
        self.markers = markers
        self.description = description
        self.readmeFile = readmeFile
        self.readmeText = readmeText
        self.dependencies = dependencies
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.git = git
        self.scannedAt = scannedAt
    }

    public var url: URL { URL(filePath: path, directoryHint: .isDirectory) }
    public var isGit: Bool { markers.contains(".git") }

    /// 最近一次可感知的活动时间：提交时间与文件修改时间取较晚者。
    public var lastActivity: Date? {
        [git?.lastCommitAt, modifiedAt].compactMap { $0 }.max()
    }
}
