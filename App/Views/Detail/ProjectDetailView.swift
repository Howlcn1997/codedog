import CodedogCore
import SwiftUI

/// 项目面板：从右侧滑出。头部与操作栏 → 指标块 → 活跃圆点图 → AI 会话 → 花费明细 → Git → 笔记。
struct ProjectDetailView: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(item: item, onClose: onClose)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 14)
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    MetricTiles(item: item)
                    ActivitySection(item: item)
                    SessionsSection(item: item)
                    CostSection(item: item)
                    GitSection(item: item)
                    NotesSection(item: item).id(item.id)
                }
                .padding(24)
            }
            .scrollIndicators(.never)
        }
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 30, x: -6, y: 10)
    }
}

private func sectionTitle(_ title: String, _ symbol: String) -> some View {
    Label(title, systemImage: symbol)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
}

// MARK: - 头部与操作

private struct PanelHeader: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                StackBadge(project: item.project, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(item.project.name)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        StatusPill(item: item)
                    }
                    Button { model.copyPath(item) } label: {
                        Text(Formatting.shortPath(item.id)).lineLimit(1).truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .help("点击复制路径")
                    Text([item.project.kind.displayName] + item.project.stacks.map(\.displayName) + [Formatting.activity(item.lastActivity)])
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 26, height: 26)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .keyboardShortcut(.cancelAction)
                .help("关闭（Esc）")
            }
            ActionBar(item: item)
        }
    }
}

private struct ActionBar: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem

    var body: some View {
        let editor = model.editor(for: item)
        let agent = item.lastAgent?.tool
        HStack(spacing: 8) {
            // 主操作：有 AI 会话时续上，否则用编辑器打开
            if let agent, !item.running.contains(agent) {
                Button { model.open(item, .resume(agent)) } label: {
                    Label { Text("续上 \(agent.displayName)") } icon: { ToolIcon(tool: agent, size: 16) }
                }
                .buttonStyle(.glassProminent)
                .tint(.brand)
                Button { model.open(item) } label: {
                    Label { Text(editor?.name ?? "打开") } icon: { if let editor { AppIconView(app: editor, size: 16) } }
                }
                .buttonStyle(.glass)
            } else {
                Button { model.open(item) } label: {
                    Label { Text(editor.map { "用 \($0.name) 打开" } ?? "打开") } icon: { if let editor { AppIconView(app: editor, size: 16) } }
                }
                .buttonStyle(.glassProminent)
                .tint(.brand)
                if let agent {
                    Label("\(agent.displayName) 运行中", systemImage: "bolt.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                }
            }
            Spacer(minLength: 0)
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    iconButton("apple.terminal", "在终端中打开") { model.open(item, .terminal) }
                    iconButton("folder", "在访达中显示") { model.open(item, .finder) }
                    iconButton("globe", "打开远程仓库") { model.open(item, .repository) }
                        .disabled(item.project.git?.webURL == nil)
                    iconButton(item.meta.favorite ? "star.fill" : "star", item.meta.favorite ? "取消收藏" : "收藏") { model.toggleFavorite(item.id) }
                        .foregroundStyle(item.meta.favorite ? .yellow : .primary)
                    Menu {
                        ForEach(AITool.allCases.filter(\.isAgent), id: \.self) { t in
                            Button("新的 \(t.displayName) 会话") { model.open(item, .newSession(t)) }
                        }
                        Divider()
                        Section("打开方式") {
                            ForEach(Opener.installedEditors, id: \.self) { app in
                                Button { model.open(item, .editor(app)) } label: {
                                    Label { Text(app.name) } icon: { Image(nsImage: AppIconView.icon(app)) }
                                }
                            }
                        }
                    } label: { Image(systemName: "ellipsis") }
                    .menuIndicator(.hidden)
                    .buttonStyle(.glass)
                    .fixedSize()
                }
            }
        }
        .controlSize(.large)
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.glass)
            .help(help)
    }
}

// MARK: - 指标块

private struct MetricTiles: View {
    var item: ProjectItem

