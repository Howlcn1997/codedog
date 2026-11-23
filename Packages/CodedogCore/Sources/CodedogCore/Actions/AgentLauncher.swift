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

    /// 能在里面执行命令的终端。不在列表里的（如编辑器内置终端）由调用方退回到偏好终端。
    public static let drivableTerminals: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty", "net.kovidgoyal.kitty", "com.github.wez.wezterm",
    ]

    /// 在指定目录打开终端并执行命令。未指定或无法驱动的终端退回到系统终端。
    public static func run(_ command: String, in directory: String, terminal: AppRef?) throws {
        let id = terminal?.bundleID ?? "com.apple.Terminal"
        guard drivableTerminals.contains(id), NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil else {
            return try appleScript(terminal: "com.apple.Terminal", line: "cd \(shellQuote(directory)) && \(command)")
        }
        switch id {
        case "com.apple.Terminal", "com.googlecode.iterm2":
            try appleScript(terminal: id, line: "cd \(shellQuote(directory)) && \(command)")
        case "dev.warp.Warp-Stable":
            try warp(command, in: directory)
        default:
            try openNew(id, args: shellArgs(id, command: command, directory: directory))
        }
    }

    // MARK: 各终端

    private static func appleScript(terminal: String, line: String) throws {
        let script = terminal == "com.googlecode.iterm2" ? """
            tell application id "com.googlecode.iterm2"
                activate
                set w to (create window with default profile)
                tell current session of w to write text \(appleQuote(line))
            end tell
            """ : """
            tell application id "com.apple.Terminal"
                activate
                do script \(appleQuote(line))
            end tell
            """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            throw NSError(domain: "codedog", code: 1, userInfo: [NSLocalizedDescriptionKey: (error[NSAppleScript.errorMessage] as? String) ?? String(localized: "无法控制终端，请在系统设置 › 隐私与安全性 › 自动化 中允许 CodeDog。")])
        }
    }

    /// Warp 没有"执行命令"的 URL，只能写一份启动配置（launch configuration）再用 `warp://launch/` 打开。
    /// 配置固定写到同一个文件，每次覆盖，不会在 Warp 里越积越多。
    private static func warp(_ command: String, in directory: String) throws {
        let dir = URL(filePath: NSHomeDirectory()).appending(path: ".warp/launch_configurations", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "codedog-resume"
        let title = (directory as NSString).lastPathComponent
        let yaml = """
            ---
            name: \(name)
            windows:
              - tabs:
                  - title: \(yamlQuote(title))
                    layout:
                      cwd: \(yamlQuote(directory))
                      commands:
                        - exec: \(yamlQuote(command))

            """
        try yaml.write(to: dir.appending(path: "\(name).yaml"), atomically: true, encoding: .utf8)
        guard let url = URL(string: "warp://launch/\(name).yaml") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Ghostty / kitty / WezTerm：开一个新实例，用登录 shell 执行命令，命令结束后留在 shell 里。
    static func shellArgs(_ bundleID: String, command: String, directory: String) -> [String] {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let exec = [shell, "-l", "-c", "\(command); exec \(shellQuote(shell)) -l"]
        switch bundleID {
        case "com.mitchellh.ghostty": return ["--working-directory=\(directory)", "-e"] + exec
        case "net.kovidgoyal.kitty": return ["--directory", directory] + exec
        case "com.github.wez.wezterm": return ["start", "--cwd", directory, "--"] + exec
        default: return []
        }
    }

    private static func openNew(_ bundleID: String, args: [String]) throws {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/open")
        p.arguments = ["-n", "-b", bundleID, "--args"] + args
        try p.run()
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func appleQuote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
    static func yamlQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }
}

/// 记住每个智能体会话是在哪个终端里跑的，续上时回到同一个终端。
/// 键为 "工具|工作目录"，值为终端的 bundle id。存在 `agent-terminals.json`，属于可再生的观测数据。
public struct AgentTerminals: Codable, Sendable, Hashable {
    public var byKey: [String: String] = [:]

    public init() {}

    public static var url: URL { Codedog.dataDirectory.appending(path: "agent-terminals.json") }

    public static func load(from url: URL = AgentTerminals.url) -> AgentTerminals {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(AgentTerminals.self, from: $0) } ?? AgentTerminals()
    }

    public func save(to url: URL = AgentTerminals.url) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    static func key(_ tool: AITool, _ cwd: String) -> String { "\(tool.rawValue)|\(FolderScanner.normalizeFast(cwd))" }

    /// 记下正在运行的进程所在的终端；只记能驱动的终端（编辑器内置终端等无法续上，不记）。返回是否有变化。
    public mutating func record(_ processes: [RunningAgents.Process]) -> Bool {
        var changed = false
        for p in processes {
            guard let t = p.terminal, AgentLauncher.drivableTerminals.contains(t) else { continue }
            let k = Self.key(p.tool, p.cwd)
            if byKey[k] != t { byKey[k] = t; changed = true }
        }
        return changed
    }

    /// 某个会话该用的终端：先按会话目录精确找，再按项目目录找，最后找项目下任一子目录的记录。
    public func terminal(tool: AITool, cwd: String?, project: String) -> String? {
        if let cwd, let t = byKey[Self.key(tool, cwd)] { return t }
        if let t = byKey[Self.key(tool, project)] { return t }
        let prefix = Self.key(tool, project) + "/"
        return byKey.first { $0.key.hasPrefix(prefix) }?.value
    }
}
