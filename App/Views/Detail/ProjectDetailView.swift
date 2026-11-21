import CodedogCore
import SwiftUI

/// 项目详情：左侧大卡片与操作，右侧工具时间线、热力图、token 用量、Git 与笔记。
struct ProjectDetailView: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(spacing: 26) {
                Spacer(minLength: 0)
                FolderCard(item: item, match: SearchMatch(rank: 0, reasons: []), isSelected: false)
                    .scaleEffect(1.4)
                    .frame(width: FolderCard.size.width * 1.4, height: FolderCard.size.height * 1.4)
                    .allowsHitTesting(false)
                DetailActions(item: item)
                Spacer(minLength: 0)
            }
            .frame(width: 340)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    ToolTimeline(item: item)
                    ActivitySection(item: item)
                    TokenSection(item: item)
                    GitSection(item: item)
                    NotesSection(item: item).id(item.id)
                }
                .padding(26)
            }
            .scrollIndicators(.never)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .padding(.horizontal, 36)
        .padding(.top, 52)
        .padding(.bottom, 28)
    }
}

// MARK: - 左侧操作

private struct DetailActions: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem

    var body: some View {
        let editor = model.editor(for: item)
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                primary
                Button { model.open(item) } label: {
                    if let editor { AppIconView(app: editor, size: 20) } else { Image(systemName: "arrow.up.forward.app") }
                }
                .help(editor.map { "在 \($0.name) 中打开" } ?? "打开")
                Button { model.open(item, .terminal) } label: { Image(systemName: "apple.terminal") }
                    .help("在终端中打开")
                Button { model.open(item, .finder) } label: { Image(systemName: "folder") }
                    .help("在访达中显示")
                Button { model.toggleFavorite(item.id) } label: {
                    Image(systemName: item.meta.favorite ? "star.fill" : "star")
                        .foregroundStyle(item.meta.favorite ? .yellow : .primary)
                }
                .help(item.meta.favorite ? "取消收藏" : "收藏")
            }
            .buttonStyle(.glass)
            .controlSize(.extraLarge)
        }
    }

    /// 主按钮：智能体运行中 → "已在运行"；有会话 → "继续 X"；否则用编辑器打开。
    @ViewBuilder private var primary: some View {
        let agent = item.lastAgent?.tool
        let isRunning = agent.map { item.running.contains($0) } ?? false
        Menu {
            ForEach(AITool.allCases.filter(\.isAgent), id: \.self) { tool in
                if item.tools.contains(where: { $0.tool == tool && $0.lastSession != nil }) {
                    Button("继续 \(tool.displayName) 上次的会话") { model.open(item, .resume(tool)) }
                }
                Button("新的 \(tool.displayName) 会话") { model.open(item, .newSession(tool)) }
            }
            Divider()
            Section("打开方式") {
                ForEach(Opener.installedEditors, id: \.self) { app in
                    Button { model.open(item, .editor(app)) } label: {
                        Label { Text(app.name) } icon: { Image(nsImage: AppIconView.icon(app)) }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let agent { ToolIcon(tool: agent, size: 18) }
                Text(agent.map { isRunning ? "已在运行" : "继续 \($0.displayName)" } ?? "打开")
                    .fontWeight(.semibold)
            }
        } primaryAction: {
            if let agent, !isRunning { model.open(item, .resume(agent)) } else if agent == nil { model.open(item) }
        }
        .menuStyle(.button)
        .buttonStyle(.glassProminent)
        .fixedSize()
        .help(isRunning ? "\(agent!.displayName) 正在这个项目里运行" : "")
    }
}

// MARK: - 工具时间线

private struct ToolTimeline: View {
    var item: ProjectItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if item.tools.isEmpty {
                HStack {
                    Text(item.project.name).font(.title2.bold())
                    Spacer()
                    status
                }
                Text("还没有发现 AI 工具或编辑器的使用记录。").foregroundStyle(.secondary)
            }
            ForEach(Array(item.tools.enumerated()), id: \.element.tool) { i, t in
                HStack(alignment: .center, spacing: 10) {
                    ToolIcon(tool: t.tool, size: 22)
                    Text(t.tool.displayName).font(.system(size: 19, weight: .semibold))
                    Text(Formatting.dateRange(t.firstAt, t.lastAt)).foregroundStyle(.secondary)
                    if item.running.contains(t.tool) {
                        Label("运行中", systemImage: "circle.fill").labelStyle(.titleAndIcon).font(.caption).foregroundStyle(.green)
                    }
                    Spacer()
                    if i == 0 { status }
                }
                if let s = t.lastSession, let title = s.title ?? s.lastPrompt, t.tool.isAgent {
                    Text("上次：\(Formatting.plain(title))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.leading, 32)
                }
            }
        }
    }

    @ViewBuilder private var status: some View {
        if item.waiting {
            Label("在等你", systemImage: "circle.fill").labelStyle(.titleAndIcon).foregroundStyle(.orange).font(.callout)
        } else {
            Text(Formatting.activity(item.lastActivity)).foregroundStyle(.secondary).font(.callout)
        }
    }
}

