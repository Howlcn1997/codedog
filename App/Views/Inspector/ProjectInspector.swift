import CodedogCore
import SwiftUI

struct ProjectInspector: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        if let item = model.selectedItem {
            InspectorContent(item: item).id(item.id)
        } else {
            ContentUnavailableView("未选择项目", systemImage: "sidebar.right", description: Text("点选一个项目查看详情。"))
        }
    }
}

private struct InspectorContent: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem
    @State private var notes = ""
    @State private var pickingApp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                actions
                if let git = item.project.git { gitSection(git) }
                categorySection
                editorSection
                notesSection
                if let readme = item.project.readmeText, !readme.isEmpty { readmeSection(readme) }
                Button(item.meta.hidden ? "取消隐藏" : "隐藏这个项目", systemImage: item.meta.hidden ? "eye" : "eye.slash") {
                    model.setHidden(item.id, !item.meta.hidden)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .onAppear { notes = item.meta.notes }
        .task(id: notes) {
            guard notes != item.meta.notes else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            model.setNotes(item.id, notes)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: item.project.kind.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 46, height: 46)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.project.name).font(.title2.bold()).lineLimit(2)
                    Text([item.project.kind.displayName] + item.project.stacks.map(\.displayName) + [Formatting.activity(item.lastActivity)])
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    model.toggleFavorite(item.id)
                } label: {
                    Image(systemName: item.meta.favorite ? "star.fill" : "star")
                        .foregroundStyle(item.meta.favorite ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)
                .help(item.meta.favorite ? "取消收藏" : "收藏")
            }
            if let d = item.project.description {
                Text(d).font(.callout).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
            }
            Button {
                model.copyPath(item)
            } label: {
                Label(Formatting.shortPath(item.id), systemImage: "folder")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("点击复制路径")
        }
    }

    private var actions: some View {
        let editor = model.editor(for: item)
        return VStack(spacing: 10) {
            Button {
                model.open(item)
            } label: {
                HStack {
                    if let editor { AppIconView(app: editor, size: 18) }
                    Text(editor.map { "在 \($0.name) 中打开" } ?? "打开")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    actionButton("终端", "apple.terminal") { model.open(item, .terminal) }
                    actionButton("访达", "folder") { model.open(item, .finder) }
                    actionButton("仓库", "globe") { model.open(item, .repository) }
                        .disabled(item.project.git?.webURL == nil)
                }
            }
        }
    }

    private func actionButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.regular)
    }

    private func gitSection(_ git: GitInfo) -> some View {
        section("Git") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch").foregroundStyle(.secondary)
                    Text(git.branch ?? "—").fontWeight(.medium)
                    Spacer()
                    if git.dirtyFiles > 0 {
                        Label("\(git.dirtyFiles) 处改动", systemImage: "circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("已全部提交").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !git.recentCommits.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(git.recentCommits.enumerated()), id: \.offset) { _, c in
                            Text("· " + c).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                if let remote = git.remote {
                    Text(remote).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
            }
        }
    }

    private var categorySection: some View {
        section("分类") {
            FlowLayout(spacing: 6) {
                ForEach(model.library.categories.filter { item.meta.categories.contains($0.id) }) { c in
                    HStack(spacing: 4) {
                        Circle().fill(CategoryPalette.color(c.color) ?? .secondary).frame(width: 7, height: 7)
                        Text(c.name).font(.callout)
                        Button { model.toggleCategory(item.id, c.id) } label: { Image(systemName: "xmark").font(.caption2) }
                            .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: Capsule())
                }
                Menu {
                    ForEach(model.library.categories.filter { !item.meta.categories.contains($0.id) }) { c in
                        Button(c.name) { model.toggleCategory(item.id, c.id) }
                    }
                    Divider()
                    Button("新建分类…") { NotificationCenter.default.post(name: .newCategory, object: item.id) }
                } label: {
                    Label("添加", systemImage: "plus").font(.callout)
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .fixedSize()
            }
        }
    }

    private var editorSection: some View {
        section("打开方式") {
            Picker("编辑器", selection: Binding(
                get: { item.meta.editor },
                set: { model.setEditor(item.id, $0) })) {
                Text("跟随默认（\(model.library.preferences.editor?.name ?? Opener.installedEditors.first?.name ?? "未设置")）").tag(AppRef?.none)
                Divider()
                ForEach(editorChoices, id: \.self) { app in
                    Label { Text(app.name) } icon: { Image(nsImage: AppIconView.icon(app)) }.tag(AppRef?.some(app))
                }
            }
            .labelsHidden()
            Button("选择其他 App…") { pickingApp = true }
                .buttonStyle(.borderless)
                .font(.caption)
                .fileImporter(isPresented: $pickingApp, allowedContentTypes: [.application]) { result in
                    if case .success(let url) = result, let ref = Opener.appRef(at: url) { model.setEditor(item.id, ref) }
                }
        }
    }

    private var editorChoices: [AppRef] {
        var list = Opener.installedEditors
        if let custom = item.meta.editor, !list.contains(custom) { list.append(custom) }
        return list
    }

    private var notesSection: some View {
        section("备注") {
            TextEditor(text: $notes)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 70)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func readmeSection(_ text: String) -> some View {
        section(item.project.readmeFile ?? "README") {
            Text(Self.markdown(String(text.prefix(6000))))
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible))) ?? AttributedString(s)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }
}

extension Text {
    /// 用 " · " 连接多段文字。
    init(_ parts: [String]) { self.init(parts.filter { !$0.isEmpty }.joined(separator: " · ")) }
}

/// 简单的换行布局（分类胶囊）。
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
