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
                        if model.searchText.isEmpty {
                            ActivityChart(buckets: model.activityBuckets)
                                .padding(.bottom, 10)
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
        @Bindable var model = model
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.system(size: 30, weight: .bold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(count) 个项目")
                    if let b = model.bucketFilter {
                        Button {
                            withAnimation(.snappy) { model.bucketFilter = nil }
                        } label: {
                            Label(b.label, systemImage: "xmark.circle.fill")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(TimeRange.allCases) { r in
                        let on = model.timeRange == r && model.bucketFilter == nil
                        Button(r.title) {
                            withAnimation(.snappy) {
                                model.timeRange = r
                                model.bucketFilter = nil
                            }
                        }
                        .buttonStyle(.glass)
                        .tint(on ? .accentColor : nil)
                        .fontWeight(on ? .semibold : .regular)
                        .controlSize(.large)
                    }
                }
            }
        }
    }

    private func grid(_ rows: [(item: ProjectItem, match: SearchMatch)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: FolderCard.size.width, maximum: FolderCard.size.width + 40), spacing: 26)], spacing: 30) {
            ForEach(rows, id: \.item.id) { row in
                FolderCard(item: row.item, match: row.match, isSelected: model.selectedID == row.item.id)
                    .onTapGesture {
                        model.selectedID = row.item.id
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.detailID = row.item.id }
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
            ContentUnavailableView("这里还没有项目", systemImage: "tray", description: Text("换个时间范围或分类看看。"))
        }
    }
}

/// 内容区背景：柔和的强调色光晕，衬托玻璃卡片。
struct BackdropView: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            (scheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.14) : Color(red: 0.96, green: 0.96, blue: 0.98))
            RadialGradient(colors: [Color.accentColor.opacity(scheme == .dark ? 0.16 : 0.10), .clear], center: .topTrailing, startRadius: 0, endRadius: 700)
            RadialGradient(colors: [Color.blue.opacity(scheme == .dark ? 0.10 : 0.06), .clear], center: .bottomLeading, startRadius: 0, endRadius: 600)
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
