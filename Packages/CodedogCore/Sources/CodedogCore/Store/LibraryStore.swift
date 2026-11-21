import Foundation

/// 读写 `library.json`。写入前重新读盘并在文件协调下完成，App 与 CLI 可以安全共享。
public actor LibraryStore {
    public let url: URL
    public private(set) var library: Library

    public init(url: URL = Codedog.libraryURL) {
        self.url = url
        self.library = Self.read(url) ?? Library()
    }

    public func reload() -> Library {
        library = Self.read(url) ?? library
        return library
    }

    @discardableResult
    public func mutate(_ body: @Sendable (inout Library) throws -> Void) throws -> Library {
        var coordError: NSError?
        var thrown: Error?
        var result = library
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordError) { target in
            do {
                var fresh = Self.decode(target) ?? library
                try body(&fresh)
                try Self.encoder.encode(fresh).write(to: target, options: .atomic)
                result = fresh
            } catch { thrown = error }
        }
        if let e = coordError ?? thrown { throw e }
        library = result
        return result
    }

    static func read(_ url: URL) -> Library? {
        var coordError: NSError?
        var lib: Library?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { target in
            lib = decode(target)
        }
        return lib
    }

    /// 不加协调地读取；只能在已持有协调的块内调用，否则嵌套协调会死锁。
    static func decode(_ url: URL) -> Library? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.codedog.decode(Library.self, from: data)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static var codedog: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// `cache.json`：扫描结果缓存，用于秒开。损坏或缺失时直接重扫。
public struct ProjectCache: Codable, Sendable {
    public var projects: [DiscoveredProject] = []
    public var lastScan: Date?

    public init(projects: [DiscoveredProject] = [], lastScan: Date? = nil) {
        self.projects = projects
        self.lastScan = lastScan
    }

    public static func load(_ url: URL = Codedog.cacheURL) -> ProjectCache {
        guard let data = try? Data(contentsOf: url), let c = try? JSONDecoder.codedog.decode(ProjectCache.self, from: data) else { return ProjectCache() }
        return c
    }

    public func save(_ url: URL = Codedog.cacheURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        try e.encode(self).write(to: url, options: .atomic)
    }
}