    var body: some View {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -30, to: .now)!
        func last30(_ days: [String: Int]) -> Int {
            days.filter { key, _ in (try? Date(key + "T12:00:00Z", strategy: .iso8601)).map { $0 >= cutoff } ?? false }.values.reduce(0, +)
        }
        let cost = item.tokensByModel.compactMap { Pricing.cost(model: $0.key, usage: $0.value) }.reduce(0, +)
        let tokens = item.tokensByModel.values.map(\.total).reduce(0, +)
        return HStack(spacing: 10) {
            tile("\(last30(item.commitDays))", "30 天提交", "arrow.triangle.merge", .brand)
            tile(Formatting.tokens(last30(item.aiDays)), "30 天 AI 回复", "sparkles", .orange)
            tile(cost > 0 ? Formatting.cost(cost) : (tokens > 0 ? Formatting.tokens(tokens) : "—"), cost > 0 ? "估算花费" : "token", "dollarsign.circle", .green)
            tile("\(item.project.git?.dirtyFiles ?? 0)", "未提交文件", "plusminus.circle", .pink)
        }
    }

    private func tile(_ value: String, _ label: String, _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - 活跃圆点图

private struct ActivitySection: View {
    var item: ProjectItem
    @State private var source: Source = .all

    enum Source: String, CaseIterable { case all = "全部", commits = "提交", ai = "AI" }

    var body: some View {
        let commits = item.commitDays, ai = item.aiDays
        let days: [String: Int] = switch source {
        case .all: commits.merging(ai, uniquingKeysWith: +)
        case .commits: commits
        case .ai: ai
        }
        let active = Set(commits.filter { $0.value > 0 }.keys).union(ai.filter { $0.value > 0 }.keys).count
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("近一年 · 活跃 \(active) 天", "circle.grid.3x3.fill")
                Spacer()
                Picker("来源", selection: $source) {
                    ForEach(Source.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
            }
            HeatmapView(days: days, unit: source == .commits ? "次提交" : source == .ai ? "条 AI 回复" : "次活动")
        }
    }
}

// MARK: - AI 会话

private struct SessionsSection: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem

    var body: some View {
        let sessions = item.tools.flatMap(\.recentSessions)
            .sorted { ($0.lastAt ?? .distantPast) > ($1.lastAt ?? .distantPast) }
            .prefix(6)
        let editors = item.tools.filter { !$0.tool.isAgent }
        if !item.tools.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("AI 会话", "bubble.left.and.text.bubble.right")
                ForEach(Array(sessions.enumerated()), id: \.offset) { i, s in
                    SessionRow(item: item, session: s, isLatest: i == 0)
                }
                if !editors.isEmpty {
                    HStack(spacing: 14) {
                        ForEach(editors, id: \.tool) { t in
                            HStack(spacing: 5) {
                                ToolIcon(tool: t.tool, size: 14)
                                Text("\(t.tool.displayName) · \(Formatting.dateRange(t.firstAt, t.lastAt))")
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
            }
        }
    }
}

private struct SessionRow: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem
    var session: SessionSummary
    var isLatest: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ToolIcon(tool: session.tool, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(Formatting.plain(session.title ?? session.lastPrompt ?? "未命名会话"))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(session.lastAt.map { Formatting.relative($0) } ?? "")
                    if session.waiting && isLatest {
                        Text("· 等你回复").foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("续上") { model.open(item, .resumeSession(session)) }
                .buttonStyle(.glass)
                .controlSize(.small)
                .opacity(hovering || isLatest ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(hovering ? 0.06 : 0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering = $0 }
    }
}

// MARK: - 花费明细

private struct CostSection: View {
    var item: ProjectItem
    @State private var expanded = false

    var body: some View {
        let rows = item.tokensByModel.map { (model: $0.key, usage: $0.value, cost: Pricing.cost(model: $0.key, usage: $0.value)) }
            .filter { $0.usage.total > 0 }
            .sorted { ($0.cost ?? -1, $0.usage.total) > ($1.cost ?? -1, $1.usage.total) }
        if !rows.isEmpty {
            let total = rows.map(\.usage.total).reduce(0, +)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionTitle("模型用量 · \(Formatting.tokens(total)) token", "cpu")
                    Image(systemName: "info.circle").foregroundStyle(.tertiary)
                        .help("花费按 Anthropic 公开 API 价格估算（缓存写入按 1.25×/2× 输入价），只统计 Claude 模型；订阅用户的实际花费不同。")
                }
                ForEach(rows.prefix(expanded ? rows.count : 4), id: \.model) { r in
                    UsageBar(name: Pricing.displayName(r.model), cost: r.cost, tokens: r.usage.total, fraction: Double(r.usage.total) / Double(max(total, 1)))
                }
                if rows.count > 4 {
                    Button(expanded ? "收起" : "其余 \(rows.count - 4) 个模型") { withAnimation { expanded.toggle() } }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
        }
    }
}

private struct UsageBar: View {
    var name: String
    var cost: Double?
    var tokens: Int
    var fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).lineLimit(1)
                Spacer()
                Text(Formatting.tokens(tokens)).foregroundStyle(.secondary).monospacedDigit()
                Text(Formatting.cost(cost)).monospacedDigit().frame(minWidth: 54, alignment: .trailing)
            }
            .font(.callout)
            GeometryReader { g in
                Capsule().fill(Color.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.brand.gradient).frame(width: max(4, g.size.width * fraction))
                    }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Git

private struct GitSection: View {
    var item: ProjectItem

    var body: some View {
        if let git = item.project.git {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionTitle(git.branch ?? "Git", "arrow.triangle.branch")
                    Spacer()
                    if git.dirtyFiles > 0 {
                        Text("\(git.dirtyFiles) 个文件未提交")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.pink)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.pink.opacity(0.12), in: Capsule())
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(git.recentCommits.enumerated()), id: \.offset) { i, c in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 0) {
                                Circle().fill(c.mine ? Color.brand : Color.secondary.opacity(0.5)).frame(width: 7, height: 7).padding(.top, 5)
                                if i < git.recentCommits.count - 1 {
                                    Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1)
                                }
                            }
                            .frame(width: 7)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.subject).foregroundStyle(c.mine ? .primary : .secondary).lineLimit(2).textSelection(.enabled)
                                Text(Formatting.relative(c.date)).font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.bottom, 10)
                        }
                    }
                }
                .font(.callout)
                if let remote = git.remote {
                    Text(remote).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
            }
        }
    }
}

