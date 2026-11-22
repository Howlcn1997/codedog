import CodedogCore
import SwiftUI

/// 项目面板：从右侧滑出。
/// 头部（名称、路径、一行数字）→ 接着干（续上会话、未提交改动、打开方式）→ 活动（热力图 + 最近提交）→ 关于（属性表）→ 备注。
struct ProjectDetailView: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(item: item, onClose: onClose)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    NextUpCard(item: item)
                    ActivitySection(item: item)
                    AboutSection(item: item)
                    NotesSection(item: item).id(item.id)
                    PanelFooter(item: item)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 20)
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

/// 分组列表的底色（属性表、活动列表共用）。
private let groupFill = Color.primary.opacity(0.045)

// MARK: - 头部

private struct PanelHeader: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem
    var onClose: () -> Void
    @State private var showUsage = false
    @State private var showStorage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                StackBadge(project: item.project, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(item.project.name)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        livePill
                    }
                    Button { model.copyPath(item) } label: {
                        Text(Formatting.shortPath(item.id)).lineLimit(1).truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .help("点击复制路径")
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 24, height: 24)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .keyboardShortcut(.cancelAction)
                .help("关闭（Esc）")
            }
            statsLine
        }
    }

    /// 只显示需要注意的实时状态；未提交改动放在"接着干"里。
    @ViewBuilder private var livePill: some View {
        if !item.running.isEmpty {
            pill("运行中", .green)
        } else if item.waiting {
            pill("等你回复", .orange)
        }
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(color.opacity(0.14), in: Capsule())
        .fixedSize()
    }

    private var statsLine: some View {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
        func last30(_ days: [String: Int]) -> Int {
            days.filter { key, _ in (try? Date(key + "T12:00:00Z", strategy: .iso8601)).map { $0 >= cutoff } ?? false }.values.reduce(0, +)
        }
        let cost = item.tokensByModel.compactMap { Pricing.cost(model: $0.key, usage: $0.value) }.reduce(0, +)
        let tokens = item.tokensByModel.values.map(\.total).reduce(0, +)
        let kind = Text([item.project.kind.displayName] + item.project.stacks.prefix(2).map(\.displayName))
        return FlowLayout(spacing: 8) {
            kind.foregroundStyle(.secondary)
            divider
            stat("\(last30(item.commitDays))", "提交").help("近 30 天的提交")
            stat(Formatting.tokens(last30(item.aiDays)), "AI 回复").help("近 30 天的 AI 回复")
            if tokens > 0 {
                divider
                Button { showUsage.toggle() } label: {
                    linkStat(cost > 0 ? Formatting.cost(cost) : Formatting.tokens(tokens), cost > 0 ? "花费" : "token")
                }
                .buttonStyle(.plain)
                .help("各模型用量与估算花费")
                .popover(isPresented: $showUsage, arrowEdge: .bottom) { ModelUsageDetail(item: item) }
            }
            Button { showStorage.toggle() } label: {
                linkStat(item.size.map { Formatting.bytes($0.total) } ?? "—", "磁盘")
            }
            .buttonStyle(.plain)
            .help("占用空间与清理")
            .popover(isPresented: $showStorage, arrowEdge: .bottom) {
                StorageSection(item: item).padding(16).frame(width: 340)
            }
        }
        .font(.system(size: 12))
    }

    private var divider: some View { Text("|").foregroundStyle(.quaternary) }

    private func stat(_ value: String, _ label: String) -> some View {
        (Text(value).fontWeight(.semibold).foregroundStyle(.primary) + Text(" \(label)").foregroundStyle(.secondary))
            .monospacedDigit()
    }

    private func linkStat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 2) {
            stat(value, label)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 接着干

private struct NextUpCard: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem
    @State private var showFiles = false

    var body: some View {
        let agent = item.lastAgent
        let git = item.project.git
        VStack(alignment: .leading, spacing: 8) {
            Text("接着干").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            if let agent, let session = agent.lastSession {
                sessionRow(agent.tool, session)
            }
            if let git, git.dirtyFiles > 0 {
                changesRow(git)
            }
            actions(hasSessionRow: agent != nil)
        }
        .padding(12)
        .background(Color.brand.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func sessionRow(_ tool: AITool, _ session: SessionSummary) -> some View {
        let running = item.running.contains(tool)
        return row {
            ToolIcon(tool: tool, size: 20)
        } title: {
            Text(Formatting.plain(session.title ?? session.lastPrompt ?? "未命名会话"))
        } subtitle: {
            HStack(spacing: 4) {
                Text(tool.displayName)
                Text("·")
                if running {
                    Text("运行中").foregroundStyle(.green)
                } else if session.waiting {
                    Text("等你回复").foregroundStyle(.orange)
                } else {
                    Text(session.lastAt.map { Formatting.relative($0) } ?? "")
                }
            }
        } trailing: {
            if !running {
                Button("续上") { model.open(item, .resume(tool)) }
                    .buttonStyle(.glassProminent)
                    .tint(.brand)
                    .controlSize(.small)
            }
        }
    }

    private func changesRow(_ git: GitInfo) -> some View {
        let names = git.changedFiles.prefix(3).map(\.name).joined(separator: "、")
        return VStack(alignment: .leading, spacing: 0) {
            row {
                Image(systemName: "plusminus.circle.fill").font(.system(size: 17)).foregroundStyle(.pink)
                    .frame(width: 20)
            } title: {
                Text("\(git.dirtyFiles) 个文件未提交") + Text(git.branch.map { " · \($0)" } ?? "").foregroundStyle(.secondary)
            } subtitle: {
                Text(git.changedFiles.count > 3 ? names + "…" : names)
            } trailing: {
                Button(showFiles ? "收起" : "查看") { withAnimation(.snappy) { showFiles.toggle() } }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
            if showFiles {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(git.changedFiles.prefix(15), id: \.path) { f in
                        Button { NSWorkspace.shared.open(URL(filePath: item.id + "/" + f.path)) } label: {
                            HStack(spacing: 8) {
                                Text(statusLetter(f.status)).font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(statusColor(f.status)).frame(width: 12)
                                Text(f.path).font(.system(size: 11.5, design: .monospaced)).lineLimit(1).truncationMode(.head)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(f.status == .deleted)
                        .help(f.status == .deleted ? "已删除" : "打开文件")
                    }
                    if git.changedFiles.count > 15 {
                        Text("还有 \(git.changedFiles.count - 15) 个文件").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .padding(.top, 2)
                .transition(.opacity)
            }
        }
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusLetter(_ s: FileRef.Status) -> String {
        switch s {
        case .added: "A"
        case .deleted: "D"
        case .renamed: "R"
        case .untracked: "U"
        default: "M"
        }
    }

    private func statusColor(_ s: FileRef.Status) -> Color {
        switch s {
        case .added, .untracked: .green
        case .deleted: .red
        default: .orange
        }
    }

    private func row<I: View, T: View, S: View, R: View>(
        @ViewBuilder icon: () -> I, @ViewBuilder title: () -> T, @ViewBuilder subtitle: () -> S, @ViewBuilder trailing: () -> R
    ) -> some View {
        HStack(spacing: 10) {
            icon()
            VStack(alignment: .leading, spacing: 1) {
                title().lineLimit(1)
                subtitle().font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            trailing()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 打开方式：没有会话行时编辑器按钮是主操作。
    private func actions(hasSessionRow: Bool) -> some View {
        let editor = model.editor(for: item)
        return HStack(spacing: 6) {
            let open = Button { model.open(item) } label: {
                Label { Text(editor.map { hasSessionRow ? $0.name : "用 \($0.name) 打开" } ?? "打开") } icon: {
                    if let editor { AppIconView(app: editor, size: 15) }
                }
            }
            if hasSessionRow {
                open.buttonStyle(.glass)
            } else {
                open.buttonStyle(.glassProminent).tint(.brand)
            }
            Spacer(minLength: 0)
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 4) {
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
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.glass)
            .help(help)
    }
}

// MARK: - 活动

/// 热力图（提交与 AI 回复合并）+ 最近提交。AI 会话已在"接着干"里，这里只列提交。
private struct ActivitySection: View {
    var item: ProjectItem
    @State private var day: String?
    @State private var expanded = false

    var body: some View {
        let days = item.commitDays.merging(item.aiDays, uniquingKeysWith: +)
        let unit = "次活动"
        let active = days.filter { $0.value > 0 }.count
        let commits = (item.project.git?.recentCommits ?? []).filter { day == nil || HeatmapView.key($0.date) == day }
        let limit = 5
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("活动").font(.system(size: 13, weight: .semibold))
                Text("近一年活跃 \(active) 天").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            HeatmapView(days: days, unit: unit, selection: $day)
            if let day {
                HStack(spacing: 6) {
                    Text(dayLabel(day)).fontWeight(.semibold)
                    Text("\(days[day] ?? 0) \(unit)").foregroundStyle(.secondary)
                    Spacer()
                    Button("显示全部") { withAnimation(.snappy) { self.day = nil } }.buttonStyle(.borderless)
                }
                .font(.caption)
            }
            if let git = item.project.git {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(git.branch ?? "HEAD").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(.primary)
                    Text("分支的最近提交")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .help("当前检出的分支（HEAD）上的提交记录")
                if commits.isEmpty {
                    Text(day == nil ? "还没有提交" : "最近的提交里没有这一天的")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(groupFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    VStack(spacing: 0) {
                        let shown = expanded ? commits : Array(commits.prefix(limit))
                        ForEach(Array(shown.enumerated()), id: \.offset) { i, c in
                            if i > 0 { Divider().padding(.leading, 34) }
                            commitRow(c, first: i == 0, last: i == shown.count - 1)
                        }
                        if commits.count > limit {
                            Divider()
                            Button(expanded ? "收起" : "显示更多（\(commits.count - limit)）") { withAnimation(.snappy) { expanded.toggle() } }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                        }
                    }
                    .background(groupFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .onChange(of: day) { expanded = false }
    }

    /// 时间线：圆点用品牌色（别人的提交用浅色），相邻提交之间用竖线连起来。
    private func commitRow(_ c: Commit, first: Bool, last: Bool) -> some View {
        let line = Color.brand.opacity(0.3)
        return HStack(spacing: 10) {
            ZStack {
                VStack(spacing: 0) {
                    Rectangle().fill(first ? .clear : line).frame(width: 1.5)
                    Rectangle().fill(last ? .clear : line).frame(width: 1.5)
                }
                Circle().fill(c.mine ? Color.brand : Color.brand.opacity(0.45)).frame(width: 8, height: 8)
            }
            .frame(width: 14)
            .frame(maxHeight: .infinity)
            HStack(spacing: 10) {
                Text(c.subject).lineLimit(1).foregroundStyle(c.mine ? .primary : .secondary)
                    .help(c.mine ? c.subject : "\(c.subject)（其他人的提交）")
                    .textSelection(.enabled)
                Spacer(minLength: 6)
                Text(Formatting.relative(c.date)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.vertical, 7)
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
    }

    private func dayLabel(_ key: String) -> String {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return key }
        let thisYear = Calendar.current.component(.year, from: .now)
        return p[0] == thisYear ? "\(p[1])月\(p[2])日" : "\(p[0])年\(p[1])月\(p[2])日"
    }
}

// MARK: - 关于（属性表）

private struct AboutSection: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem
    @State private var pickingApp = false
    @State private var showReadme = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关于").font(.system(size: 13, weight: .semibold))
            VStack(spacing: 0) {
                let rows = rowViews
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    if i > 0 { Divider().padding(.leading, 12) }
                    r
                }
            }
            .background(groupFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .fileImporter(isPresented: $pickingApp, allowedContentTypes: [.application]) { r in
            if case .success(let url) = r, let ref = Opener.appRef(at: url) { model.setEditor(item.id, ref) }
        }
    }

    private var rowViews: [AnyView] {
        var rows: [AnyView] = []
        if let d = item.project.description, !d.isEmpty {
            rows.append(AnyView(prop("简介") { Text(Formatting.plain(d)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }))
        }
        if !item.project.languages.isEmpty {
            rows.append(AnyView(prop("语言") { LanguageBar(languages: item.project.languages) }))
        }
        rows.append(AnyView(prop("标签") { tags }))
        if let git = item.project.git {
            rows.append(AnyView(prop("仓库") { repo(git) }))
        }
        rows.append(AnyView(prop("打开方式") { editorPicker }))
        if let readme = item.project.readmeText, !readme.isEmpty {
            rows.append(AnyView(prop("README") {
                Button { showReadme = true } label: {
                    HStack(spacing: 3) {
                        Text(item.project.readmeFile ?? "README")
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                    }
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showReadme, arrowEdge: .leading) { ReadmeView(title: item.project.readmeFile ?? "README", text: readme) }
            }))
        }
        return rows
    }

    private func prop<V: View>(_ label: String, @ViewBuilder _ value: () -> V) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
                .padding(.top, 2)
            value().frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var tags: some View {
        FlowLayout(spacing: 5) {
            ForEach(model.library.categories.filter { item.meta.categories.contains($0.id) }) { c in
                HStack(spacing: 4) {
                    Circle().fill(CategoryPalette.color(c.color) ?? .secondary).frame(width: 6, height: 6)
                    Text(c.name)
                    Button { model.toggleCategory(item.id, c.id) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("移除标签")
                }
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: Capsule())
            }
            Menu {
                ForEach(model.library.categories.filter { !item.meta.categories.contains($0.id) }) { c in
                    Button(c.name) { model.toggleCategory(item.id, c.id) }
                }
                Divider()
                Button("新建标签…") { NotificationCenter.default.post(name: .newCategory, object: item.id) }
            } label: { Text("+ 添加").font(.caption) }
            .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
        }
    }

    private func repo(_ git: GitInfo) -> some View {
        HStack(spacing: 6) {
            Text(git.branch ?? "—").font(.system(size: 12, design: .monospaced))
            if let remote = git.remote {
                Text("·").foregroundStyle(.tertiary)
                if let url = git.webURL {
                    Link(url.host().map { $0 + url.path() } ?? remote, destination: url)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                } else {
                    Text(remote).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
            }
        }
    }

    private var editorPicker: some View {
        HStack(spacing: 6) {
            Picker("编辑器", selection: Binding(get: { item.meta.editor }, set: { model.setEditor(item.id, $0) })) {
                Text("跟随全局（\(model.library.preferences.editor?.name ?? Opener.installedEditors.first?.name ?? "未设置")）").tag(AppRef?.none)
                Divider()
                ForEach(editorChoices, id: \.self) { app in
                    Label { Text(app.name) } icon: { Image(nsImage: AppIconView.icon(app)) }.tag(AppRef?.some(app))
                }
            }
            .labelsHidden().fixedSize().controlSize(.small)
            Button("其他…") { pickingApp = true }.buttonStyle(.borderless).font(.caption)
        }
    }

    private var editorChoices: [AppRef] {
        var list = Opener.installedEditors
        if let custom = item.meta.editor, !list.contains(custom) { list.append(custom) }
        return list
    }
}

/// 语言分布：分段色条 + 图例。最多单独列 5 种，其余合并为"其他"。
private struct LanguageBar: View {
    var languages: [LanguageShare]

    private var shares: [(name: String, fraction: Double, color: Color)] {
        let total = Double(languages.reduce(0) { $0 + $1.bytes })
        guard total > 0 else { return [] }
        let top = languages.prefix(5).map { (name: $0.name, fraction: Double($0.bytes) / total, color: Color(hex: $0.color)) }
        let rest = languages.dropFirst(5).reduce(0) { $0 + $1.bytes }
        return rest > 0 ? top + [(name: "其他", fraction: Double(rest) / total, color: Color.secondary.opacity(0.5))] : top
    }

    var body: some View {
        let items = shares
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                let gap: CGFloat = 2
                let usable = g.size.width - gap * CGFloat(items.count - 1)
                HStack(spacing: gap) {
                    ForEach(items, id: \.name) { s in
                        Rectangle().fill(s.color).frame(width: max(2, usable * s.fraction))
                    }
                }
                .frame(width: g.size.width, alignment: .leading)
                .clipShape(Capsule())
            }
            .frame(height: 6)
            .padding(.top, 6)
            FlowLayout(spacing: 10) {
                ForEach(items, id: \.name) { s in
                    HStack(spacing: 4) {
                        Circle().fill(s.color).frame(width: 7, height: 7)
                        Text(s.name)
                        Text(percent(s.fraction)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            .font(.caption)
        }
    }

    private func percent(_ f: Double) -> String {
        let p = f * 100
        return p < 0.1 ? "<0.1%" : String(format: "%.1f%%", p)
    }
}

private struct ReadmeView: View {
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ScrollView {
                Text(Self.markdown(String(text.prefix(12000))))
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 460, height: 520)
    }

    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible))) ?? AttributedString(s)
    }
}

// MARK: - 备注与页脚

private struct NotesSection: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("备注").font(.system(size: 13, weight: .semibold))
            TextField("写点备注…", text: $notes, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...8)
                .padding(10)
                .background(groupFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .onAppear { notes = item.meta.notes }
        .task(id: notes) {
            guard notes != item.meta.notes else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            model.setNotes(item.id, notes)
        }
    }
}

private struct PanelFooter: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem

    var body: some View {
        HStack {
            Button(item.meta.hidden ? "取消隐藏" : "隐藏这个项目") { model.setHidden(item.id, !item.meta.hidden) }
                .buttonStyle(.borderless)
            Spacer()
            if let created = item.project.createdAt {
                Text("创建于 \(created.formatted(.dateTime.year().month()))").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 2)
    }
}

// MARK: - 模型用量明细（概览卡片弹出）

private struct ModelUsageDetail: View {
    var item: ProjectItem

    var body: some View {
        let rows = item.tokensByModel.map { (model: $0.key, usage: $0.value, cost: Pricing.cost(model: $0.key, usage: $0.value)) }
            .filter { $0.usage.total > 0 }
            .sorted { ($0.cost ?? -1, $0.usage.total) > ($1.cost ?? -1, $1.usage.total) }
        let total = rows.map(\.usage.total).reduce(0, +)
        let cost = rows.compactMap(\.cost).reduce(0, +)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("模型用量", "cpu")
                Spacer()
                Text("\(Formatting.tokens(total)) token").foregroundStyle(.secondary).monospacedDigit()
                Text(cost > 0 ? Formatting.cost(cost) : "—").font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(rows, id: \.model) { r in
                        VStack(alignment: .leading, spacing: 5) {
                            UsageBar(name: Pricing.displayName(r.model), cost: r.cost, tokens: r.usage.total, fraction: Double(r.usage.total) / Double(max(total, 1)))
                            Text([
                                "输入 \(Formatting.tokens(r.usage.input))",
                                "输出 \(Formatting.tokens(r.usage.output))",
                                r.usage.cacheRead > 0 ? "缓存读 \(Formatting.tokens(r.usage.cacheRead))" : "",
                                r.usage.cacheWrite5m + r.usage.cacheWrite1h > 0 ? "缓存写 \(Formatting.tokens(r.usage.cacheWrite5m + r.usage.cacheWrite1h))" : "",
                            ])
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)
            Text("花费按 Anthropic 公开 API 价格估算（缓存写入按 1.25×/2× 输入价），只统计 Claude 模型；订阅用户的实际花费不同。")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 380)
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

// MARK: - 磁盘

private struct StorageSection: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem
    @State private var confirming = false
    @State private var cleaning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("磁盘", "internaldrive")
                Spacer()
                if model.isMeasuring { ProgressView().controlSize(.mini) }
                Button("重新统计") { Task { await model.measureSizes(only: [item.id]) } }
                    .buttonStyle(.borderless).font(.caption)
                    .disabled(model.isMeasuring)
            }
            if let size = item.size {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Formatting.bytes(size.total)).font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("源码 \(Formatting.bytes(size.source)) · 依赖与缓存 \(Formatting.bytes(size.reclaimable))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                GeometryReader { g in
                    let frac = size.total > 0 ? CGFloat(size.source) / CGFloat(size.total) : 1
                    HStack(spacing: 2) {
                        Capsule().fill(Color.brand).frame(width: max(4, g.size.width * frac))
                        Capsule().fill(Color.orange.opacity(0.7))
                    }
                }
                .frame(height: 6)
                let plan = DependencyCleaner.plan(project: item.id, size: size)
                if !plan.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(plan.prefix(4)) { c in
                            HStack {
                                Text(c.directory.replacingOccurrences(of: item.id + "/", with: ""))
                                    .font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(Formatting.bytes(c.bytes)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        if plan.count > 4 { Text("还有 \(plan.count - 4) 个目录").font(.caption).foregroundStyle(.tertiary) }
                    }
                    Button {
                        confirming = true
                    } label: {
                        Label(cleaning ? "清理中…" : "清理依赖与缓存 · \(Formatting.bytes(size.reclaimable))", systemImage: "trash")
                    }
                    .buttonStyle(.glass)
                    .disabled(cleaning)
                    .confirmationDialog("把 \(plan.count) 个目录移到废纸篓？", isPresented: $confirming) {
                        Button("移到废纸篓", role: .destructive) {
                            cleaning = true
                            Task { await model.clean(plan); cleaning = false }
                        }
                    } message: {
                        Text("这些是依赖与构建缓存（如 node_modules、.venv），重新安装或构建即可恢复。需要时也可以从废纸篓还原。")
                    }
                }
            } else {
                Text(model.isMeasuring ? "正在统计…" : "还没有统计").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

