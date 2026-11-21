import Foundation

/// 项目占用空间。依赖与构建缓存目录单独统计，可以安全清理（重新安装/构建即可恢复）。
public struct SizeInfo: Codable, Sendable, Hashable {
    public var total: Int64
    public var reclaimable: Int64
    /// 可清理目录的绝对路径 → 字节数
    public var reclaimableDirs: [String: Int64]
    public var measuredAt: Date

    public init(total: Int64, reclaimable: Int64, reclaimableDirs: [String: Int64], measuredAt: Date = .now) {
        self.total = total
        self.reclaimable = reclaimable
        self.reclaimableDirs = reclaimableDirs
        self.measuredAt = measuredAt
    }

    public var source: Int64 { max(0, total - reclaimable) }
}

public enum DiskUsage {
    /// 总是可以重新生成的目录。
    static let alwaysReclaimable: Set<String> = ["node_modules", ".venv", "venv", "Pods", ".next", ".nuxt", ".turbo", ".parcel-cache"]

    /// 名称是否为可清理目录。`target` 只在 Rust 项目（同级有 Cargo.toml）中算可清理。
    static func isReclaimable(name: String, parent: String) -> Bool {
        if alwaysReclaimable.contains(name) { return true }
        if name == "target" { return FileManager.default.fileExists(atPath: parent + "/Cargo.toml") }
        return false
    }

    /// 统计项目大小。不跟随符号链接；遇到可清理目录整体计入后不再细分。
    public static func measure(path: String) -> SizeInfo {
        var total: Int64 = 0
        var dirs: [String: Int64] = [:]
        let root = URL(filePath: path, directoryHint: .isDirectory)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else {
            return SizeInfo(total: 0, reclaimable: 0, reclaimableDirs: [:])
        }
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isSymbolicLink == true { continue }  // 遍历器本身不跟随链接；不要在这里 skipDescendants，它作用于上一个目录
            if v.isDirectory == true {
                let name = url.lastPathComponent
                if isReclaimable(name: name, parent: url.deletingLastPathComponent().path(percentEncoded: false)) {
                    let size = treeSize(url)
                    dirs[url.path(percentEncoded: false).replacingOccurrences(of: "/$", with: "", options: .regularExpression)] = size
                    total += size
                    e.skipDescendants()
                }
                continue
            }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return SizeInfo(total: total, reclaimable: dirs.values.reduce(0, +), reclaimableDirs: dirs)
    }

    static func treeSize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        var sum: Int64 = 0
        for case let u as URL in e {
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isSymbolicLink == true { continue }  // 遍历器本身不跟随链接；不要在这里 skipDescendants，它作用于上一个目录
            if v.isDirectory != true { sum += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0) }
        }
        return sum
    }

    /// 并发统计多个项目（限并发，磁盘 IO 为主）。
    public static func measureAll(_ paths: [String], concurrency: Int = 3, progress: (@Sendable (String, SizeInfo) -> Void)? = nil) async -> [String: SizeInfo] {
        await withTaskGroup(of: (String, SizeInfo).self) { group in
            var out: [String: SizeInfo] = [:]
            var it = paths.makeIterator()
            for _ in 0..<concurrency {
                guard let p = it.next() else { break }
                group.addTask(priority: .utility) { (p, measure(path: p)) }
            }
            for await (p, s) in group {
                out[p] = s
                progress?(p, s)
                if let n = it.next() { group.addTask(priority: .utility) { (n, measure(path: n)) } }
            }
            return out
        }
    }
}

/// `sizes.json`：占用空间缓存。
public struct SizeCache: Codable, Sendable {
    public var sizes: [String: SizeInfo] = [:]

    public init(sizes: [String: SizeInfo] = [:]) { self.sizes = sizes }

    public static var url: URL { Codedog.dataDirectory.appending(path: "sizes.json") }

    public static func load(_ url: URL = SizeCache.url) -> SizeCache {
        guard let data = try? Data(contentsOf: url), let c = try? JSONDecoder.codedog.decode(SizeCache.self, from: data) else { return SizeCache() }
        return c
    }

    public func save(_ url: URL = SizeCache.url) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.codedogCompact.encode(self).write(to: url, options: .atomic)
    }
}
