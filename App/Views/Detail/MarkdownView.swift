import AppKit
import SwiftUI

/// README 弹窗：标题栏 + 可滚动的 Markdown 正文，Esc 或右上角关闭。
struct ReadmeSheet: View {
    let title: String
    /// 项目目录，用来解析 README 里的相对图片路径。
    let baseURL: URL?
    private let blocks: [MarkdownBlock]
    @Environment(\.dismiss) private var dismiss

    init(title: String, text: String, baseURL: URL?) {
        self.title = title
        self.baseURL = baseURL
        self.blocks = MarkdownParser.parse(text)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text").foregroundStyle(.secondary)
                Text(verbatim: title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.06), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("关闭")
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            Divider()
            ScrollView {
                MarkdownView(blocks: blocks, baseURL: baseURL)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 560, idealWidth: 720, maxWidth: 900, minHeight: 420, idealHeight: 640, maxHeight: 900)
    }
}

// MARK: - 渲染

struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    let baseURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
        // README 里的相对链接（docs/xxx.md）按项目目录解析，用默认应用打开
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == nil, let baseURL else { return .systemAction }
            let path = url.path(percentEncoded: false)
            guard !path.isEmpty else { return .discarded }
            NSWorkspace.shared.open(baseURL.appending(path: path.hasPrefix("./") ? String(path.dropFirst(2)) : path))
            return .handled
        })
    }

    @ViewBuilder private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            heading(level, text, centered: false)
        case .paragraph(let text):
            Text(MarkdownParser.inline(text))
                .font(.system(size: 13))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .list(let items):
            list(items)
        case .code(let code):
            ScrollView(.horizontal) {
                Text(verbatim: code)
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(2)
                    .padding(12)
            }
            .scrollIndicators(.never)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.primary.opacity(0.18)).frame(width: 3)
                Text(MarkdownParser.inline(text))
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .rule:
            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
        case .table(let header, let rows):
            table(header, rows)
        case .images(let images):
            if images.count == 1, let img = images.first {
                MarkdownImage(image: img, baseURL: baseURL, standalone: true)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, img in
                        MarkdownImage(image: img, baseURL: baseURL, standalone: false)
                    }
                }
            }
        case .centered(.heading(let level, let text)):
            heading(level, text, centered: true)
        case .centered(let inner):
            AnyView(view(for: inner))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func heading(_ level: Int, _ text: String, centered: Bool) -> some View {
        let size: CGFloat = [22, 18, 15, 13, 13, 12][min(max(level, 1), 6) - 1]
        return VStack(alignment: .leading, spacing: 6) {
            Text(MarkdownParser.inline(text))
                .font(.system(size: size, weight: level <= 2 ? .bold : .semibold))
                .multilineTextAlignment(centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            if level <= 2 {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            }
        }
        .padding(.top, level <= 2 ? 6 : 2)
    }

    private func list(_ items: [MarkdownListItem]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Group {
                        if let checked = item.checked {
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .foregroundStyle(checked ? Color.brand : .secondary)
                        } else if let n = item.number {
                            Text(verbatim: "\(n).").monospacedDigit().foregroundStyle(.secondary)
                        } else {
                            Text(verbatim: item.indent == 0 ? "•" : "◦").foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: 16, alignment: .trailing)
                    Text(MarkdownParser.inline(item.text))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 13))
                .padding(.leading, CGFloat(item.indent) * 18)
            }
        }
    }

    private func table(_ header: [String], _ rows: [[String]]) -> some View {
        let columns = max(header.count, rows.map(\.count).max() ?? 0)
        func cell(_ row: [String], _ i: Int) -> String { i < row.count ? row[i] : "" }
        return ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                GridRow {
                    ForEach(0..<columns, id: \.self) { i in
                        Text(MarkdownParser.inline(cell(header, i))).fontWeight(.semibold)
                    }
                }
                Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { i in
                            Text(MarkdownParser.inline(cell(row, i)))
                        }
                    }
                }
            }
            .font(.system(size: 12.5))
            .padding(12)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// 图片：相对路径从项目目录读，网络图片异步加载；加载失败时显示替代文字（没有就不显示）。
