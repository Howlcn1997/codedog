import CodedogCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("扫描", systemImage: "folder") { ScanSettings() }
            Tab("打开方式", systemImage: "arrow.up.forward.app") { OpenSettings() }
        }
        .frame(width: 520, height: 380)
    }
}

private struct ScanSettings: View {
    @Environment(LibraryModel.self) private var model
    @State private var selection: String?
    @State private var picking = false

    var body: some View {
        Form {
            Section {
                List(selection: $selection) {
                    ForEach(model.library.scanRoots, id: \.self) { root in
                        Label(Formatting.shortPath(root), systemImage: "folder").tag(root)
                    }
                }
                .frame(minHeight: 140)
                HStack {
                    Button("添加…", systemImage: "plus") { picking = true }
                    Button("移除", systemImage: "minus") {
                        if let s = selection { model.setScanRoots(model.library.scanRoots.filter { $0 != s }) }
                    }
                    .disabled(selection == nil)
                    Spacer()
                    if model.isScanning { ProgressView().controlSize(.small) }
                    Text("共 \(model.projects.count) 个项目").foregroundStyle(.secondary)
                }
            } header: {
                Text("扫描目录")
            } footer: {
                Text("codedog 会在这些文件夹里寻找项目（最多 5 层），并在文件变化时自动更新。不会移动或修改任何文件。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                model.setScanRoots(model.library.scanRoots + urls.map { $0.path(percentEncoded: false) })
            }
        }
    }
}

private struct OpenSettings: View {
    @Environment(LibraryModel.self) private var model
    @State private var pickingEditor = false
    @State private var pickingTerminal = false

    var body: some View {
        Form {
            appPicker("默认编辑器", current: model.library.preferences.editor, choices: Opener.installedEditors, fallback: Opener.installedEditors.first?.name ?? "未找到") { app in
                model.setPreferences { $0.editor = app }
            } pick: { pickingEditor = true }
            appPicker("默认终端", current: model.library.preferences.terminal, choices: Opener.installedTerminals, fallback: KnownApps.defaultTerminal.name) { app in
                model.setPreferences { $0.terminal = app }
            } pick: { pickingTerminal = true }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $pickingEditor, allowedContentTypes: [.application]) { r in
            if case .success(let url) = r, let ref = Opener.appRef(at: url) { model.setPreferences { $0.editor = ref } }
        }
        .fileImporter(isPresented: $pickingTerminal, allowedContentTypes: [.application]) { r in
            if case .success(let url) = r, let ref = Opener.appRef(at: url) { model.setPreferences { $0.terminal = ref } }
        }
    }

    private func appPicker(_ title: String, current: AppRef?, choices: [AppRef], fallback: String, set: @escaping (AppRef?) -> Void, pick: @escaping () -> Void) -> some View {
        var list = choices
        if let current, !list.contains(current) { list.append(current) }
        return LabeledContent(title) {
            HStack {
                Picker(title, selection: Binding(get: { current }, set: set)) {
                    Text("自动（\(fallback)）").tag(AppRef?.none)
                    Divider()
                    ForEach(list, id: \.self) { app in
                        Label { Text(app.name) } icon: { Image(nsImage: AppIconView.icon(app)) }.tag(AppRef?.some(app))
                    }
                }
                .labelsHidden()
                .fixedSize()
                Button("其他…", action: pick)
            }
        }
    }
}
