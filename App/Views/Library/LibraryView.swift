import CodedogCore
import SwiftUI

struct LibraryView: View {
    @Environment(LibraryModel.self) private var model
    /// 标题离工具栏的距离，网格和列表两种形态共用，保证切换时标题不跳
    private let headerTop: CGFloat = 14

    var body: some View {
        let visible = model.visible
        Group {
            if !model.isLoaded {
                // 设置还没读完：先只显示背景，免得闪一下首次启动的引导页
                Color.clear
            } else if showNoRoots {
                // 放进 ScrollView：详情区没有滚动视图时，系统会把侧栏列表当成窗口的主滚动视图，
                // 给它套上工具栏的顶部偏移，侧栏内容就被推到标题栏下面、底部按钮也看不到了。
                ScrollView {
                    NoRootsView().containerRelativeFrame(.vertical)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(count: visible.count)
                        if model.selection == .smart(.large) {
                            CleanupBanner(items: visible.map(\.item))
                        } else if model.searchText.isEmpty {
                            PulseStrip().padding(.bottom, 6)
                        }
                        if visible.isEmpty {
                            LibraryEmptyState().frame(minHeight: 340)
                        } else if model.viewMode == .list {
                            ProjectTable(rows: visible).padding(.horizontal, -12)   // 行底色外扩，让文字和标题左对齐
                        } else {
                            grid(visible)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, headerTop)
                    .padding(.bottom, 40)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
        }
        .background { BackdropView() }
    }

    private var showNoRoots: Bool {
        #if DEBUG
        if model.debugNoRoots { return true }
        #endif
        return model.library.scanRoots.isEmpty && model.library.pinnedPaths.isEmpty
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(model.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .lineLimit(1)
            Text(subtitle(count))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func subtitle(_ count: Int) -> String {
        var parts = [String(localized: "\(count) 个项目")]
        if model.timeRange != .all { parts.append(model.timeRange.title) }
        if let p = model.pulse { parts.append(p.title) }
        return parts.joined(separator: " · ")
    }

    private func grid(_ rows: [(item: ProjectItem, match: SearchMatch)]) -> some View {
        let k = model.cardScale
        let w = ProjectCard.size.width * k, h = ProjectCard.size.height * k
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: w, maximum: w + 40 * k), spacing: 26 * k)], spacing: 30 * k) {
            ForEach(rows, id: \.item.id) { row in
                ProjectCard(item: row.item, match: row.match, isSelected: model.selectedID == row.item.id) {
                    model.selectedID = row.item.id
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) { model.detailID = row.item.id }
                }
                    .scaleEffect(k, anchor: .topLeading)
                    .frame(width: w, height: h, alignment: .topLeading)
                    .contextMenu { ProjectMenu(item: row.item) }
                    .help(Formatting.shortPath(row.item.id))
            }
        }
    }
}

/// 内容区背景：柔和的强调色光晕，衬托玻璃卡片。
struct BackdropView: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            (scheme == .dark ? Color(red: 0.09, green: 0.09, blue: 0.11) : Color(red: 0.97, green: 0.97, blue: 0.98))
            RadialGradient(colors: [Color.brand.opacity(scheme == .dark ? 0.20 : 0.10), .clear], center: .top, startRadius: 0, endRadius: 650)
        }
        .ignoresSafeArea()
    }
}

/// 首次启动：还没有任何扫描目录。
struct NoRootsView: View {
    @Environment(LibraryModel.self) private var model
    @State private var picking = false

