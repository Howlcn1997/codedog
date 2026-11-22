import Foundation

public struct CleanupItem: Sendable, Hashable, Identifiable {
    public var project: String
    public var directory: String
    public var bytes: Int64
    public var id: String { directory }

    public init(project: String, directory: String, bytes: Int64) {
        self.project = project
        self.directory = directory
        self.bytes = bytes
    }
}

public enum CleanupError: LocalizedError, Sendable {
    case unsafe(String)

    public var errorDescription: String? {
        switch self { case .unsafe(let reason): reason }
    }
}

/// 清理依赖与构建缓存目录：移到废纸篓（可恢复），删除前逐个复核安全性。
public enum DependencyCleaner {
    public static func plan(project: String, size: SizeInfo) -> [CleanupItem] {
        size.reclaimableDirs
            .filter { FileManager.default.fileExists(atPath: $0.key) }
            .map { CleanupItem(project: project, directory: $0.key, bytes: $0.value) }
            .sorted { $0.bytes > $1.bytes }
    }

    /// 复核：目录真实存在、不是符号链接、位于项目内部、名称属于可清理目录。
    public static func validate(_ item: CleanupItem) throws {
        let fm = FileManager.default
        let dir = item.directory
        guard let attrs = try? fm.attributesOfItem(atPath: dir) else { throw CleanupError.unsafe(String(localized: "目录不存在：\(dir)")) }
        guard attrs[.type] as? FileAttributeType == .typeDirectory else { throw CleanupError.unsafe(String(localized: "不是普通目录（可能是符号链接）：\(dir)")) }
        let realProject = FolderScanner.normalize(item.project)
        let realDir = FolderScanner.normalize(dir)
        guard realDir.hasPrefix(realProject + "/"), realDir != realProject else { throw CleanupError.unsafe(String(localized: "目录不在项目内：\(dir)")) }
        let name = (realDir as NSString).lastPathComponent
        guard DiskUsage.isReclaimable(name: name, parent: (realDir as NSString).deletingLastPathComponent) else {
            throw CleanupError.unsafe(String(localized: "不是可清理的目录：\(dir)"))
        }
    }

    /// 逐个复核并移到废纸篓。`remove` 可替换（测试用）。返回成功释放的字节数与失败项。
    public static func clean(_ items: [CleanupItem], remove: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> (freed: Int64, failures: [(CleanupItem, String)]) {
        var freed: Int64 = 0
        var failures: [(CleanupItem, String)] = []
        for item in items {
            do {
                try validate(item)
                try remove(URL(filePath: item.directory, directoryHint: .isDirectory))
                freed += item.bytes
            } catch {
                failures.append((item, error.localizedDescription))
            }
        }
        return (freed, failures)
    }
}

/// 新建项目：在指定目录下创建文件夹，可选 git init 与 README。
public enum ProjectCreator {
    public enum Failure: LocalizedError, Sendable {
        case invalidName, exists(String), parentMissing(String)
        public var errorDescription: String? {
            switch self {
            case .invalidName: String(localized: "项目名只能包含字母、数字、中文、点、横线和下划线，且不能以点开头。")
            case .exists(let p): String(localized: "已经存在同名文件夹：\(p)")
            case .parentMissing(let p): String(localized: "位置不存在：\(p)")
            }
        }
    }

    public static func isValidName(_ name: String) -> Bool {
        name.range(of: #"^[\p{L}\p{N}_][\p{L}\p{N}._-]{0,99}$"#, options: .regularExpression) != nil
    }

    @discardableResult
    public static func create(name: String, in parent: String, gitInit: Bool, readme: Bool) async throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard isValidName(trimmed) else { throw Failure.invalidName }
        let base = FolderScanner.normalize(parent)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: base, isDirectory: &isDir), isDir.boolValue else { throw Failure.parentMissing(base) }
        let path = base + "/" + trimmed
        guard !FileManager.default.fileExists(atPath: path) else { throw Failure.exists(path) }
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
        if readme { try "# \(trimmed)\n".write(toFile: path + "/README.md", atomically: true, encoding: .utf8) }
        if gitInit { _ = try await ShellRunner.run("git", ["init", "-q", path], timeout: .seconds(20)) }
        return path
    }
}
