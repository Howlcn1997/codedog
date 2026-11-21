import Foundation
import Testing
@testable import CodedogCore

@Suite struct StoreTests {
    @Test func mutatePersistsAndDropsEmptyMeta() async throws {
        let f = try Fixture()
        let url = URL(filePath: f.root + "/library.json")
        let store = LibraryStore(url: url)
        try await store.mutate { lib in
            lib.scanRoots = ["/x"]
            lib.updateMeta("/x/a") { $0.favorite = true }
            lib.updateMeta("/x/b") { $0.notes = "" }
        }
        let reread = LibraryStore(url: url)
        let lib = await reread.library
        #expect(lib.scanRoots == ["/x"])
        #expect(lib.meta(for: "/x/a").favorite)
        #expect(lib.meta["/x/b"] == nil)
    }

    @Test func mutateRereadsDiskFirst() async throws {
        let f = try Fixture()
        let url = URL(filePath: f.root + "/library.json")
        let a = LibraryStore(url: url), b = LibraryStore(url: url)
        try await a.mutate { $0.scanRoots = ["/a"] }
        try await b.mutate { $0.categories.append(Category(name: "c")) }
        let lib = await LibraryStore(url: url).library
        #expect(lib.scanRoots == ["/a"])
        #expect(lib.categories.map(\.name) == ["c"])
    }

    @Test func cacheRoundTrip() throws {
        let f = try Fixture()
        let url = URL(filePath: f.root + "/cache.json")
        let p = DiscoveredProject(path: "/x/a", name: "a", stacks: [.go], kind: .service, git: GitInfo(branch: "main", dirtyFiles: 2))
        try ProjectCache(projects: [p], lastScan: .now).save(url)
        #expect(ProjectCache.load(url).projects.first?.git?.dirtyFiles == 2)
    }
}
