import CodedogCore
import SwiftUI

struct RootView: View {
    @Environment(LibraryModel.self) private var model
    @State private var newCategoryName = ""
    @State private var newCategoryFor: String?
    @State private var showNewCategory = false
    @State private var addingProject = false

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
        .onChange(of: model.selection) { model.bucketFilter = nil }
        .onReceive(NotificationCenter.default.publisher(for: .newCategory)) { note in
            newCategoryFor = note.object as? String
            newCategoryName = ""
            showNewCategory = true
        }
        .alert("新建分类", isPresented: $showNewCategory) {
            TextField("分类名称", text: $newCategoryName)
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
            Button("添加项目", systemImage: "folder.badge.plus") { addingProject = true }
                .help("添加不在扫描目录里的项目")
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
                Picker("排序", selection: $model.sortOrder) {
                    ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("排序", systemImage: "arrow.up.arrow.down")
            }
            .help("排序：\(model.sortOrder.title)")
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
            ZStack(alignment: .topTrailing) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.25))
                    .ignoresSafeArea()
                    .onTapGesture { closeDetail() }
                ProjectDetailView(item: item)
                Button { closeDetail() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .keyboardShortcut(.cancelAction)
                .padding(.top, 12)
                .padding(.trailing, 16)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
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
