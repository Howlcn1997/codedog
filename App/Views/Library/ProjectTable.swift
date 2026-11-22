import CodedogCore
import SwiftUI

/// 列表形态：不带列名的紧凑行，隔行铺一层圆角底色；行尾快捷按钮鼠标移上去才出现。
/// 不用 Table：它画不出圆角斑马纹，也拿不到行级 hover。
struct ProjectTable: View {
    @Environment(LibraryModel.self) private var model
    var rows: [(item: ProjectItem, match: SearchMatch)]

    var body: some View {
        LazyVStack(spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.element.item.id) { index, row in
                ProjectRow(item: row.item, match: row.match, striped: index % 2 == 1,
                           isSelected: model.selectedID == row.item.id) {
                    model.selectedID = row.item.id
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.detailID = row.item.id }
                }
                .contextMenu { ProjectMenu(item: row.item) }
                .help(Formatting.shortPath(row.item.id))
            }
        }
    }
}

private struct ProjectRow: View {
    var item: ProjectItem
    var match: SearchMatch
    var striped: Bool
    var isSelected: Bool
    var open: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                StackBadge(project: item.project, size: 24)   // 和文件夹卡片同一套类型图标
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(item.project.name).fontWeight(.medium).foregroundStyle(.primary).lineLimit(1)
                        if item.meta.favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    }
                    // 只在搜索命中名称以外的内容时显示命中原因，平时不显示路径
                    if let reason = match.reasons.first, !reason.hasPrefix(String(localized: "名称")) {
                        Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                if let dirty = item.project.git?.dirtyFiles, dirty > 0 {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                }
                Text(item.project.git?.branch ?? "—").lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)

            Text(item.categoryNames.joined(separator: "、")).lineLimit(1)
                .frame(width: 110, alignment: .leading)

            Text(Formatting.activity(item.lastActivity)).lineLimit(1)
                .frame(width: 80, alignment: .leading)

            // 平时藏起来，鼠标移到这一行（或选中它）才出现
            let showActions = hovering || isSelected
            RowActions(item: item)
                .opacity(showActions ? 1 : 0)
                .allowsHitTesting(showActions)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(background)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onTapGesture(perform: open)
    }

    private var background: some View {
        let fill: AnyShapeStyle = isSelected ? AnyShapeStyle(Color.brand.opacity(0.16))
            : hovering ? AnyShapeStyle(.primary.opacity(0.07))
            : striped ? AnyShapeStyle(.primary.opacity(0.035))
            : AnyShapeStyle(.clear)
        return RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill)
    }
}

/// 行尾快捷按钮：最近用的 AI 助手（接着上次的会话）、终端、访达。
private struct RowActions: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem

    var body: some View {
        HStack(spacing: 2) {
            if let tool = item.lastAgent?.tool {
                button(help: model.resumeHelp(item, tool: tool)) {
                    model.open(item, .resume(tool))
                } label: {
                    ToolIcon(tool: tool, size: 16)
                }
            } else {
                Color.clear.frame(width: 28, height: 26)   // 没用过 AI 的项目留空，保持后两个按钮对齐
            }
            button(help: String(localized: "在终端中打开")) { model.open(item, .terminal) } label: {
                Image(systemName: "apple.terminal")
            }
            button(help: String(localized: "在访达中显示")) { model.open(item, .finder) } label: {
                Image(systemName: "folder")
            }
        }
    }

    private func button(help: String, action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
        Button(action: action) {
            label().font(.system(size: 14))
        }
        .buttonStyle(RowActionStyle())
        .help(help)
    }
}

/// 行尾图标按钮：悬停时浮出圆角底色、图标变亮，按下时稍微缩小
private struct RowActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowActionButton(configuration: configuration)
    }
}

private struct RowActionButton: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(hovering ? .primary : .secondary)
            .frame(width: 28, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.primary.opacity(configuration.isPressed ? 0.18 : hovering ? 0.10 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}
