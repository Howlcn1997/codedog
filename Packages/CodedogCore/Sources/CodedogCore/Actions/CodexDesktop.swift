import AppKit
import Foundation

/// Codex 桌面版（bundle id `com.openai.codex`，安装后可能叫 ChatGPT.app 或 Codex.app）。
/// 通过它注册的 `codex://` 深链接跳转：
/// - `codex://threads/<会话ID>`：打开已有会话（CLI 与桌面版共用 ~/.codex/sessions，会话互通）
/// - `codex://threads/new?path=<目录>`：在该目录对应的项目里新开会话，项目已存在时直接选中它
public enum CodexDesktop {
    public static let bundleID = "com.openai.codex"

    public static var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    public static var isInstalled: Bool { appURL != nil }

    static func deepLink(sessionID: String?, path: String) -> URL? {
        if let id = sessionID, UUID(uuidString: id) != nil {
            return URL(string: "codex://threads/\(id.lowercased())")
        }
        var c = URLComponents()
        c.scheme = "codex"
        c.host = "threads"
        c.path = "/new"
        c.queryItems = [URLQueryItem(name: "path", value: path)]
        return c.url
    }

    /// 有会话就跳到会话，否则在项目里新开一个。
    public static func open(sessionID: String?, path: String) async throws {
        guard let app = appURL else { throw OpenError.appNotInstalled("Codex") }
        guard let url = deepLink(sessionID: sessionID, path: path) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config)
    }
}
