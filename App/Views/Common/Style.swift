import AppKit
import CodedogCore
import SwiftUI

extension Color {
    /// codedog 品牌紫，固定使用，不跟随系统强调色。
    static let brand = Color(red: 0x65 / 255, green: 0x63 / 255, blue: 0xDA / 255)
}

extension ProjectKind {
    var symbol: String {
        switch self {
        case .web: "safari"
        case .app: "macwindow"
        case .service: "server.rack"
        case .tool: "apple.terminal"
        case .library: "shippingbox"
        case .other: "folder"
        }
    }
}

/// 标签可选颜色（名称 → 颜色）。
enum CategoryPalette {
    static let all: [(id: String, name: String, color: Color)] = [
        ("red", "红色", .red), ("orange", "橙色", .orange), ("yellow", "黄色", .yellow),
        ("green", "绿色", .green), ("teal", "青色", .teal), ("blue", "蓝色", .blue),
        ("purple", "紫色", .purple), ("pink", "粉色", .pink), ("brown", "棕色", .brown), ("gray", "灰色", .gray),
    ]

    static func color(_ id: String?) -> Color? {
        guard let id else { return nil }
        return all.first { $0.id == id }?.color
    }
}

enum Formatting {
    /// 口语化的活动时间："今天活跃""昨天活跃""3 天前""2 周前""5 个月前""2024 年"
    static func activity(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "很久没动" }
        let cal = Calendar.current
        if date > now || cal.isDateInToday(date) { return "今天活跃" }
        if cal.isDateInYesterday(date) { return "昨天活跃" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        if days < 7 { return "\(days) 天前" }
        if days < 30 { return "\(days / 7) 周前" }
        if days < 365 { return "\(max(1, days / 30)) 个月前" }
        return "\(cal.component(.year, from: date)) 年"
    }

