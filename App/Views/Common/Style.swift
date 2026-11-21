import AppKit
import CodedogCore
import SwiftUI

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

/// 分类可选颜色（名称 → 颜色）。
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
    /// 口语化的活动时间："今天在做""昨天在做""3 天前""2 周前""5 个月前""2024 年"
    static func activity(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "很久没动" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天在做" }
        if cal.isDateInYesterday(date) { return "昨天在做" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        if days < 7 { return "\(days) 天前" }
        if days < 30 { return "\(days / 7) 周前" }
        if days < 365 { return "\(max(1, days / 30)) 个月前" }
        return "\(cal.component(.year, from: date)) 年"
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
        Menu("分类") {
            ForEach(model.library.categories) { c in
                Toggle(c.name, isOn: Binding(get: { item.meta.categories.contains(c.id) }, set: { _ in model.toggleCategory(item.id, c.id) }))
            }
            if !model.library.categories.isEmpty { Divider() }
            Button("新建分类…") { NotificationCenter.default.post(name: .newCategory, object: item.id) }
        }
        Divider()
        Button(item.meta.hidden ? "取消隐藏" : "隐藏", systemImage: item.meta.hidden ? "eye" : "eye.slash") {
            model.setHidden(item.id, !item.meta.hidden)
        }
    }
}

extension Notification.Name {
    /// object: 可选的项目路径（新建后自动加入该分类）
    static let newCategory = Notification.Name("codedog.newCategory")
    static let focusSearch = Notification.Name("codedog.focusSearch")
}
