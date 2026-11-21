import Foundation

/// 临时目录夹具，测试结束自动删除。
final class Fixture {
    let root: String

    init() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "codedog-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = base.resolvingSymlinksInPath().path(percentEncoded: false).replacingOccurrences(of: "/$", with: "", options: .regularExpression)
    }

    @discardableResult
    func file(_ rel: String, _ content: String = "") throws -> String {
        let path = root + "/" + rel
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    func dir(_ rel: String) throws {
        try FileManager.default.createDirectory(atPath: root + "/" + rel, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(atPath: root) }
}
