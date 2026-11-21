import Foundation

/// 高速逐行扫描 JSONL：内存映射 + memchr 分行 + memmem 预筛，只解析需要的行。
enum JSONLScanner {
    static func forEachLine(path: String, matchingAny needles: [String], _ body: ([String: Any]) -> Void) {
        guard let data = try? Data(contentsOf: URL(filePath: path), options: .alwaysMapped) else { return }
        let needleBytes = needles.map { Array($0.utf8) }
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            let count = raw.count
            while offset < count {
                let start = base + offset
                let remaining = count - offset
                let nl = memchr(start, 0x0A, remaining)
                let length = nl.map { UnsafeRawPointer($0) - UnsafeRawPointer(start) } ?? remaining
                defer { offset += length + 1 }
                guard length > 2 else { continue }
                let hit = needleBytes.contains { n in
                    n.withUnsafeBytes { memmem(start, length, $0.baseAddress, n.count) != nil }
                }
                guard hit else { continue }
                let line = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: start), count: length, deallocator: .none)
                if let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] { body(obj) }
            }
        }
    }
}
