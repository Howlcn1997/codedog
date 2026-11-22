import AppKit
import CodedogCore
import ServiceManagement

/// 开机启动（SMAppService）。
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isEnabled: Bool { status == .enabled }
    static var needsApproval: Bool { status == .requiresApproval }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// 把 App 内置的命令行工具链接到 `~/.local/bin/codedog`。
enum CLIInstaller {
    enum Status: Equatable {
        case notInstalled
        case installed
        /// 已有同名文件但不是 codedog 安装的
        case conflict
    }

    static var executable: URL { Bundle.main.bundleURL.appending(path: "Contents/MacOS/codedog-cli") }
    static var link: URL { URL(filePath: NSHomeDirectory()).appending(path: ".local/bin/codedog") }

    static var status: Status {
        let fm = FileManager.default
        let path = link.path(percentEncoded: false)
        guard (try? fm.attributesOfItem(atPath: path)) != nil else { return .notInstalled }
        if let dest = try? fm.destinationOfSymbolicLink(atPath: path) {
            return dest.hasSuffix("/Contents/MacOS/codedog-cli") ? .installed : .conflict
        }
        return .conflict
    }

    /// 是否指向当前这份 App（App 被移动后需要重新安装）。
    static var pointsToThisApp: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false))) == executable.path(percentEncoded: false)
    }

    static func install() throws {
        let fm = FileManager.default
        if status == .conflict {
            throw NSError(domain: "codedog", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: "\(link.path(percentEncoded: false)) 已存在且不是 codedog 安装的，为了安全不会覆盖。")])
        }
        try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        if status == .installed { try fm.removeItem(at: link) }
        try fm.createSymbolicLink(at: link, withDestinationURL: executable)
    }

    static func uninstall() throws {
        guard status == .installed else { return }
        try FileManager.default.removeItem(at: link)
    }

    /// 登录 shell 的 PATH 是否包含 ~/.local/bin。
    static func pathContainsLocalBin() async -> Bool {
        let path = await LoginEnvironment.shared.environment["PATH"] ?? ""
        let dir = link.deletingLastPathComponent().path(percentEncoded: false)
        return path.split(separator: ":").contains { String($0) == dir || String($0) == "~/.local/bin" }
    }
}
