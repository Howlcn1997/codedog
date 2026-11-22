import AppKit
import CodedogCore
import SwiftUI

extension Color {
    /// codedog 品牌紫，固定使用，不跟随系统强调色。
    static let brand = Color(red: 0x65 / 255, green: 0x63 / 255, blue: 0xDA / 255)
}

/// 外观偏好：跟随系统 / 亮色 / 暗色，直接作用于整个 App（主窗口、启动器、菜单栏面板）。
enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: String(localized: "跟随系统")
        case .light: String(localized: "亮色")
        case .dark: String(localized: "暗色")
        }
    }

    @MainActor static func apply(_ raw: String) {
        switch AppearanceMode(rawValue: raw) ?? .system {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
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
        ("red", String(localized: "红色"), .red), ("orange", String(localized: "橙色"), .orange), ("yellow", String(localized: "黄色"), .yellow),
        ("green", String(localized: "绿色"), .green), ("teal", String(localized: "青色"), .teal), ("blue", String(localized: "蓝色"), .blue),
        ("purple", String(localized: "紫色"), .purple), ("pink", String(localized: "粉色"), .pink), ("brown", String(localized: "棕色"), .brown),
        ("gray", String(localized: "灰色"), .gray),
    ]

    static func color(_ id: String?) -> Color? {
        guard let id else { return nil }
        return all.first { $0.id == id }?.color
    }
}

/// 文件夹卡片的颜色：克制的浅色调，深一号的同色字。不选颜色时是灰色。
enum FolderPalette {
    static let all: [(id: String, name: String, base: UInt32)] = [
        ("blue", String(localized: "蓝色"), 0x4A7BE0), ("purple", String(localized: "紫色"), 0x9468DC),
        ("pink", String(localized: "粉色"), 0xDD5E98), ("red", String(localized: "红色"), 0xDE5A55),
        ("orange", String(localized: "橙色"), 0xE5843A), ("yellow", String(localized: "黄色"), 0xD6A626),
        ("green", String(localized: "绿色"), 0x43A466), ("teal", String(localized: "青色"), 0x2F9FAA),
        ("brown", String(localized: "棕色"), 0x9A7257),
    ]
    static let grayBase: UInt32 = 0x7E7E86

    static func name(_ id: String) -> String { all.first { $0.id == id }?.name ?? id }
    static func base(_ id: String?) -> Color { Color(hex: all.first { $0.id == id }?.base ?? grayBase) }

    struct Style {
        var front: Color
        var back: Color
        var text: Color
        var shadow: Color
        /// 轮廓描边：浅色底上靠它把边缘勾清楚
        var edge: Color
    }

    static func style(_ id: String?, dark: Bool) -> Style {
        let b = base(id)
        if dark {
            let ground = Color(hex: 0x2A2A2E)
            return Style(front: b.mix(with: ground, by: 0.55), back: b.mix(with: ground, by: 0.7),
                         text: b.mix(with: .white, by: 0.6), shadow: .black.opacity(0.35), edge: .white.opacity(0.08))
        }
        return Style(front: b.mix(with: .white, by: 0.58), back: b.mix(with: .white, by: 0.74),
                     text: b.mix(with: .black, by: 0.38), shadow: b.mix(with: .black, by: 0.3).opacity(0.22),
                     edge: b.mix(with: .black, by: 0.25).opacity(0.16))
    }

    /// 菜单里的色块：菜单会把 SF Symbol 渲染成单色，只能画成非模板图片。
    @MainActor static func swatch(_ id: String) -> NSImage {
        if let img = swatches[id] { return img }
        let color = NSColor(base(id))
        let img = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
            color.setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        img.isTemplate = false
        swatches[id] = img
        return img
    }
    @MainActor private static var swatches: [String: NSImage] = [:]
}

enum Formatting {
    /// 口语化的活动时间："今天活跃""昨天活跃""3 天前""2 周前""5 个月前""2024 年"
    static func activity(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return String(localized: "很久没动") }
        let cal = Calendar.current
        if date > now || cal.isDateInToday(date) { return String(localized: "今天活跃") }
        if cal.isDateInYesterday(date) { return String(localized: "昨天活跃") }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        if days < 7 { return String(localized: "\(days) 天前") }
        if days < 30 { return String(localized: "\(days / 7) 周前") }
        if days < 365 { return String(localized: "\(max(1, days / 30)) 个月前") }
        return date.formatted(.dateTime.year().locale(AppLanguage.locale))
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
        Picker("颜色", selection: Binding(get: { item.meta.color }, set: { model.setColor(item.id, $0) })) {
            Image(systemName: "circle.slash").help("无颜色").tag(String?.none)
            ForEach(FolderPalette.all, id: \.id) { p in
                Image(nsImage: FolderPalette.swatch(p.id)).help(p.name).tag(Optional(p.id))
            }
        }
        .pickerStyle(.palette)
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
    static let debugSettingsPage = Notification.Name("codedog.debugSettingsPage")
}

extension Formatting {
    /// 按界面语言缩写：15亿、7.6万、980；英文为 1.5B、76K。
    static func tokens(_ n: Int) -> String {
        n.formatted(.number.notation(.compactName).locale(AppLanguage.locale))
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
        let f = { (d: Date) in day(d, withYear: !sameYear) }
        return cal.isDate(a, inSameDayAs: b) ? f(a) : "\(f(a)) – \(f(b))"
    }

    /// 按界面语言格式化日期：11月22日 / Nov 22，需要时带年份。
    static func day(_ d: Date, withYear: Bool) -> String {
        let style = Date.FormatStyle(locale: AppLanguage.locale).month(.abbreviated).day()
        return d.formatted(withYear ? style.year() : style)
    }

    /// 4 分钟前、5 小时前、昨天、3 天前
    static func relative(_ date: Date, now: Date = .now) -> String {
        let s = now.timeIntervalSince(date)
        if s < 60 { return String(localized: "刚刚") }
        if s < 3600 { return String(localized: "\(Int(s / 60)) 分钟前") }
        if Calendar.current.isDateInToday(date) { return String(localized: "\(Int(s / 3600)) 小时前") }
        if Calendar.current.isDateInYesterday(date) { return String(localized: "昨天") }
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
