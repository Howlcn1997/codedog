import CodedogCore
import SwiftUI

/// 批量清理：列出所有可清理的项目，默认全选，确认后移到废纸篓。
struct CleanupSheet: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var items: [ProjectItem]
    @State private var selected: Set<String> = []
    @State private var cleaning = false

    private var plans: [(item: ProjectItem, plan: [CleanupItem], bytes: Int64)] {
        items.compactMap { item in
            guard let size = item.size else { return nil }
            let plan = DependencyCleaner.plan(project: item.id, size: size)
            let bytes = plan.map(\.bytes).reduce(0, +)
            return plan.isEmpty ? nil : (item, plan, bytes)
        }
        .sorted { $0.bytes > $1.bytes }
    }

    var body: some View {
        let rows = plans
        let total = rows.filter { selected.contains($0.item.id) }.map(\.bytes).reduce(0, +)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("清理依赖与构建缓存").font(.title3.bold())
                Text("会移到废纸篓，可以还原；重新安装依赖或构建即可恢复。").font(.callout).foregroundStyle(.secondary)
            }
            List {
                ForEach(rows, id: \.item.id) { row in
                    Toggle(isOn: Binding(get: { selected.contains(row.item.id) },
                                         set: { on in if on { selected.insert(row.item.id) } else { selected.remove(row.item.id) } })) {
                        HStack(spacing: 10) {
                            StackBadge(project: row.item.project, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.item.project.name).lineLimit(1)
                                Text(row.plan.map { ($0.directory as NSString).lastPathComponent }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: "、"))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if (row.item.project.git?.dirtyFiles ?? 0) > 0 || !row.item.running.isEmpty {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                    .help(!row.item.running.isEmpty ? "AI 正在这个项目里运行" : "有未提交的改动（不影响清理依赖）")
                            }
                            Text(Formatting.bytes(row.bytes)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .listStyle(.bordered)
            .frame(minHeight: 280)
            HStack {
                Button(selected.count == rows.count ? "全不选" : "全选") {
                    selected = selected.count == rows.count ? [] : Set(rows.map(\.item.id))
                }
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button {
                    cleaning = true
                    let chosen = rows.filter { selected.contains($0.item.id) }.flatMap(\.plan)
                    Task {
                        await model.clean(chosen)
                        cleaning = false
                        dismiss()
                    }
                } label: {
                    Text(cleaning ? "清理中…" : "移到废纸篓 · \(Formatting.bytes(total))")
                }
                .buttonStyle(.borderedProminent)
                .tint(.brand)
                .disabled(selected.isEmpty || cleaning)
            }
        }
        .padding(20)
        .frame(width: 560, height: 480)
        .onAppear {
            // 默认不勾选 AI 正在运行的项目
            selected = Set(rows.filter { $0.item.running.isEmpty }.map(\.item.id))
        }
    }
}

/// 新建项目表单。
struct NewProjectSheet: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var parent = ""
    @State private var gitInit = true
    @State private var readme = true
    @State private var picking = false
    @State private var creating = false

    var body: some View {
        let valid = ProjectCreator.isValidName(name.trimmingCharacters(in: .whitespaces))
        VStack(alignment: .leading, spacing: 16) {
            Text("新建项目").font(.title3.bold())
            Form {
                TextField("名称", text: $name, prompt: Text("my-app"))
                if !name.isEmpty && !valid {
                    Text("只能包含字母、数字、中文、点、横线和下划线，且不能以点开头。").font(.caption).foregroundStyle(.red)
                }
                LabeledContent("位置") {
                    HStack {
                        Picker("位置", selection: $parent) {
                            ForEach(model.library.scanRoots, id: \.self) { Text(Formatting.shortPath($0)).tag($0) }
                            if !parent.isEmpty && !model.library.scanRoots.contains(parent) {
                                Text(Formatting.shortPath(parent)).tag(parent)
                            }
                        }
                        .labelsHidden()
                        Button("选择…") { picking = true }
                    }
                }
                Toggle("初始化 Git 仓库", isOn: $gitInit)
                Toggle("创建 README.md", isOn: $readme)
                if valid && !parent.isEmpty {
                    Text("将创建 \(Formatting.shortPath(parent))/\(name.trimmingCharacters(in: .whitespaces))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button(creating ? "创建中…" : "创建") {
                    creating = true
                    Task {
                        if await model.createProject(name: name, in: parent, gitInit: gitInit, readme: readme) { dismiss() }
                        creating = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.brand)
                .keyboardShortcut(.defaultAction)
                .disabled(!valid || parent.isEmpty || creating)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { if parent.isEmpty { parent = model.library.scanRoots.first ?? NSHomeDirectory() } }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { r in
            if case .success(let url) = r { parent = FolderScanner.normalize(url.path(percentEncoded: false)) }
        }
    }
}
