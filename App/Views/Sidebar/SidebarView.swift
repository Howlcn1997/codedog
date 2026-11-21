import CodedogCore
import SwiftUI

struct SidebarView: View {
    @Environment(LibraryModel.self) private var model
    @State private var renaming: CodedogCore.Category?
    @State private var renameText = ""

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            row(.all, "全部项目", "square.grid.2x2")

            Section("智能文件夹") {
                ForEach(SmartFolder.allCases, id: \.self) { f in
                    if f != .hidden || model.count(.smart(.hidden)) > 0 {
                        row(.smart(f), f.title, f.symbol)
                    }
                }
            }

            Section("我的分类") {
                ForEach(model.library.categories) { c in
                    row(.category(c.id), c.name, "circle.fill", tint: CategoryPalette.color(c.color) ?? .secondary, small: true)
                        .contextMenu { categoryMenu(c) }
                }
                Button {
                    NotificationCenter.default.post(name: .newCategory, object: nil)
                } label: {
                    Label("新建分类", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if !model.toolsPresent.isEmpty {
                Section("AI 与编辑器") {
                    ForEach(model.toolsPresent, id: \.self) { t in
                        toolRow(t)
                    }
                }
            }

            if !model.kindsPresent.isEmpty {
                Section("项目类型") {
                    ForEach(model.kindsPresent, id: \.self) { k in
                        row(.kind(k), k.displayName, k.symbol)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { footer }
        .alert("重命名分类", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") { if let c = renaming { model.renameCategory(c.id, renameText) } }
        }
    }

    private func row(_ s: SidebarSelection, _ title: String, _ symbol: String, tint: Color? = nil, small: Bool = false) -> some View {
        Label {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                let n = model.count(s)
                Text("\(n)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .opacity(n == 0 ? 0.5 : 1)
            }
        } icon: {
            Image(systemName: symbol)
                .imageScale(small ? .small : .medium)
                .foregroundStyle(tint ?? .accentColor)
        }
        .tag(s)
    }

    private func toolRow(_ t: AITool) -> some View {
        Label {
            HStack {
                Text(t.displayName).lineLimit(1)
                Spacer()
                Text("\(model.count(.tool(t)))").monospacedDigit().foregroundStyle(.secondary)
            }
        } icon: {
            ToolIcon(tool: t, size: 16)
        }
        .tag(SidebarSelection.tool(t))
    }

    @ViewBuilder private func categoryMenu(_ c: CodedogCore.Category) -> some View {
        Button("一起打开", systemImage: "rectangle.stack") { model.openTogether(category: c.id) }
        Divider()
        Button("重命名…") { renameText = c.name; renaming = c }
        Menu("颜色") {
            ForEach(CategoryPalette.all, id: \.id) { p in
                Button { model.setCategoryColor(c.id, p.id) } label: {
                    Label(p.name, systemImage: c.color == p.id ? "checkmark.circle.fill" : "circle.fill")
                }
            }
            Divider()
            Button("去掉颜色") { model.setCategoryColor(c.id, nil) }
        }
        Divider()
        Button("删除分类", role: .destructive) { model.deleteCategory(c.id) }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("设置")
            Spacer()
            if model.isScanning {
                ProgressView().controlSize(.small)
                Text("正在扫描…").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
