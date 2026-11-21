import Foundation

/// 通过 GitHub Releases 检查新版本（App 未签名，无法自动替换安装，只提示下载）。
public enum UpdateChecker {
    public static let repository = "Howlcn1997/codedog"

    public struct Release: Sendable, Equatable {
        public var version: String
        public var url: URL
        public var notes: String
        public var publishedAt: Date?
    }

    /// 最新的正式版；请求失败返回 nil（离线时静默）。
    public static func latest(session: URLSession = .shared) async -> Release? {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("codedog", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return parse(json)
    }

    static func parse(_ json: [String: Any]) -> Release? {
        guard json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                       url: page,
                       notes: json["body"] as? String ?? "",
                       publishedAt: (json["published_at"] as? String).flatMap(DayKey.parseISO))
    }

    /// 语义化版本比较：`1.2.10 > 1.2.9`，忽略 `-beta` 等后缀。
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