    /// 去掉 Markdown 标记，压成一行。
    static func plain(_ s: String) -> String {
        s.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[*_`#>]+"#, with: "", options: .regularExpression)
            .split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    static func shortPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// 本机 App 图标（编辑器、终端）。
struct AppIconView: View {
    var app: AppRef
    var size: CGFloat = 16

    var body: some View {
        Image(nsImage: Self.icon(app))
            .resizable()
            .frame(width: size, height: size)
    }

    @MainActor static func icon(_ app: AppRef) -> NSImage {
        if let url = Opener.appURL(app) { return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)) }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }
}

/// 项目右键菜单，卡片与列表共用。
struct ProjectMenu: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem

    var body: some View {
        let current = model.editor(for: item)
        Button {
            model.open(item)
        } label: {
            Label(current.map { "在 \($0.name) 中打开" } ?? "打开", systemImage: "arrow.up.forward.app")
        }
        Menu("打开方式") {
            ForEach(Opener.installedEditors, id: \.self) { app in
                Button {
                    model.open(item, .editor(app))
                } label: {
                    Label { Text(app.name) } icon: { Image(nsImage: AppIconView.icon(app)) }
                }
            }
        }
        Button("在终端中打开", systemImage: "apple.terminal") { model.open(item, .terminal) }
        Button("在访达中显示", systemImage: "folder") { model.open(item, .finder) }
        if item.project.git?.webURL != nil {
            Button("打开远程仓库", systemImage: "globe") { model.open(item, .repository) }
        }
        Button("复制路径", systemImage: "doc.on.doc") { model.copyPath(item) }
        Divider()
        Button(item.meta.favorite ? "取消收藏" : "收藏", systemImage: item.meta.favorite ? "star.slash" : "star") {
            model.toggleFavorite(item.id)
        }
        Menu("标签") {
            ForEach(model.library.categories) { c in
                Toggle(c.name, isOn: Binding(get: { item.meta.categories.contains(c.id) }, set: { _ in model.toggleCategory(item.id, c.id) }))
            }
            if !model.library.categories.isEmpty { Divider() }
            Button("新建标签…") { NotificationCenter.default.post(name: .newCategory, object: item.id) }
        }
        Divider()
        Button(item.meta.hidden ? "取消隐藏" : "隐藏", systemImage: item.meta.hidden ? "eye" : "eye.slash") {
            model.setHidden(item.id, !item.meta.hidden)
        }
    }
}

extension Notification.Name {
    /// object: 可选的项目路径（新建后自动加入该标签）
    static let newCategory = Notification.Name("codedog.newCategory")
    static let focusSearch = Notification.Name("codedog.focusSearch")
    static let openSettingsRequest = Notification.Name("codedog.openSettings")
    static let debugSheet = Notification.Name("codedog.debugSheet")
}

extension Formatting {
    /// 15亿、5755万、7.6万、980
    static func tokens(_ n: Int) -> String {
        func trim(_ v: Double) -> String { v < 10 ? String(format: "%.1f", v).replacingOccurrences(of: ".0", with: "") : String(Int(v.rounded())) }
        if n >= 100_000_000 { return trim(Double(n) / 100_000_000) + "亿" }
        if n >= 10_000 { return trim(Double(n) / 10_000) + "万" }
        return "\(n)"
    }

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func cost(_ v: Double?) -> String {
        guard let v else { return "—" }
        if v >= 1 { return "$\(Int(v.rounded()))" }
        return v >= 0.01 ? String(format: "$%.2f", v) : "<$0.01"
    }

    /// 11月10日 – 11月21日（跨年时带年份）
    static func dateRange(_ a: Date?, _ b: Date?) -> String {
        guard let a, let b else { return "" }
        let cal = Calendar.current
        let sameYear = cal.component(.year, from: a) == cal.component(.year, from: b) && cal.component(.year, from: b) == cal.component(.year, from: .now)
        func f(_ d: Date) -> String {
            let c = cal.dateComponents([.year, .month, .day], from: d)
            return sameYear ? "\(c.month!)月\(c.day!)日" : "\(c.year!)年\(c.month!)月\(c.day!)日"
        }
        return cal.isDate(a, inSameDayAs: b) ? f(a) : "\(f(a)) – \(f(b))"
    }

    /// 4 分钟前、5 小时前、昨天、3 天前
    static func relative(_ date: Date, now: Date = .now) -> String {
        let s = now.timeIntervalSince(date)
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(Int(s / 60)) 分钟前" }
        if Calendar.current.isDateInToday(date) { return "\(Int(s / 3600)) 小时前" }
        if Calendar.current.isDateInYesterday(date) { return "昨天" }
        return activity(date, now: now)
    }
}

/// AI / 编辑工具图标：使用各工具真实的品牌标志（矢量资源，见 docs/assets/ICONS.md）。
/// 彩色标志保留原色；单色标志随亮/暗模式显示为黑或白。
struct ToolIcon: View {
    var tool: AITool
    var size: CGFloat = 18

    var body: some View {
        let (asset, mono) = Self.asset(tool)
        if mono {
            Image(asset).renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
        } else {
            Image(asset).renderingMode(.original).resizable().scaledToFit()
                .frame(width: size, height: size)
        }
    }

    static func asset(_ tool: AITool) -> (name: String, mono: Bool) {
        switch tool {
        case .claudeCode: ("Tool/claude", false)
        case .codex: ("Tool/openai", true)
        case .cursor: ("Tool/cursor", true)
        case .vscode: ("Tool/vscode", false)
        case .windsurf: ("Tool/windsurf", true)
        case .trae: ("Tool/trae", false)
        }
    }
}

extension Text {
    /// 用 " · " 连接多段文字。
    init(_ parts: [String]) { self.init(parts.filter { !$0.isEmpty }.joined(separator: " · ")) }
}

/// 简单的换行布局（标签胶囊）。
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in arrange(proposal: proposal, subviews: subviews).points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