// MARK: - 热力图

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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(summary(commits: commits, ai: ai)).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Picker("来源", selection: $source) {
                    ForEach(Source.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            HeatmapView(days: days, unit: source == .commits ? "次提交" : source == .ai ? "条 AI 回复" : "次活动")
        }
    }

    private func summary(commits: [String: Int], ai: [String: Int]) -> String {
        let c = commits.values.reduce(0, +), a = ai.values.reduce(0, +)
        let activeDays = Set(commits.filter { $0.value > 0 }.keys).union(ai.filter { $0.value > 0 }.keys).count
        return "近一年 \(c) 次提交 · \(Formatting.tokens(a)) 条 AI 回复 · 活跃 \(activeDays) 天"
    }
}

// MARK: - token 用量

private struct TokenSection: View {
    var item: ProjectItem
    @State private var expanded = false

    var body: some View {
        let rows = item.tokensByModel.map { (model: $0.key, usage: $0.value, cost: Pricing.cost(model: $0.key, usage: $0.value)) }
            .filter { $0.usage.total > 0 }
            .sorted { $0.usage.total > $1.usage.total }
        if !rows.isEmpty {
            let totalCost = rows.compactMap(\.cost).reduce(0, +)
            let totalTokens = rows.map(\.usage.total).reduce(0, +)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("按 API 价约 \(Formatting.cost(totalCost)) · \(Formatting.tokens(totalTokens)) token")
                        .font(.headline)
                    Image(systemName: "info.circle").foregroundStyle(.tertiary)
                        .help("按 Anthropic 公开 API 价格估算（缓存写入按 1.25×/2× 输入价），只统计 Claude 模型；订阅用户的实际花费不同。")
                }
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    ForEach(rows.prefix(expanded ? rows.count : 6), id: \.model) { r in
                        GridRow {
                            Text(Pricing.displayName(r.model)).foregroundStyle(.secondary).lineLimit(1)
                            Text(Formatting.cost(r.cost)).monospacedDigit().gridColumnAlignment(.trailing)
                            Text(Formatting.tokens(r.usage.total)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.callout)
                if rows.count > 6 {
                    Button(expanded ? "收起" : "还有 \(rows.count - 6) 个模型") { withAnimation { expanded.toggle() } }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
        }
    }
}

// MARK: - Git

private struct GitSection: View {
    var item: ProjectItem

    var body: some View {
        if let git = item.project.git {
            VStack(alignment: .leading, spacing: 10) {
                if git.dirtyFiles > 0 {
                    Label("还有 \(git.dirtyFiles) 个文件改了没提交", systemImage: "pencil.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(git.branch ?? "—")
                    if let remote = git.remote {
                        Text("·")
                        Text(remote).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: 8) {
                    ForEach(Array(git.recentCommits.enumerated()), id: \.offset) { _, c in
                        GridRow {
                            Text(Formatting.relative(c.date)).foregroundStyle(.tertiary).monospacedDigit()
                            Text(c.subject).foregroundStyle(c.mine ? .primary : .secondary).textSelection(.enabled)
                        }
                    }
                }
                .font(.callout)
            }
        }
    }
}

// MARK: - 分类、备注、打开方式、README

private struct NotesSection: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem
    @State private var notes = ""
    @State private var pickingApp = false
    @State private var showReadme = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Divider()
            if let d = item.project.description {
                Text(d).foregroundStyle(.secondary).textSelection(.enabled)
            }
            FlowLayout(spacing: 6) {
                ForEach(model.library.categories.filter { item.meta.categories.contains($0.id) }) { c in
                    HStack(spacing: 4) {
                        Circle().fill(CategoryPalette.color(c.color) ?? .secondary).frame(width: 7, height: 7)
                        Text(c.name).font(.callout)
                        Button { model.toggleCategory(item.id, c.id) } label: { Image(systemName: "xmark").font(.caption2) }
                            .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassEffect(.regular, in: Capsule())
                }
                Menu {
                    ForEach(model.library.categories.filter { !item.meta.categories.contains($0.id) }) { c in
                        Button(c.name) { model.toggleCategory(item.id, c.id) }
                    }
                    Divider()
                    Button("新建分类…") { NotificationCenter.default.post(name: .newCategory, object: item.id) }
                } label: { Label("分类", systemImage: "plus").font(.callout) }
                .menuStyle(.button).buttonStyle(.glass).fixedSize()
            }

            TextField("写点备注…", text: $notes, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...8)
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Text("打开方式").foregroundStyle(.secondary)
                Picker("编辑器", selection: Binding(get: { item.meta.editor }, set: { model.setEditor(item.id, $0) })) {
                    Text("跟随默认（\(model.library.preferences.editor?.name ?? Opener.installedEditors.first?.name ?? "未设置")）").tag(AppRef?.none)
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

            HStack {
                Button { model.copyPath(item) } label: {
                    Label(Formatting.shortPath(item.id), systemImage: "folder").lineLimit(1).truncationMode(.middle)
                }
                .buttonStyle(.borderless)
                .help("点击复制路径")
                Spacer()
                Button(item.meta.hidden ? "取消隐藏" : "隐藏这个项目") { model.setHidden(item.id, !item.meta.hidden) }
                    .buttonStyle(.borderless)
            }
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
