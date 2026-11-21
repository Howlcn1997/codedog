import CodedogCore
import SwiftUI

struct RootView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var newCategoryName = ""
    @State private var newCategoryFor: String?
    @State private var showNewCategory = false
    @State private var addingProject = false
    @State private var creatingProject = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            LibraryView()
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "搜索项目、README、依赖…")
        .toolbar { toolbar }
        .onChange(of: model.selection) { model.pulse = nil }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequest)) { _ in openSettings() }
        .onReceive(NotificationCenter.default.publisher(for: .newCategory)) { note in
            newCategoryFor = note.object as? String
            newCategoryName = ""
            showNewCategory = true
        }
        .alert("新建标签", isPresented: $showNewCategory) {
            TextField("标签名称", text: $newCategoryName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                if let id = model.createCategory(newCategoryName), let path = newCategoryFor {
                    model.toggleCategory(path, id)
                }
            }
        }
        .alert("出错了", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .overlay { detailOverlay }
        .overlay(alignment: .bottom) { toastView }
        .fileImporter(isPresented: $addingProject, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.addProjects(urls) }
        }
        .sheet(isPresented: $creatingProject) { NewProjectSheet() }
        .onReceive(NotificationCenter.default.publisher(for: .debugSheet)) { n in if n.object as? String == "new" { creatingProject = true } }
        .onChange(of: model.selection) { _, s in
            // 进入"占空间"时自动按占用排序
            if s == .smart(.large) { model.sortOrder = .size } else if model.sortOrder == .size { model.sortOrder = .activity }
        }
        .task {
            #if DEBUG
            DebugSnapshot.startIfRequested(model: model)
            #endif
            await model.start()
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        @Bindable var model = model
        ToolbarItem {
            Menu {
                Button("新建项目…", systemImage: "plus.square") { creatingProject = true }
                Button("添加已有文件夹…", systemImage: "folder.badge.plus") { addingProject = true }
            } label: {
                Label("新建", systemImage: "plus")
            }
            .help("新建项目，或添加不在扫描目录里的文件夹")
        }
        ToolbarItem {
            Picker("视图", selection: $model.viewMode) {
                Label("卡片", systemImage: "square.grid.2x2").tag(ViewMode.grid)
                Label("列表", systemImage: "list.bullet").tag(ViewMode.list)
            }
            .pickerStyle(.segmented)
            .help("切换视图")
        }
        ToolbarItem {
            Menu {
                Picker("时间", selection: $model.timeRange) {
                    ForEach(TimeRange.allCases) { Text($0.menuTitle).tag($0) }
                }
                .pickerStyle(.inline)
                Picker("排序", selection: $model.sortOrder) {
                    ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("时间与排序", systemImage: model.timeRange == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
            }
            .help("时间：\(model.timeRange.menuTitle) · 排序：\(model.sortOrder.title)")
        }
        ToolbarSpacer(.fixed)
        ToolbarItem {
            Button {
                Task { await model.rescan() }
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
                    .symbolEffect(.rotate, isActive: model.isScanning)
            }
            .disabled(model.isScanning)
            .help(model.lastScan.map { "上次扫描：\($0.formatted(.relative(presentation: .named)))" } ?? "重新扫描")
        }
    }

    @ViewBuilder private var detailOverlay: some View {
        if let item = model.detailItem {
            ZStack(alignment: .trailing) {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture { closeDetail() }
                    .transition(.opacity)
                ProjectDetailView(item: item, onClose: closeDetail)
                    .frame(width: 620)
                    .padding(.vertical, 10)
                    .padding(.trailing, 10)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private func closeDetail() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { model.detailID = nil }
    }

    @ViewBuilder private var toastView: some View {
        if let text = model.toast {
            Text(text)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: Capsule())
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: text) {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { model.toast = nil }
                }
        }
    }
}
