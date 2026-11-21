import Foundation
import Testing
@testable import CodedogCore

@Suite struct LegacyImporterTests {
    let json = """
    {"version":1,"root":"/tmp/legacy-root","ide":"Cursor","terminal":"warp","launcherShortcut":"CommandOrControl+Shift+Space",
     "groups":[{"id":"group-1","name":"Github"}],
     "projects":[
       {"id":"1","name":"a","path":"/tmp/legacy-root/company/a","group":"company","tags":["ZXAI"],"notes":"n","favorite":true,"archived":false,"lastOpened":1789133972845,"ide":"WebStorm","searchIndex":{}},
       {"id":"2","name":"b","path":"/elsewhere/b","group":"group-1","tags":["zxai"],"favorite":false,"archived":true,"lastOpened":0}
     ]}
    """

    @Test func migratesUsefulFields() throws {
        var lib = Library()
        try LegacyImporter.migrate(data: Data(json.utf8), into: &lib, suggestedRoots: [])
        let root = FolderScanner.normalize("/tmp/legacy-root")
        #expect(lib.scanRoots == [root])
        #expect(Set(lib.categories.map(\.name)) == ["公司项目", "ZXAI", "Github"])  // 标签不区分大小写去重

        let a = lib.meta(for: FolderScanner.normalize("/tmp/legacy-root/company/a"))
        #expect(a.favorite && !a.hidden && !a.pinned)
        #expect(a.notes == "n")
        #expect(a.editor?.name == "WebStorm")
        #expect(a.categories.count == 2)
        #expect(a.lastOpened != nil)

        let b = lib.meta(for: "/elsewhere/b")
        #expect(b.hidden && b.pinned)
        #expect(b.lastOpened == nil)

        #expect(lib.preferences.editor?.name == "Cursor")
        #expect(lib.preferences.terminal?.name == "Warp")
        #expect(lib.preferences.launcherShortcut == "cmd+shift+space")
        #expect(lib.migratedLegacy)
    }

    @Test func migrationIsIdempotent() throws {
        var lib = Library()
        try LegacyImporter.migrate(data: Data(json.utf8), into: &lib, suggestedRoots: [])
        let once = lib
        try LegacyImporter.migrate(data: Data(json.utf8), into: &lib, suggestedRoots: [])
        #expect(lib == once)
    }
}
