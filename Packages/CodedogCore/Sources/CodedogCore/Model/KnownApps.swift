import Foundation

/// 常见编辑器与终端，用于自动识别和旧数据迁移。用户也可以选择任意其他 App。
public enum KnownApps {
    public static let editors: [AppRef] = [
        AppRef(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        AppRef(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code"),
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

    public static func editor(named name: String) -> AppRef? {
        editors.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
