import CodedogCore
import SwiftUI

/// 启动器：大号搜索框 → 结果列表 → 底部操作条。全键盘：↑↓ 选项目，←→ 选操作，↵ 执行。
struct LauncherView: View {
    @Environment(LibraryModel.self) private var model
    @Bindable var state: LauncherState
    var onClose: () -> Void
    @FocusState private var focused: Bool

    struct Action: Identifiable, Equatable {
        var id: String
        var title: String
        var symbol: String
        var tool: AITool?
        var run: OpenAction
        static func == (a: Action, b: Action) -> Bool { a.id == b.id }
    }

    private var results: [(item: ProjectItem, match: SearchMatch)] {
        let visible = model.items.filter { !$0.meta.hidden }
        return Array(ProjectSearch.search(visible, query: state.query, document: \.searchDocument, by: LibrarySnapshot.defaultOrder).prefix(50))
    }

    private func actions(for item: ProjectItem) -> [Action] {
        let editor = model.editor(for: item)
        var list = [Action(id: "editor", title: editor?.name ?? "编辑器", symbol: "chevron.left.forwardslash.chevron.right", run: .editor(nil))]
        if let agent = item.lastAgent?.tool, !item.running.contains(agent) {
            list.append(Action(id: "resume", title: "续上 \(agent.displayName)", symbol: "arrow.uturn.forward", tool: agent, run: .resume(agent)))
        }
        list.append(Action(id: "terminal", title: "终端", symbol: "apple.terminal", run: .terminal))
        list.append(Action(id: "finder", title: "访达", symbol: "folder", run: .finder))
        if item.project.git?.webURL != nil {
            list.append(Action(id: "repo", title: "仓库", symbol: "globe", run: .repository))
        }
        return list
    }

    var body: some View {
        let rows = results
        let selected = rows.indices.contains(state.selection) ? rows[state.selection].item : nil
        let acts = selected.map(actions) ?? []
        VStack(spacing: 0) {
            searchField
            Divider().opacity(0.4)
            if rows.isEmpty {
                if state.query.isEmpty {
                    EmptyStateView("还没有项目", symbol: "tray", message: "在主窗口里添加放代码的文件夹。", compact: true)
                } else {
                    EmptyStateView("没有找到“\(state.query)”", symbol: "magnifyingglass", message: "可以搜项目名、README 里的内容或依赖名。", compact: true)
                }
            } else {
                list(rows)
            }
            Divider().opacity(0.4)
            actionBar(acts)
        }
        .frame(width: LauncherController.size.width, height: LauncherController.size.height)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onChange(of: state.query) { state.selection = 0; state.action = 0 }
        .onChange(of: state.selection) { state.action = 0 }
        .onChange(of: state.focusToken, initial: true) { focused = true }
        .onKeyPress(.upArrow) { move(-1, count: rows.count); return .handled }
        .onKeyPress(.downArrow) { move(1, count: rows.count); return .handled }
        .onKeyPress(.leftArrow) { state.action = acts.isEmpty ? 0 : (state.action - 1 + acts.count) % acts.count; return .handled }
        .onKeyPress(.rightArrow) { state.action = acts.isEmpty ? 0 : (state.action + 1) % acts.count; return .handled }
        .onKeyPress(.return, phases: .down) { press in
            guard let selected else { return .handled }  // 只监听 .down，按住不放的重复事件不会触发
            // ⌘↵ 续上 AI，⌥↵ 终端，否则执行当前选中的操作
            if press.modifiers.contains(.command), let a = acts.first(where: { $0.id == "resume" }) { run(a, selected) }
            else if press.modifiers.contains(.option), let a = acts.first(where: { $0.id == "terminal" }) { run(a, selected) }
            else if acts.indices.contains(state.action) { run(acts[state.action], selected) }
            return .handled
        }
        .onKeyPress(.escape) {
            if state.query.isEmpty { onClose() } else { state.query = "" }
            return .handled
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("搜索项目、README、依赖…", text: $state.query)
                .textFieldStyle(.plain)
                .font(.system(size: 21, weight: .regular))
                .focused($focused)
            if !state.query.isEmpty {
                Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 62)
    }

    private func list(_ rows: [(item: ProjectItem, match: SearchMatch)]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if state.query.isEmpty {
                        Text("常用").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 6)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.item.id) { i, row in
                        LauncherRow(item: row.item, match: row.match, selected: i == state.selection)
                            .onTapGesture { state.selection = i }
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                if let a = actions(for: row.item).first { run(a, row.item) }
                            })
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.never)
            .onChange(of: state.selection) { _, i in
                guard rows.indices.contains(i) else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(rows[i].item.id) }
            }
        }
    }

    private func actionBar(_ acts: [Action]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(acts.enumerated()), id: \.element.id) { i, a in
                let on = i == state.action
                HStack(spacing: 5) {
                    if let tool = a.tool { ToolIcon(tool: tool, size: 13) } else { Image(systemName: a.symbol).font(.system(size: 11, weight: .semibold)) }
                    Text(a.title).lineLimit(1)
                }
                .font(.system(size: 12, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(on ? Color.brand : Color.primary.opacity(0.07), in: Capsule())
                .onTapGesture { state.action = i }
            }
            Spacer(minLength: 8)
            Text("↑↓ 选择  ←→ 操作  ↵ 执行  ⌘↵ 续上 AI  esc 关闭")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    private func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        state.selection = (state.selection + delta + count) % count
    }

    private func run(_ action: Action, _ item: ProjectItem) {
        onClose()
        model.open(item, action.run)
    }
}

/// 半叠放的工具图标：每个图标放在圆形底座里，后一个压住前一个的一半左右。
private struct ToolStack: View {
    var tools: [AITool]
    private let chip: CGFloat = 24

    var body: some View {
        HStack(spacing: -chip * 0.4) {
            ForEach(Array(tools.enumerated()), id: \.element) { i, tool in
                ToolIcon(tool: tool, size: 14)
                    .frame(width: chip, height: chip)
                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                    .overlay(Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.12), radius: 1.5, x: -1, y: 0.5)
                    .zIndex(Double(i))
            }
        }
    }
}

private struct LauncherRow: View {
    var item: ProjectItem
    var match: SearchMatch
    var selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            StackBadge(project: item.project, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.project.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    if item.meta.favorite { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow) }
                }
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            StatusPill(item: item)
            ToolStack(tools: item.tools.prefix(3).map(\.tool))
            Text(Formatting.activity(item.lastActivity))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(selected ? Color.brand.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }

    private var detail: String {
        if let r = match.reasons.first, !r.hasPrefix("名称") { return r }
        return Formatting.shortPath(item.id)
    }
}
