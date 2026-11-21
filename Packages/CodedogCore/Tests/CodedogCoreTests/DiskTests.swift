import Foundation
import Testing
@testable import CodedogCore

@Suite struct DiskUsageTests {
    @Test func separatesReclaimableAndSkipsSymlinks() throws {
        let f = try Fixture()
        try f.file("app/package.json", "{}")
        try f.file("app/src/index.js", String(repeating: "a", count: 10_000))
        try f.file("app/node_modules/lib/index.js", String(repeating: "b", count: 50_000))
        try f.file("outside/big.bin", String(repeating: "c", count: 200_000))
        try FileManager.default.createSymbolicLink(atPath: f.root + "/app/linked", withDestinationPath: f.root + "/outside")

        let s = DiskUsage.measure(path: f.root + "/app")
        #expect(s.reclaimableDirs.keys.map { ($0 as NSString).lastPathComponent } == ["node_modules"])
        #expect(s.reclaimable >= 50_000)
        #expect(s.source >= 10_000)
        #expect(s.total < 200_000)  // 没有跟随符号链接统计 outside
    }

    @Test func targetOnlyReclaimableForRust() throws {
        let f = try Fixture()
        try f.file("rs/Cargo.toml", "[package]")
        try f.file("rs/target/debug/x", "x")
        try f.file("java/target/classes/A.class", "x")
        #expect(DiskUsage.measure(path: f.root + "/rs").reclaimableDirs.count == 1)
        #expect(DiskUsage.measure(path: f.root + "/java").reclaimableDirs.isEmpty)
    }
}

@Suite struct CleanerTests {
    @Test func cleansValidDirectoriesThroughRemover() throws {
        let f = try Fixture()
        try f.file("app/node_modules/x.js", "x")
        var removed: [String] = []
        let item = CleanupItem(project: f.root + "/app", directory: f.root + "/app/node_modules", bytes: 100)
        let r = DependencyCleaner.clean([item]) { removed.append($0.lastPathComponent) }
        #expect(removed == ["node_modules"])
        #expect(r.freed == 100 && r.failures.isEmpty)
    }

    @Test func refusesSymlinkOutsideAndForeignNames() throws {
        let f = try Fixture()
        try f.file("app/package.json", "{}")
        try f.file("elsewhere/node_modules/x.js", "x")
        try f.file("app/src/main.js", "x")
        try FileManager.default.createSymbolicLink(atPath: f.root + "/app/node_modules", withDestinationPath: f.root + "/elsewhere/node_modules")
        let items = [
            CleanupItem(project: f.root + "/app", directory: f.root + "/app/node_modules", bytes: 1),      // 符号链接
            CleanupItem(project: f.root + "/app", directory: f.root + "/elsewhere/node_modules", bytes: 1), // 不在项目内
            CleanupItem(project: f.root + "/app", directory: f.root + "/app/src", bytes: 1),               // 名称不对
            CleanupItem(project: f.root + "/app", directory: f.root + "/app", bytes: 1),                   // 项目本身
        ]
        var removed = 0
        let r = DependencyCleaner.clean(items) { _ in removed += 1 }
        #expect(removed == 0)
        #expect(r.failures.count == 4)
    }
}

@Suite struct CreatorTests {
    @Test func validatesNames() {
        #expect(ProjectCreator.isValidName("my-app"))
        #expect(ProjectCreator.isValidName("项目_1"))
        #expect(!ProjectCreator.isValidName(".hidden"))
        #expect(!ProjectCreator.isValidName("a/b"))
        #expect(!ProjectCreator.isValidName(""))
    }

    @Test func createsWithGitAndReadme() async throws {
        let f = try Fixture()
        let path = try await ProjectCreator.create(name: "demo", in: f.root, gitInit: true, readme: true)
        #expect(FileManager.default.fileExists(atPath: path + "/.git"))
        #expect((try? String(contentsOfFile: path + "/README.md", encoding: .utf8)) == "# demo\n")
        await #expect(throws: ProjectCreator.Failure.self) {
            try await ProjectCreator.create(name: "demo", in: f.root, gitInit: false, readme: false)
        }
    }
}