    var body: some View {
        VStack(spacing: 28) {
            EmptyStateView("告诉 codedog 你的代码放在哪里", symbol: "folder.badge.plus",
                           message: "选择一个或多个文件夹，codedog 会自动找到里面的项目。") {
                Button("选择文件夹…", systemImage: "folder") { picking = true }
                    .buttonStyle(.glassProminent)
                    .tint(.brand)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                feature("sparkle.magnifyingglass", "自动发现", "识别 Git、Node、Swift、Python 等项目")
                feature("arrow.triangle.2.circlepath", "实时更新", "文件变化时自动刷新状态")
                feature("lock.shield", "只读", "不会移动或修改任何文件")
            }
            // 卡片等高但只按内容的高度，否则会被拉满整个窗口
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 620)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                model.setScanRoots(model.library.scanRoots + urls.map { $0.path(percentEncoded: false) })
            }
        }
    }

    /// 和"今日脉搏"同款的玻璃小卡片
    private func feature(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.brand)
                .frame(width: 28, height: 28)
                .background(Color.brand.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 项目库没有可显示的项目：按"搜索 → 扫描中 → 脉搏筛选 → 时间范围 → 侧栏分组"给出对应的说明和出路。
struct LibraryEmptyState: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        if !model.searchText.isEmpty {
            EmptyStateView("没有找到“\(model.searchText)”", symbol: "magnifyingglass",
                           message: "可以搜项目名、README 里的内容或依赖名。") {
                Button("清除搜索") { model.searchText = "" }.buttonStyle(.glass)
            }
        } else if model.isScanning && model.projects.isEmpty {
            EmptyStateView("正在寻找项目…", symbol: "sparkle.magnifyingglass",
                           message: "第一次扫描可能需要几秒钟。", animating: true)
        } else if let p = model.pulse {
            EmptyStateView("没有\(p.title)的项目", symbol: p.symbol, message: p.emptyMessage, tint: p.color) {
                Button("取消筛选") { withAnimation(.snappy) { model.pulse = nil } }.buttonStyle(.glass)
            }
        } else if let s = selectionEmpty {
            EmptyStateView(s.title, symbol: s.symbol, message: s.message, tint: s.tint) {
                if model.timeRange != .all { showAllTime }
            }
        } else if model.timeRange != .all {
            EmptyStateView("这段时间没有活跃的项目", symbol: "calendar.badge.clock",
                           message: "当前只显示\(model.timeRange.menuTitle)的项目。") { showAllTime }
        } else {
            EmptyStateView("这里还没有项目", symbol: "tray", message: "换个分组或标签看看。")
        }
    }

    private var showAllTime: some View {
        Button("不限时间") { model.timeRange = .all }.buttonStyle(.glass)
    }

    /// 侧栏分组本身为空时的文案（只在不限时间时才说"一个都没有"，否则交给时间范围提示）
    private var selectionEmpty: (title: LocalizedStringKey, symbol: String, message: LocalizedStringKey, tint: Color)? {
        let ranged = model.timeRange != .all
        switch model.selection {
        case .smart(.favorites):
            return ("还没有收藏", "star", "在项目的右键菜单里选择“收藏”，常用的项目会集中在这里。", .yellow)
        case .smart(.waiting):
            return ("没有在等你回复的 AI", "bubble.left.and.text.bubble.right", "AI 助手停下来等你确认时，项目会出现在这里。", .orange)
        case .smart(.recent):
            return ("最近两周没有打开过项目", "clock.arrow.circlepath", "通过 codedog 打开的项目会出现在这里。", .brand)
        case .smart(.dirty) where !ranged:
            return ("所有改动都已提交", "checkmark.circle", "没有项目有未提交的改动。", .green)
        case .smart(.large) where !ranged:
            return ("没有超过 500 MB 的项目", "internaldrive", "磁盘占用都很健康。", .green)
        case .smart(.hidden):
            return ("没有隐藏的项目", "eye.slash", "在右键菜单里选择“隐藏”，可以把不想看到的项目收起来。", .secondary)
        case .category where !ranged:
            return ("这个标签下还没有项目", "tag", "在项目的右键菜单里打开“标签”，把项目加进来。", .brand)
        default:
            return nil
        }
    }
}

extension Pulse {
    var color: Color {
        switch self {
        case .running: .green
        case .waiting: .orange
        case .dirty: .pink
        case .activeWeek: .brand
        }
    }

    var emptyMessage: LocalizedStringKey {
        switch self {
        case .running: "现在没有 AI 助手在工作。"
        case .waiting: "没有 AI 助手在等你回复。"
        case .dirty: "所有改动都已提交。"
        case .activeWeek: "这周还没有动过任何项目。"
        }
    }
}

/// 今日脉搏：四个指标块，点一下就按该状态筛选，再点取消。
struct PulseStrip: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Pulse.allCases) { p in
                let on = model.pulse == p
                let n = model.count(p)
                Button {
                    withAnimation(.snappy) { model.pulse = on ? nil : p }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: p.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(on ? .white : color(p))
                            .frame(width: 34, height: 34)
                            .background(on ? color(p) : color(p).opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(n)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text(p.title).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .glassEffect(on ? .regular.tint(color(p).opacity(0.25)) : .regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .opacity(n == 0 && !on ? 0.6 : 1)
                .help(on ? Text("取消筛选") : Text("只看\(p.title)的项目"))
            }
        }
    }

    private func color(_ p: Pulse) -> Color { p.color }
}

/// "占空间"视图顶部：可清理总量 + 批量清理入口。
struct CleanupBanner: View {
    @Environment(LibraryModel.self) private var model
    var items: [ProjectItem]
    @State private var showSheet = false

    var body: some View {
        let reclaimable = items.compactMap(\.size?.reclaimable).reduce(0, +)
        let total = items.compactMap(\.size?.total).reduce(0, +)
        HStack(spacing: 14) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.orange.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("共占用 \(Formatting.bytes(total))，其中 \(Formatting.bytes(reclaimable)) 是依赖与构建缓存")
                    .font(.system(size: 14, weight: .semibold))
                (model.isMeasuring ? Text("正在统计…") : Text("这里只列出 500 MB 以上的项目，按占用从大到小排列。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("重新统计") { Task { await model.measureSizes(force: true) } }
                .buttonStyle(.glass)
                .disabled(model.isMeasuring)
            Button("清理…") { showSheet = true }
                .buttonStyle(.glassProminent)
                .tint(.brand)
                .disabled(reclaimable == 0)
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .sheet(isPresented: $showSheet) { CleanupSheet(items: items) }
        .onReceive(NotificationCenter.default.publisher(for: .debugSheet)) { n in if n.object as? String == "cleanup" { showSheet = true } }
    }
}
