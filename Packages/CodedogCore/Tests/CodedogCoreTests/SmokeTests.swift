import Foundation
import Testing
@testable import CodedogCore

@Test func dataDirectoryEndsWithCodedog() {
    #expect(Codedog.dataDirectory.lastPathComponent == "codedog" || ProcessInfo.processInfo.environment["CODEDOG_DATA_DIR"] != nil)
}
