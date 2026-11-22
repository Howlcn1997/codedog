import AppKit
import Foundation

/// 在终端里接着上次的 AI 会话继续。
public enum AgentLauncher {
    /// 续上会话的命令；没有会话时直接启动工具。
    public static func resumeCommand(tool: AITool, sessionID: String?) -> String? {
        switch tool {
        case .claudeCode: sessionID.map { "claude --resume \(shellQuote($0))" } ?? "claude"
        case .codex: sessionID.map { "codex resume \(shellQuote($0))" } ?? "codex"
        default: nil
        }
    }

    /// 在指定目录打开终端并执行命令。Terminal 与 iTerm2 通过 AppleScript；其他终端退回到系统终端。
    public static func run(_ command: String, in directory: String, terminal: AppRef?) throws {
        let line = "cd \(shellQuote(directory)) && \(command)"
        let script: String
        if terminal?.bundleID == "com.googlecode.iterm2" {
            script = """
            tell application id "com.googlecode.iterm2"
                activate
                set w to (create window with default profile)
                tell current session of w to write text \(appleQuote(line))
            end tell
            """
        } else {
            script = """
            tell application id "com.apple.Terminal"
                activate
                do script \(appleQuote(line))
            end tell
            """
        }
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            throw NSError(domain: "codedog", code: 1, userInfo: [NSLocalizedDescriptionKey: (error[NSAppleScript.errorMessage] as? String) ?? String(localized: "无法控制终端，请在系统设置 › 隐私与安全性 › 自动化 中允许 codedog。")])
        }
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func appleQuote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
}
