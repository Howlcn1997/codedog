import Foundation

/// codedog 核心库：项目发现、搜索、元数据存储，与 UI 无关，App 与 CLI 共用。
public enum Codedog {
    public static let version = "1.0.0"

    /// `~/Library/Application Support/codedog`，可用环境变量 `CODEDOG_DATA_DIR` 覆盖。
    public static var dataDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["CODEDOG_DATA_DIR"], !custom.isEmpty {
            return URL(filePath: custom, directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory.appending(path: "codedog", directoryHint: .isDirectory)
    }

    public static var libraryURL: URL { dataDirectory.appending(path: "library.json") }
    public static var cacheURL: URL { dataDirectory.appending(path: "cache.json") }
    public static var legacyURL: URL { dataDirectory.appending(path: "projects.json") }
}
