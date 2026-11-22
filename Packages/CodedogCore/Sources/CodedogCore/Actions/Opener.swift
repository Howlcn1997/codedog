import AppKit
import Foundation

public enum OpenError: LocalizedError, Sendable {
    case appNotInstalled(String)
    case noEditor
    case noRepository
    case missingPath(String)

    public var errorDescription: String? {
        switch self {
        case .appNotInstalled(let name): String(localized: "没有找到 \(name)，它可能已被卸载。")
        case .noEditor: String(localized: "还没有可用的编辑器，请在设置里选择一个。")
        case .noRepository: String(localized: "这个项目没有远程仓库地址。")
        case .missingPath(let p): String(localized: "项目目录不存在：\(p)")
        }
    }
}

/// 打开项目：编辑器、终端、访达、仓库网页。App 与 CLI 共用。
public enum Opener {
    public static func appURL(_ app: AppRef) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
    }

    public static func isInstalled(_ app: AppRef) -> Bool { appURL(app) != nil }

    public static var installedEditors: [AppRef] { KnownApps.editors.filter(isInstalled) }
    public static var installedTerminals: [AppRef] { KnownApps.terminals.filter(isInstalled) }

    /// 根据 .app 路径构造引用（用户在设置里选择任意 App 时使用）。
    public static func appRef(at url: URL) -> AppRef? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return AppRef(bundleID: id, name: KnownApps.displayName(bundleID: id, fallback: name))
    }

    public static func open(_ path: String, with app: AppRef) async throws {
        guard FileManager.default.fileExists(atPath: path) else { throw OpenError.missingPath(path) }
        guard let appURL = appURL(app) else { throw OpenError.appNotInstalled(app.name) }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try await NSWorkspace.shared.open([URL(filePath: path)], withApplicationAt: appURL, configuration: config)
    }

    /// 用编辑器打开；未指定时退回到第一个已安装的常见编辑器。
    public static func openInEditor(_ path: String, editor: AppRef?) async throws {
        guard let app = editor ?? installedEditors.first else { throw OpenError.noEditor }
        try await open(path, with: app)
    }

    public static func openInTerminal(_ path: String, terminal: AppRef?) async throws {
        let app = terminal ?? KnownApps.defaultTerminal
        guard FileManager.default.fileExists(atPath: path) else { throw OpenError.missingPath(path) }
        if app.bundleID == "dev.warp.Warp-Stable" {
            var c = URLComponents(string: "warp://action/new_tab")!
            c.queryItems = [URLQueryItem(name: "path", value: path)]
            guard let url = c.url else { return }
            NSWorkspace.shared.open(url)
            return
        }
        try await open(path, with: app)
    }

    public static func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
    }

    public static func openRepository(_ git: GitInfo?) throws {
        guard let url = git?.webURL else { throw OpenError.noRepository }
        NSWorkspace.shared.open(url)
    }

    /// 为一组项目生成 `.code-workspace` 并用编辑器打开（"分类一起打开"）。
    public static func openTogether(name: String, paths: [String], editor: AppRef?) async throws {
        guard let app = editor ?? installedEditors.first(where: { KnownApps.workspaceCapable.contains($0.bundleID) }) else { throw OpenError.noEditor }
        let dir = Codedog.dataDirectory.appending(path: "workspaces", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: #"[/:\\]"#, with: "-", options: .regularExpression)
        let file = dir.appending(path: "\(safe).code-workspace")
        let json: [String: Any] = ["folders": paths.map { ["path": $0] }, "settings": [:]]
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .withoutEscapingSlashes]).write(to: file, options: .atomic)
        try await open(file.path(percentEncoded: false), with: app)
    }
}
