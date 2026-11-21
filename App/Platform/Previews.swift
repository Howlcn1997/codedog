import AppKit
import CodedogCore
import WebKit

/// HTML 项目预览：在屏幕外的 WKWebView 里加载根目录 HTML 并截图。
/// - 只允许读取项目目录内的文件，主框架跳转到其他地址会被拦截；
/// - 使用非持久化存储（不留 Cookie / 缓存）；
/// - 串行渲染，结果按"路径 + 修改时间"缓存在内存和磁盘。
@MainActor
final class HTMLThumbnailer: NSObject, WKNavigationDelegate {
    static let shared = HTMLThumbnailer()

    private var memory: [String: NSImage] = [:]
    private var waiting: [String: [CheckedContinuation<NSImage?, Never>]] = [:]
    private var queue: [(key: String, file: URL, root: URL)] = []
    private var busy = false
    private var window: NSWindow?
    private var webView: WKWebView?
    private var current: (key: String, file: URL, root: URL)?
    private var finish: ((NSImage?) -> Void)?

    private var diskDir: URL { Codedog.dataDirectory.appending(path: "thumbnails", directoryHint: .isDirectory) }

    func cached(project: String, entry: String) -> NSImage? {
        guard let key = key(project: project, entry: entry) else { return nil }
        if let img = memory[key] { return img }
        if let img = NSImage(contentsOf: diskDir.appending(path: "\(key).png")) { memory[key] = img; return img }
        return nil
    }

    func thumbnail(project: String, entry: String) async -> NSImage? {
        guard let key = key(project: project, entry: entry) else { return nil }
        if let img = cached(project: project, entry: entry) { return img }
        return await withCheckedContinuation { cont in
            if waiting[key] != nil { waiting[key]!.append(cont); return }
            waiting[key] = [cont]
            queue.append((key, URL(filePath: project + "/" + entry), URL(filePath: project, directoryHint: .isDirectory)))
            pump()
        }
    }

    private func key(project: String, entry: String) -> String? {
        let path = project + "/" + entry
        guard let m = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { return nil }
        return String(ProjectArt.seed("\(path)|\(m.timeIntervalSince1970)"), radix: 16)
    }

    private func pump() {
        guard !busy, !queue.isEmpty else { return }
        busy = true
        let job = queue.removeFirst()
        current = job
        let web = ensureWebView()
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.complete(nil)
        }
        finish = { [weak self] image in
            timeout.cancel()
            guard let self else { return }
            if let image {
                memory[job.key] = image
                try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
                if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                    try? rep.representation(using: .png, properties: [:])?.write(to: diskDir.appending(path: "\(job.key).png"))
                }
            }
            for c in waiting.removeValue(forKey: job.key) ?? [] { c.resume(returning: image) }
            current = nil
            busy = false
            web.loadHTMLString("", baseURL: nil)
            pump()
        }
        web.loadFileURL(job.file, allowingReadAccessTo: job.root)
    }

    private func complete(_ image: NSImage?) {
        let f = finish
        finish = nil
        f?(image)
    }

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 860), configuration: config)
        web.navigationDelegate = self
        // 放在屏幕外的窗口里，保证页面真正渲染
        let w = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 1200, height: 860), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.ignoresMouseEvents = true
        w.contentView = web
        w.orderBack(nil)
        window = w
        webView = web
        return web
    }

    nonisolated func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        MainActor.assumeIsolated {
            let url = action.request.url
            var inProject = false
            if let url, url.isFileURL, let root = current?.root.path(percentEncoded: false) {
                inProject = url.path(percentEncoded: false).hasPrefix(root)
            }
            let isMain = action.targetFrame?.isMainFrame ?? true
            // 主框架只允许停留在项目内；子资源（图片、脚本、iframe）照常加载
            decisionHandler(!isMain || inProject || url?.scheme == "about" ? .allow : .cancel)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            guard current != nil, webView.url?.isFileURL == true else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))   // 等脚本与字体渲染
                let cfg = WKSnapshotConfiguration()
                cfg.snapshotWidth = 600
                let image = try? await webView.takeSnapshot(configuration: cfg)
                self.complete(image.flatMap { Self.isBlank($0) ? nil : $0 })
            }
        }
    }

    /// 几乎纯色的截图（空白页、只有加载器）视为失败。
    static func isBlank(_ image: NSImage) -> Bool {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return true }
        let w = 24, h = 18
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return true }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var lums: [Double] = []
        for i in stride(from: 0, to: px.count, by: 4) {
            lums.append(0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2]))
        }
        let mean = lums.reduce(0, +) / Double(lums.count)
        let variance = lums.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(lums.count)
        return variance < 12
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { if current != nil { complete(nil) } }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { if current != nil { complete(nil) } }
    }
}

/// 文件开头几行（只读前 4KB），用于纸张上的代码预览。
@MainActor
final class FilePreviews {
    static let shared = FilePreviews()
    private var cache: [String: [String]] = [:]

    func lines(_ path: String) -> [String]? { cache[path] }

    func load(_ path: String, maxLines: Int = 12) async -> [String] {
        if let c = cache[path] { return c }
        let lines = await Task.detached(priority: .utility) { () -> [String] in
            guard let h = FileHandle(forReadingAtPath: path) else { return [] }
            defer { try? h.close() }
            let data = (try? h.read(upToCount: 4096)) ?? Data()
            if data.contains(0) { return [] }   // 二进制
            return String(decoding: data, as: UTF8.self)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .prefix(maxLines)
                .map { String($0.prefix(80)).replacingOccurrences(of: "\t", with: "  ") }
        }.value
        cache[path] = lines
        return lines
    }
}
