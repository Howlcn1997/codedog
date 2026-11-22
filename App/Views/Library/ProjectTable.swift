import CodedogCore
import SwiftUI

struct ProjectTable: View {
    @Environment(LibraryModel.self) private var model
    var rows: [(item: ProjectItem, match: SearchMatch)]

    struct Row: Identifiable {
        var item: ProjectItem
        var match: SearchMatch
        var id: String { item.id }
    }

    var body: some View {
        @Bindable var model = model
        let data = rows.map { Row(item: $0.item, match: $0.match) }
        Table(data, selection: $model.selectedID) {
            TableColumn("名称") { row in
                HStack(spacing: 10) {
                    StackBadge(project: row.item.project, size: 24)   // 和文件夹卡片同一套类型图标
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(row.item.project.name).fontWeight(.medium).lineLimit(1)
                            if row.item.meta.favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                        }
                        // 只在搜索命中名称以外的内容时显示命中原因，平时不显示路径
                        if let reason = row.match.reasons.first, !reason.hasPrefix("名称") {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .width(min: 220, ideal: 320)
            TableColumn("分支") { row in
                HStack(spacing: 4) {
                    if let dirty = row.item.project.git?.dirtyFiles, dirty > 0 {
                        Circle().fill(.orange).frame(width: 6, height: 6)
                    }
                    Text(row.item.project.git?.branch ?? "—").foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .width(min: 80, ideal: 140)
            TableColumn("标签") { row in Text(row.item.categoryNames.joined(separator: "、")).foregroundStyle(.secondary) }
                .width(min: 60, ideal: 120)
            TableColumn("最近活动") { row in Text(Formatting.activity(row.item.lastActivity)).foregroundStyle(.secondary) }
                .width(min: 70, ideal: 90)
            TableColumn("") { row in RowActions(item: row.item) }
                .width(108)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let row = data.first(where: { $0.id == id }) {
                ProjectMenu(item: row.item)
            }
        } primaryAction: { ids in
            if let id = ids.first { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.detailID = id } }
        }
        .scrollContentBackground(.hidden)
        .alternatingRowBackgrounds(.disabled)   // 不要斑马纹：空白区域也会画条纹，和背景割裂
        .background(TableSeparatorRemover())
    }
}

/// SwiftUI 的 Table 在关掉斑马纹后会画行分隔线，且 listRowSeparator 对 Table 无效。
/// 行视图（SwiftUI 私有的 NSTableRowView 子类）用 drawsSeparator 决定画不画，这里在运行时把它换掉：
/// 只对打了标记的这张表返回 false，其他表照旧。找不到类或方法时什么都不做。
private struct TableSeparatorRemover: NSViewRepresentable {
    static let marker = NSUserInterfaceItemIdentifier("codedog.projectTable")

    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        private func apply() {
            guard let root = window?.contentView else { return }
            let mine = convert(bounds, to: nil)
            // 侧栏也是 NSTableView（sourceList 样式），排除掉；剩下和自己重叠的就是这张表
            guard let table = Self.tables(in: root).first(where: { $0.style != .sourceList && $0.convert($0.visibleRect, to: nil).intersects(mine) }) else { return }
            table.identifier = TableSeparatorRemover.marker
            table.enumerateAvailableRowViews { row, _ in Self.patch(type(of: row)) }
            table.reloadData()   // 已经建好的行重新取一次 drawsSeparator
        }

        private static func tables(in view: NSView) -> [NSTableView] {
            (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(tables)
        }

        private static var patched = Set<ObjectIdentifier>()

        private static func patch(_ cls: AnyClass) {
            guard cls != NSTableRowView.self, !patched.contains(ObjectIdentifier(cls)) else { return }
            patched.insert(ObjectIdentifier(cls))
            let sel = NSSelectorFromString("drawsSeparator")
            guard let method = class_getInstanceMethod(cls, sel) else { return }
            typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
            let original = unsafeBitCast(method_getImplementation(method), to: Fn.self)
            let block: @convention(block) (NSTableRowView) -> Bool = { row in
                if (row.superview as? NSTableView)?.identifier == TableSeparatorRemover.marker { return false }
                return original(row, sel)
            }
            class_replaceMethod(cls, sel, imp_implementationWithBlock(block), method_getTypeEncoding(method))
        }
    }
}

/// 行尾快捷按钮：最近用的 AI 助手（接着上次的会话）、终端、访达。
private struct RowActions: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem

    var body: some View {
        HStack(spacing: 4) {
            if let tool = item.lastAgent?.tool {
                button(help: tool == .codex && CodexDesktop.isInstalled ? "在 Codex 中打开" : "用 \(tool.displayName) 接着上次的会话") {
                    model.open(item, .resume(tool))
                } label: {
                    ToolIcon(tool: tool, size: 16)
                }
            } else {
                Color.clear.frame(width: 28, height: 24)   // 没用过 AI 的项目留空，保持后两个按钮对齐
            }
            button(help: "在终端中打开") { model.open(item, .terminal) } label: {
                Image(systemName: "apple.terminal")
            }
            button(help: "在访达中显示") { model.open(item, .finder) } label: {
                Image(systemName: "folder")
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func button(help: String, action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
        Button(action: action) {
            label()
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