// MARK: - 笔记

private struct NotesSection: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem
    @State private var notes = ""
    @State private var pickingApp = false
    @State private var showReadme = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("笔记", "note.text")
            if let d = item.project.description {
                Text(Formatting.plain(d)).foregroundStyle(.secondary).textSelection(.enabled)
            }
            FlowLayout(spacing: 6) {
                ForEach(model.library.categories.filter { item.meta.categories.contains($0.id) }) { c in
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill").font(.caption2).foregroundStyle(CategoryPalette.color(c.color) ?? .secondary)
                        Text(c.name).font(.callout)
                        Button { model.toggleCategory(item.id, c.id) } label: { Image(systemName: "xmark").font(.caption2) }
                            .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                }
                Menu {
                    ForEach(model.library.categories.filter { !item.meta.categories.contains($0.id) }) { c in
                        Button(c.name) { model.toggleCategory(item.id, c.id) }
                    }
                    Divider()
                    Button("新建标签…") { NotificationCenter.default.post(name: .newCategory, object: item.id) }
                } label: { Label("标签", systemImage: "plus").font(.callout) }
                .menuStyle(.button).buttonStyle(.borderless).fixedSize()
            }

            TextField("写点备注…", text: $notes, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...8)
                .padding(10)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Text("默认打开方式").foregroundStyle(.secondary)
                Picker("编辑器", selection: Binding(get: { item.meta.editor }, set: { model.setEditor(item.id, $0) })) {
                    Text("跟随全局（\(model.library.preferences.editor?.name ?? Opener.installedEditors.first?.name ?? "未设置")）").tag(AppRef?.none)
                    Divider()
                    ForEach(editorChoices, id: \.self) { app in
                        Label { Text(app.name) } icon: { Image(nsImage: AppIconView.icon(app)) }.tag(AppRef?.some(app))
                    }
                }
                .labelsHidden().fixedSize()
                Button("其他…") { pickingApp = true }.buttonStyle(.borderless)
                Spacer()
            }
            .font(.callout)
            .fileImporter(isPresented: $pickingApp, allowedContentTypes: [.application]) { r in
                if case .success(let url) = r, let ref = Opener.appRef(at: url) { model.setEditor(item.id, ref) }
            }

            if let readme = item.project.readmeText, !readme.isEmpty {
                DisclosureGroup(item.project.readmeFile ?? "README", isExpanded: $showReadme) {
                    Text(Self.markdown(String(readme.prefix(8000))))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
            }

            Button(item.meta.hidden ? "取消隐藏" : "隐藏这个项目") { model.setHidden(item.id, !item.meta.hidden) }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { notes = item.meta.notes }
        .task(id: notes) {
            guard notes != item.meta.notes else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            model.setNotes(item.id, notes)
        }
    }

    private var editorChoices: [AppRef] {
        var list = Opener.installedEditors
        if let custom = item.meta.editor, !list.contains(custom) { list.append(custom) }
        return list
    }

    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible))) ?? AttributedString(s)
    }
}