private struct MarkdownImage: View {
    let image: MarkdownImageRef
    let baseURL: URL?
    /// 独占一段的大图按宽度铺开；徽章这类一排的小图保持原始高度。
    let standalone: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let content = Group {
            if let url = resolved, url.isFileURL {
                if let ns = NSImage(contentsOf: url) { sized(Image(nsImage: ns), ns.size) } else { fallback }
            } else if let url = resolved {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): sized(img, nil)
                    case .failure: fallback
                    default: ProgressView().controlSize(.small).frame(width: 20, height: 20)
                    }
                }
            } else {
                fallback
            }
        }
        if let link = image.link.flatMap(URL.init(string:)), link.scheme?.hasPrefix("http") == true {
            Link(destination: link) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    private var resolved: URL? {
        let src = scheme == .dark ? (image.darkSrc ?? image.src) : image.src
        if src.hasPrefix("http://") || src.hasPrefix("https://") { return URL(string: src) }
        guard let baseURL else { return nil }
        let clean = src.hasPrefix("./") ? String(src.dropFirst(2)) : src
        return baseURL.appending(path: clean.removingPercentEncoding ?? clean)
    }

    @ViewBuilder private func sized(_ img: Image, _ size: CGSize?) -> some View {
        if let w = image.width {
            img.resizable().scaledToFit().frame(width: w)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else if standalone {
            img.resizable().scaledToFit()
                .frame(maxWidth: min(size?.width ?? .infinity, 640), maxHeight: 420, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            img.resizable().scaledToFit().frame(height: 20)
        }
    }

    @ViewBuilder private var fallback: some View {
        if !image.alt.isEmpty {
            Text(verbatim: image.alt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
    }
}

// MARK: - 解析

struct MarkdownImageRef: Hashable {
    var src: String
    var alt: String
    var link: String?
    /// <picture> 里给暗色模式准备的图。
    var darkSrc: String?
    /// <img width="…"> 指定的显示宽度。
    var width: CGFloat?
}

struct MarkdownListItem: Hashable {
    var indent: Int
    var number: Int?
    var checked: Bool?
    var text: String
}

enum MarkdownBlock: Hashable {
    case heading(Int, String)
    case paragraph(String)
    case list([MarkdownListItem])
    case code(String)
    case quote(String)
    case rule
    case table([String], [[String]])
    case images([MarkdownImageRef])
    /// HTML 里 align="center" 的内容。
    indirect case centered(MarkdownBlock)
}

/// 够用的 Markdown 解析：标题、段落、列表（含任务列表）、代码块、引用、分隔线、表格、图片；
/// 行内语法（粗体、斜体、行内代码、链接、删除线）交给 AttributedString。README 里的 HTML 只取图片，其余去掉标签留文字。
enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var para: [String] = []
        var i = 0

        func flush() {
            guard !para.isEmpty else { return }
            var joined = ""
            for (n, line) in para.enumerated() {
                if n > 0 { joined += para[n - 1].hasSuffix("  ") || para[n - 1].hasSuffix("\\") ? "\n" : " " }
                joined += line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\\"))
            }
            blocks.append(contentsOf: paragraphBlocks(joined))
            para = []
        }

        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)

            // 代码块
            if t.hasPrefix("```") || t.hasPrefix("~~~") {
                flush()
                let fence = String(t.prefix(3))
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[i]); i += 1
                }
                i += 1
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }
            if t.isEmpty { flush(); i += 1; continue }
            // HTML 注释
            if t.hasPrefix("<!--") {
                flush()
                while i < lines.count, !lines[i].contains("-->") { i += 1 }
                i += 1
                continue
            }
            // Setext 标题（上一行文字 + === / ---）
            if !para.isEmpty, t.count >= 2, t.allSatisfy({ $0 == "=" }) || t.allSatisfy({ $0 == "-" }) {
                let level = t.first == "=" ? 1 : 2
                let text = para.joined(separator: " ")
                para = []
                blocks.append(.heading(level, text))
                i += 1
                continue
            }
            if let h = heading(t) { flush(); blocks.append(h); i += 1; continue }
            if isRule(t) { flush(); blocks.append(.rule); i += 1; continue }
            // 引用
            if t.hasPrefix(">") {
                flush()
                var quote: [String] = []
                while i < lines.count {
                    let q = lines[i].trimmingCharacters(in: .whitespaces)
                    guard q.hasPrefix(">") else { break }
                    var body = String(q.dropFirst())
                    if body.hasPrefix(" ") { body.removeFirst() }
                    // GitHub 提示块标记（[!NOTE] 等）不显示
                    if !(body.hasPrefix("[!") && body.hasSuffix("]")) { quote.append(body) }
                    i += 1
                }
                blocks.append(.quote(quote.joined(separator: "\n")))
                continue
            }
            // 列表
            if listItem(line) != nil {
                flush()
                var items: [MarkdownListItem] = []
                while i < lines.count {
                    let l = lines[i]
                    if let item = listItem(l) {
                        items.append(item); i += 1
                    } else if l.trimmingCharacters(in: .whitespaces).isEmpty {
                        // 空行后面还是列表项就继续
                        if i + 1 < lines.count, listItem(lines[i + 1]) != nil { i += 1 } else { break }
                    } else if l.hasPrefix("  ") || l.hasPrefix("\t"), !items.isEmpty {
                        items[items.count - 1].text += " " + l.trimmingCharacters(in: .whitespaces)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.list(items))
                continue
            }
            // 表格
            if t.contains("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flush()
                let header = cells(t)
                var rows: [[String]] = []
                i += 2
                while i < lines.count {
                    let r = lines[i].trimmingCharacters(in: .whitespaces)
                    guard !r.isEmpty, r.contains("|") else { break }
                    rows.append(cells(r)); i += 1
                }
                blocks.append(.table(header, rows))
                continue
            }
            // HTML 块：只取图片，其余去标签
            if t.hasPrefix("<") && !t.hasPrefix("<http") {
                flush()
                var html: [String] = []
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    html.append(lines[i]); i += 1
                }
                blocks.append(contentsOf: htmlBlocks(html.joined(separator: "\n")))
                continue
            }
            para.append(line)
            i += 1
        }
        flush()
        return blocks
    }

    /// 行内 Markdown → AttributedString；行内代码用等宽字体加浅底，链接用品牌色。
    static func inline(_ s: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        var a = (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
        for run in a.runs {
            if run.inlinePresentationIntent?.contains(.code) == true {
                a[run.range].font = .system(size: 12, design: .monospaced)
                a[run.range].backgroundColor = Color.primary.opacity(0.08)
            }
            if run.link != nil {
                a[run.range].foregroundColor = Color.brand
            }
        }
        return a
    }

    // MARK: 块级辅助

    private static func heading(_ t: String) -> MarkdownBlock? {
        let hashes = t.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = t.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") { text.removeLast() }
        return .heading(hashes, stripHTML(text.trimmingCharacters(in: .whitespaces)))
    }

    private static func isRule(_ t: String) -> Bool {
        let chars = t.filter { $0 != " " }
        guard chars.count >= 3, let c = chars.first, "-*_".contains(c) else { return false }
        return chars.allSatisfy { $0 == c }
    }

    private static func listItem(_ line: String) -> MarkdownListItem? {
        let expanded = line.replacingOccurrences(of: "\t", with: "    ")
        let spaces = expanded.prefix { $0 == " " }.count
        let t = expanded.dropFirst(spaces)
        var number: Int?
        var rest: Substring
        if let first = t.first, "-*+".contains(first), t.dropFirst().first == " " {
            rest = t.dropFirst(2)
        } else {
            let digits = t.prefix { $0.isNumber }
            guard !digits.isEmpty, digits.count <= 3 else { return nil }
            let after = t.dropFirst(digits.count)
            guard let mark = after.first, mark == "." || mark == ")", after.dropFirst().first == " " else { return nil }
            number = Int(digits)
            rest = after.dropFirst(2)
        }
        var checked: Bool?
        if rest.hasPrefix("[ ] ") { checked = false; rest = rest.dropFirst(4) }
        else if rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") { checked = true; rest = rest.dropFirst(4) }
        return MarkdownListItem(indent: min(spaces / 2, 4), number: number, checked: checked,
                                text: stripHTML(rest.trimmingCharacters(in: .whitespaces)))
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") || t.contains(":") else { return false }
        return t.allSatisfy { "|-: ".contains($0) }
    }

    private static func cells(_ row: String) -> [String] {
        var t = row
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { stripHTML($0.trimmingCharacters(in: .whitespaces)) }
    }

    // MARK: 图片与 HTML

    private static var linkedImage: Regex<(Substring, Substring, Substring, Substring)> { /\[!\[([^\]]*)\]\(([^)\s]+)[^)]*\)\]\(([^)\s]+)[^)]*\)/ }
    private static var plainImage: Regex<(Substring, Substring, Substring)> { /!\[([^\]]*)\]\(([^)\s]+)[^)]*\)/ }

    /// 整段都是图片（徽章、截图）就按图片显示；混在文字里的图片换成替代文字。
    private static func paragraphBlocks(_ text: String) -> [MarkdownBlock] {
        let cleaned = stripHTML(text)
        var images: [MarkdownImageRef] = []
        var rest = cleaned
        for m in rest.matches(of: linkedImage) {
            images.append(MarkdownImageRef(src: String(m.2), alt: String(m.1), link: String(m.3)))
        }
        rest = rest.replacing(linkedImage) { _ in "" }
        for m in rest.matches(of: plainImage) {
            images.append(MarkdownImageRef(src: String(m.2), alt: String(m.1), link: nil))
        }
        rest = rest.replacing(plainImage) { _ in "" }
        if !images.isEmpty, rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [.images(images)]
        }
        let inlineText = cleaned
            .replacing(linkedImage) { m in m.1 }
            .replacing(plainImage) { m in m.1 }
        return inlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [.paragraph(inlineText)]
    }

    private static var imgTag: Regex<(Substring, Substring)> { /<img\s[^>]*?src\s*=\s*["']([^"']+)["'][^>]*>/.ignoresCase() }
    private static var widthAttr: Regex<(Substring, Substring)> { /width\s*=\s*["']?(\d+)/.ignoresCase() }
    private static var darkSource: Regex<(Substring, Substring)> { /<source\s[^>]*?prefers-color-scheme:\s*dark[^>]*?srcset\s*=\s*["']([^"'\s]+)/.ignoresCase() }
    private static var htmlHeading: Regex<(Substring, Substring)> { /^\s*<h([1-6])[\s>]/.ignoresCase() }
    private static var centerAttr: Regex<Substring> { /align\s*=\s*["']?center/.ignoresCase() }
    private static var anchor: Regex<(Substring, Substring, Substring)> { /<a\s[^>]*?href\s*=\s*["']([^"']+)["'][^>]*>(.*?)<\/a>/.ignoresCase() }
    private static var altAttr: Regex<(Substring, Substring)> { /alt\s*=\s*["']([^"']*)["']/.ignoresCase() }
    private static var hrefAttr: Regex<(Substring, Substring)> { /<a\s[^>]*?href\s*=\s*["']([^"']+)["'][^>]*>\s*$/.ignoresCase() }

    private static func htmlBlocks(_ html: String) -> [MarkdownBlock] {
        var images: [MarkdownImageRef] = []
        let dark = html.firstMatch(of: darkSource).map { String($0.1) }
        for m in html.matches(of: imgTag) {
            let tag = html[m.range]
            let alt = tag.firstMatch(of: altAttr).map { String($0.1) } ?? ""
            let width = tag.firstMatch(of: widthAttr).flatMap { Double($0.1) }.map { CGFloat($0) }
            // 紧挨在图片前面的 <a href> 作为点击链接
            let before = html[..<m.range.lowerBound]
            let link = before.firstMatch(of: hrefAttr).map { String($0.1) }
            images.append(MarkdownImageRef(src: String(m.1), alt: alt, link: link,
                                           darkSrc: images.isEmpty ? dark : nil, width: width))
        }
        let text = stripHTML(html).trimmingCharacters(in: .whitespacesAndNewlines)
        var blocks: [MarkdownBlock] = []
        if !images.isEmpty { blocks.append(.images(images)) }
        if !text.isEmpty {
            if let level = html.firstMatch(of: htmlHeading).flatMap({ Int($0.1) }) {
                blocks.append(.heading(level, text))
            } else {
                blocks.append(contentsOf: paragraphBlocks(text))
            }
        }
        return html.contains(centerAttr) ? blocks.map { .centered($0) } : blocks
    }

    private static var tag: Regex<(Substring, Substring?)> { /<\/?[a-zA-Z][a-zA-Z0-9]*(\s[^>]*)?\/?>/ }

    /// 去掉 HTML 标签（<br> 换成换行），保留 <https://…> 这种自动链接，并还原常见实体。
    static func stripHTML(_ s: String) -> String {
        guard s.contains("<") || s.contains("&") else { return s }
        // <a href="…">文字</a> 转成 Markdown 链接，交给行内解析
        var r = s.replacing(anchor) { m in "[\(m.2)](\(m.1))" }
        r = r.replacing(/<br\s*\/?>/.ignoresCase(), with: "\n")
        r = r.replacing(tag, with: "")
        r = r.replacing(/\[\s*\]\([^)]*\)/, with: "")   // 只包着图片的链接，图片去掉后留下的空壳
        for (entity, char) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            r = r.replacingOccurrences(of: entity, with: char)
        }
        return r
    }
}
