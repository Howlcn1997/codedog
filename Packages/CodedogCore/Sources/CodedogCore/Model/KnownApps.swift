import Foundation

/// 常见编辑器与终端，用于自动识别和旧数据迁移。用户也可以选择任意其他 App。
public enum KnownApps {
    public static let editors: [AppRef] = [
        AppRef(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        AppRef(bundleID: "com.microsoft.VSCode", name: "VS Code"),
        AppRef(bundleID: "dev.zed.Zed", name: "Zed"),
        AppRef(bundleID: "com.exafunction.windsurf", name: "Windsurf"),
        AppRef(bundleID: "com.trae.app", name: "Trae"),
        AppRef(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
        AppRef(bundleID: "com.jetbrains.WebStorm", name: "WebStorm"),
        AppRef(bundleID: "com.jetbrains.goland", name: "GoLand"),
        AppRef(bundleID: "com.jetbrains.pycharm", name: "PyCharm"),
        AppRef(bundleID: "com.jetbrains.intellij", name: "IntelliJ IDEA"),
        AppRef(bundleID: "com.sublimetext.4", name: "Sublime Text"),
    ]

    public static let terminals: [AppRef] = [
        AppRef(bundleID: "com.apple.Terminal", name: "终端"),
        AppRef(bundleID: "com.googlecode.iterm2", name: "iTerm2"),
        AppRef(bundleID: "dev.warp.Warp-Stable", name: "Warp"),
        AppRef(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
        AppRef(bundleID: "net.kovidgoyal.kitty", name: "kitty"),
        AppRef(bundleID: "com.github.wez.wezterm", name: "WezTerm"),
    ]

    public static let defaultTerminal = terminals[0]

    /// 支持多根工作区文件（`.code-workspace`）的编辑器。
    public static let workspaceCapable: Set<String> = [
        "com.todesktop.230313mzl4w4u92", "com.microsoft.VSCode", "com.exafunction.windsurf", "com.trae.app",
    ]

    /// 旧名称 → 现用名称（旧数据里可能存的是 App 的完整名）。
    static let aliases: [String: String] = ["Visual Studio Code": "VS Code"]

    public static func editor(named name: String) -> AppRef? {
        let name = aliases.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value ?? name
        return editors.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// 已知 App 用统一的简称显示（例如 VS Code），未知 App 保留原名。
    public static func displayName(bundleID: String, fallback: String) -> String {
        (editors + terminals).first { $0.bundleID == bundleID }?.name ?? fallback
    }
}
