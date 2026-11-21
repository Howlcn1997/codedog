import CodedogCore
import SwiftUI

struct LibraryView: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        let visible = model.visible
        Group {
            if model.library.scanRoots.isEmpty && model.library.pinnedPaths.isEmpty {
                NoRootsView()
            } else if model.viewMode == .list {
                VStack(spacing: 0) {
                    header(count: visible.count).padding(.horizontal, 28).padding(.bottom, 8)
                    ProjectTable(rows: visible)
                }
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
                            empty.frame(maxWidth: .infinity, minHeight: 260)
                        } else {
                            grid(visible)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
        }
        .background { BackdropView() }
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
        var parts = ["\(count) 个项目"]
        if model.timeRange != .all { parts.append(model.timeRange.title) }
        if let p = model.pulse { parts.append(p.title) }
        return parts.joined(separator: " · ")
    }

    private func grid(_ rows: [(item: ProjectItem, match: SearchMatch)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: ProjectCard.size.width, maximum: ProjectCard.size.width + 60), spacing: 18)], spacing: 18) {
            ForEach(rows, id: \.item.id) { row in
                ProjectCard(item: row.item, match: row.match, isSelected: model.selectedID == row.item.id)
                    .onTapGesture {
                        model.selectedID = row.item.id
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { model.detailID = row.item.id }
                    }
                    .contextMenu { ProjectMenu(item: row.item) }
                    .help(Formatting.shortPath(row.item.id))
            }
        }
    }

    @ViewBuilder private var empty: some View {
        if !model.searchText.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else if model.isScanning && model.projects.isEmpty {
            ContentUnavailableView { Label("正在寻找项目…", systemImage: "magnifyingglass") } description: { Text("第一次扫描可能需要几秒钟。") }
        } else {
            ContentUnavailableView("这里还没有项目", systemImage: "tray", description: Text("换个时间范围或标签看看。"))
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

struct NoRootsView: View {
    @Environment(LibraryModel.self) private var model
    @State private var picking = false

    var body: some View {
        ContentUnavailableView {
            Label("告诉 codedog 你的代码放在哪里", systemImage: "folder.badge.questionmark")
        } description: {
            Text("选择一个或多个文件夹，codedog 会自动找到里面的项目，并在文件变化时保持更新。它不会移动或修改任何文件。")
        } actions: {
            Button("选择文件夹…") { picking = true }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                model.setScanRoots(model.library.scanRoots + urls.map { $0.path(percentEncoded: false) })
            }
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
                .help(on ? "取消筛选" : "只看\(p.title)的项目")
            }
        }
    }

    private func color(_ p: Pulse) -> Color {
        switch p {
        case .running: .green
        case .waiting: .orange
        case .dirty: .pink
        case .activeWeek: .brand
        }
    }
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
                Text(model.isMeasuring ? "正在统计…" : "这里只列出 500 MB 以上的项目，按占用从大到小排列。")
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
