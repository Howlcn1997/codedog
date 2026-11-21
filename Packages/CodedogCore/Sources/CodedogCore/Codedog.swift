import Foundation

/// codedog 核心库：项目发现、搜索、元数据存储，与 UI 无关，App 与 CLI 共用。
public enum Codedog {
    /// 版本号唯一来源：project.yml 的 MARKETING_VERSION（写入 App 的 Info.plist）。
    /// 命令行工具位于 App 包内，同样能读到；脱离 App 运行（如 swift test）时为 "dev"。
    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// `~/Library/Application Support/codedog`，可用环境变量 `CODEDOG_DATA_DIR` 覆盖。
    public static var dataDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["CODEDOG_DATA_DIR"], !custom.isEmpty {
            return URL(filePath: custom, directoryHint: .isDirectory)
        }
        #if DEBUG
        // 调试构建默认用独立目录，避免开发测试写入真实数据
        return URL.applicationSupportDirectory.appending(path: "codedog-dev", directoryHint: .isDirectory)
        #else
        return URL.applicationSupportDirectory.appending(path: "codedog", directoryHint: .isDirectory)
        #endif
    }

    public static var libraryURL: URL { dataDirectory.appending(path: "library.json") }
    public static var cacheURL: URL { dataDirectory.appending(path: "cache.json") }
    /// 旧版 Electron codedog 的数据文件（始终位于正式目录，只读）。
    public static var legacyURL: URL {
        if let custom = ProcessInfo.processInfo.environment["CODEDOG_DATA_DIR"], !custom.isEmpty {
            return URL(filePath: custom).appending(path: "projects.json")
        }
        return URL.applicationSupportDirectory.appending(path: "codedog/projects.json")
    }
}
