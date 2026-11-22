import CodedogCore
import SwiftUI

/// 项目面板：从右侧滑出。
/// 头部（名称、路径、一行数字）→ 接着干（续上会话、打开方式）→ 活动（热力图 + 未提交改动 + 最近提交）→ 关于（属性表）→ 备注。
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

private func sectionTitle(_ title: LocalizedStringKey, _ symbol: String) -> some View {
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

    /// 只显示需要注意的实时状态；未提交改动放在"活动"的提交列表里。
    @ViewBuilder private var livePill: some View {
        if !item.running.isEmpty {
            pill("运行中", .green)
        } else if item.waiting {
            pill("等你回复", .orange)
        }
    }

    private func pill(_ text: LocalizedStringKey, _ color: Color) -> some View {
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

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        (Text(value).fontWeight(.semibold).foregroundStyle(.primary) + Text(verbatim: " ") + Text(label).foregroundStyle(.secondary))
            .monospacedDigit()
    }

    private func linkStat(_ value: String, _ label: LocalizedStringKey) -> some View {
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

    var body: some View {
        let agent = item.lastAgent
        VStack(alignment: .leading, spacing: 8) {
            Text("接着干").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            if let agent, let session = agent.lastSession {
                sessionRow(agent.tool, session)
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
            Text(Formatting.plain(session.title ?? session.lastPrompt ?? String(localized: "未命名会话")))
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
                Label { Text(editor.map { hasSessionRow ? $0.name : String(localized: "用 \($0.name) 打开") } ?? String(localized: "打开")) } icon: {
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
                    iconButton("apple.terminal", "终端打开") { model.open(item, .terminal) }
                    iconButton("folder", "访达打开") { model.open(item, .finder) }
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

    private func iconButton(_ symbol: String, _ help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.glass)
            .help(help)
    }
}

// MARK: - 活动

/// 热力图（提交与 AI 回复合并）+ 最近提交。AI 会话已在"接着干"里，这里只列提交；
/// 未提交的改动作为时间线最上面的一个节点。
private struct ActivitySection: View {
    var item: ProjectItem
    @State private var day: String?
    @State private var expanded = false
    @State private var showFiles = false

    var body: some View {
        let days = item.commitDays.merging(item.aiDays, uniquingKeysWith: +)
        let active = days.filter { $0.value > 0 }.count
        let commits = (item.project.git?.recentCommits ?? []).filter { day == nil || HeatmapView.key($0.date) == day }
        let limit = 5
        // 选中某一天时只看那天的提交，不显示未提交改动。
        let dirty = item.project.git.flatMap { day == nil && $0.dirtyFiles > 0 ? $0 : nil }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("活动").font(.system(size: 13, weight: .semibold))
                Text("近一年活跃 \(active) 天").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            HeatmapView(days: days, selection: $day)
            if let day {
                HStack(spacing: 6) {
                    Text(dayLabel(day)).fontWeight(.semibold)
                    Text("\(days[day] ?? 0) 次活动").foregroundStyle(.secondary)
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
                if commits.isEmpty && dirty == nil {
                    Label(day == nil ? "还没有提交" : "最近的提交里没有这一天的", systemImage: day == nil ? "tray" : "calendar.badge.exclamationmark")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(groupFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    VStack(spacing: 0) {
                        if let dirty {
                            uncommittedRow(dirty, last: commits.isEmpty)
                            if !commits.isEmpty { Divider().padding(.leading, 34) }
                        }
                        let shown = expanded ? commits : Array(commits.prefix(limit))
                        ForEach(Array(shown.enumerated()), id: \.offset) { i, c in
                            if i > 0 { Divider().padding(.leading, 34) }
                            commitRow(c, first: i == 0 && dirty == nil, last: i == shown.count - 1)
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

    /// 时间线顶端的"未提交"节点：空心粉色圆点，可展开文件列表。
    private func uncommittedRow(_ git: GitInfo, last: Bool) -> some View {
        let line = Color.brand.opacity(0.3)
        let names = git.changedFiles.prefix(3).map(\.name).joined(separator: "、")
        return HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle().fill(.clear).frame(width: 1.5, height: 17)
                    Rectangle().fill(last ? .clear : line).frame(width: 1.5)
                }
                Circle().strokeBorder(Color.pink, lineWidth: 1.5).frame(width: 9, height: 9).padding(.top, 13)
            }
            .frame(width: 14)
            .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        (Text("\(git.dirtyFiles) 个文件未提交").foregroundStyle(.pink))
                        Text(git.changedFiles.count > 3 ? names + "…" : names)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 6)
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
                    .padding(.top, 2)
                    .transition(.opacity)
                }
            }
            .padding(.vertical, 7)
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
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
                    .help(c.mine ? c.subject : String(localized: "\(c.subject)（其他人的提交）"))
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
        guard p.count == 3, let date = Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return key }
        return Formatting.day(date, withYear: p[0] != Calendar.current.component(.year, from: .now))
    }
}

// MARK: - 关于（属性表）

private struct AboutSection: View {
    @Environment(LibraryModel.self) private var model
    var item: ProjectItem
    @State private var pickingApp = false
    @State private var showReadme = false
    @State private var copiedPath: String?

    var body: some View {
        let git = item.project.git
        VStack(alignment: .leading, spacing: 10) {
            Text("关于").font(.system(size: 13, weight: .semibold))
            // 不写「简介」「语言」这类标签：内容本身看得出是什么
            VStack(alignment: .leading, spacing: 16) {
                if let d = item.project.description, !d.isEmpty {
                    Text(Formatting.plain(d))
                        .font(.callout)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !item.project.languages.isEmpty {
                    LanguageBar(languages: item.project.languages)
                }
                tags
                if let wts = git?.worktrees, !wts.isEmpty {
                    worktrees(wts)
                }
                // 能点的入口收成底部一排：仓库、README、编辑器
                VStack(alignment: .leading, spacing: 12) {
                    Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
                    FlowLayout(spacing: 6) {
                        if let git { repo(git) }
                        readme
                        editorPicker
                    }
                }
                .padding(.top, -4)
            }
            .padding(14)
            .background(groupFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .fileImporter(isPresented: $pickingApp, allowedContentTypes: [.application]) { r in
            if case .success(let url) = r, let ref = Opener.appRef(at: url) { model.setEditor(item.id, ref) }
        }
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
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.primary.opacity(0.07), in: Capsule())
            }
            Menu {
                ForEach(model.library.categories.filter { !item.meta.categories.contains($0.id) }) { c in
                    Button(c.name) { model.toggleCategory(item.id, c.id) }
                }
                Divider()
                Button("新建标签…") { NotificationCenter.default.post(name: .newCategory, object: item.id) }
            } label: { Text("+ 标签").font(.caption) }
            .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        }
    }

    /// 仓库：托管平台图标 + 平台名（GitHub / GitLab / Gitee，其他托管显示域名），点击跳转，完整地址放在悬停提示里；
    /// 没有网页地址时点击复制 remote。
    @ViewBuilder
    private func repo(_ git: GitInfo) -> some View {
        if let url = git.webURL {
            let host = url.host()?.lowercased() ?? ""
            // 平台图标：GitHub 跟随文字色、GitLab 橙、Gitee 红，其他托管用 Git 图标
            let (icon, brand, name): (String, Color, String) =
                host.contains("github") ? ("Repo/github", .primary, "GitHub")
                : host.contains("gitlab") ? ("Repo/gitlab", Color(hex: 0xFC6D26), "GitLab")
                : host.contains("gitee") ? ("Repo/git", Color(hex: 0xC71D23), "Gitee")
                : ("Repo/git", Color(hex: 0xF05032), host)
            Button { NSWorkspace.shared.open(url) } label: {
                HStack(spacing: 6) {
                    Image(icon).resizable().renderingMode(.template)
                        .frame(width: 14, height: 14).foregroundStyle(brand)
                    Text(verbatim: name).lineLimit(1).truncationMode(.middle)
                }
            }
            .buttonStyle(PillStyle())
            .help(url.absoluteString)
        } else if let remote = git.remote {
            Button { copy(remote) } label: {
                HStack(spacing: 6) {
                    Image("Repo/git").resizable().renderingMode(.template).frame(width: 14, height: 14)
                        .foregroundStyle(Color(hex: 0xF05032))
                    Image(systemName: copiedPath == remote ? "checkmark" : "doc.on.doc").font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(PillStyle())
            .help(remote)
        }
    }

    @ViewBuilder private var readme: some View {
        if let text = item.project.readmeText, !text.isEmpty {
            let title = item.project.readmeFile ?? "README"
            Button { showReadme = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text").font(.system(size: 11))
                    Text(verbatim: "README")
                }
            }
            .buttonStyle(PillStyle())
            .help(title)
            .sheet(isPresented: $showReadme) {
                ReadmeSheet(title: title, text: text, baseURL: URL(fileURLWithPath: item.project.path, isDirectory: true))
            }
        }
    }

    /// 编辑器：显示实际会用的编辑器，弹出列表里可改为跟随全局或另选。
    private var editorPicker: some View {
        let global = model.library.preferences.editor ?? Opener.installedEditors.first
        let shown = item.meta.editor ?? global
        let auto = String(localized: "跟随全局（\(global?.name ?? String(localized: "未设置"))）")
        let options: [SettingsChoice<AppRef?, AnyView>.Option] =
            [.init(value: nil, title: auto, icon: nil)]
            + editorChoices.map { .init(value: $0, title: $0.name, icon: AppIconView.icon($0)) }
        return SettingsChoice(title: "编辑器", options: options,
                              selection: Binding(get: { item.meta.editor }, set: { model.setEditor(item.id, $0) }),
                              extra: (String(localized: "其他应用…"), { pickingApp = true })) {
            AnyView(HStack(spacing: 6) {
                if let shown { Image(nsImage: AppIconView.icon(shown)).resizable().frame(width: 14, height: 14) }
                Text(shown?.name ?? String(localized: "未设置")).font(.system(size: 12))
            })
        }
        .help(item.meta.editor == nil ? auto : String(localized: "打开方式"))
    }

    /// 每个 worktree 一行：分支名 + 复制路径按钮。
    private func worktrees(_ wts: [GitWorktree]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(wts, id: \.path) { wt in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(wt.branch ?? String(localized: "游离 HEAD"))
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(wt.prunable ? .secondary : .primary)
                    if wt.prunable {
                        Text("已删除").font(.caption).foregroundStyle(.secondary).fixedSize()
                    }
                    Spacer(minLength: 4)
                    Button { copy(wt.path) } label: {
                        Image(systemName: copiedPath == wt.path ? "checkmark" : "doc.on.doc").font(.system(size: 11))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .help(Formatting.shortPath(wt.path))
                }
                .contextMenu {
                    Button("在编辑器中打开") {
                        let editor = model.editor(for: item)
                        Task { try? await Opener.openInEditor(wt.path, editor: editor) }
                    }
                    .disabled(wt.prunable)
                    Button("访达打开") { Opener.revealInFinder(wt.path) }.disabled(wt.prunable)
                    Button("拷贝路径") { copy(wt.path) }
                }
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedPath = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if copiedPath == text { copiedPath = nil }
        }
    }

    private var editorChoices: [AppRef] {
        var list = Opener.installedEditors
        if let custom = item.meta.editor, !list.contains(custom) { list.append(custom) }
        return list
    }
}

/// 关于区底部的胶囊按钮，和 SettingsChoice 的外观一致。
private struct PillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { PillBody(configuration: configuration) }

    private struct PillBody: View {
        let configuration: Configuration
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(Color.primary.opacity(hovered ? 0.1 : 0.06)))
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
                .onHover { hovered = $0 }
        }
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
        return rest > 0 ? top + [(name: String(localized: "其他"), fraction: Double(rest) / total, color: Color.secondary.opacity(0.5))] : top
    }

    var body: some View {
        let items = shares
        VStack(alignment: .leading, spacing: 8) {
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
            .frame(height: 4)
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
                Text("创建于 \(created.formatted(.dateTime.year().month().locale(AppLanguage.locale)))").foregroundStyle(.secondary)
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
                                String(localized: "输入 \(Formatting.tokens(r.usage.input))"),
                                String(localized: "输出 \(Formatting.tokens(r.usage.output))"),
                                r.usage.cacheRead > 0 ? String(localized: "缓存读 \(Formatting.tokens(r.usage.cacheRead))") : "",
                                r.usage.cacheWrite5m + r.usage.cacheWrite1h > 0 ? String(localized: "缓存写 \(Formatting.tokens(r.usage.cacheWrite5m + r.usage.cacheWrite1h))") : "",
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

