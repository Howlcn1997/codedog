import CodedogCore
import SwiftUI

struct SettingsView: View {
    @State private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            Tab("通用", systemImage: "gearshape", value: "general") { GeneralSettings() }
            Tab("扫描", systemImage: "folder", value: "scan") { ScanSettings() }
            Tab("打开方式", systemImage: "arrow.up.forward.app", value: "open") { OpenSettings() }
        }
        .frame(width: 540, height: 420)
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
                Picker(title, selection: Binding(get: { current }, set: { set($0) })) {
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

private struct GeneralSettings: View {
    @Environment(LibraryModel.self) private var model
    @State private var loginEnabled = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.needsApproval
    @State private var loginError: String?
    @State private var cliStatus = CLIInstaller.status
    @State private var cliPathOK = true
    @State private var cliMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("常驻菜单栏", isOn: Binding(
                    get: { model.library.preferences.menuBarResident },
                    set: { v in model.setPreferences { $0.menuBarResident = v } }))
                Text("关闭主窗口后 codedog 继续在菜单栏运行，随时用快捷键呼出启动器；Dock 图标会一起隐藏。")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("登录时启动", isOn: Binding(get: { loginEnabled }, set: { setLogin($0) }))
                if loginNeedsApproval {
                    HStack {
                        Text("需要在系统设置里允许 codedog 登录时启动。").font(.caption).foregroundStyle(.orange)
                        Button("打开系统设置") { LoginItem.openSystemSettings() }.controlSize(.small)
                    }
                }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }

            Section("启动器") {
                LabeledContent("快捷键") { ShortcutRecorder() }
                Text("在任何地方按下快捷键呼出启动器：输入名称，↑↓ 选择，←→ 切换操作，↵ 打开。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("更新") {
                Toggle("自动检查新版本", isOn: Binding(
                    get: { model.library.preferences.checkForUpdates },
                    set: { v in model.setPreferences { $0.checkForUpdates = v } }))
                LabeledContent("当前版本 \(Codedog.version)") {
                    HStack {
                        if model.isCheckingUpdate { ProgressView().controlSize(.small) }
                        if let u = model.availableUpdate {
                            Button("下载 \(u.version)") { NSWorkspace.shared.open(u.url) }
                        }
                        Button("立即检查") { Task { await model.checkForUpdates(manual: true) } }
                            .disabled(model.isCheckingUpdate)
                    }
                }
                Text("从 GitHub Releases 检查，每天最多一次，不上传任何信息。codedog 没有开发者签名，新版本需要手动下载替换。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("命令行工具") {
                LabeledContent("codedog") {
                    switch cliStatus {
                    case .installed:
                        HStack {
                            Label(CLIInstaller.pointsToThisApp ? "已安装" : "已安装（指向旧位置）", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(CLIInstaller.pointsToThisApp ? .green : .orange)
                            if !CLIInstaller.pointsToThisApp { Button("修复") { install() } }
                            Button("卸载") { uninstall() }
                        }
                    case .notInstalled:
                        Button("安装到 ~/.local/bin") { install() }
                    case .conflict:
                        Label("~/.local/bin/codedog 已被其他程序占用", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                Text("在终端里用 codedog open web、cd \"$(codedog path web)\"、codedog list 快速找到项目。")
                    .font(.caption).foregroundStyle(.secondary)
                if cliStatus == .installed && !cliPathOK {
                    Text("你的 PATH 里还没有 ~/.local/bin，请在 shell 配置中加入：export PATH=\"$HOME/.local/bin:$PATH\"")
                        .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
                if let cliMessage { Text(cliMessage).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .task { cliPathOK = await CLIInstaller.pathContainsLocalBin() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginEnabled = LoginItem.isEnabled
            loginNeedsApproval = LoginItem.needsApproval
        }
    }

    private func setLogin(_ on: Bool) {
        do {
            try LoginItem.set(on)
            loginError = nil
        } catch {
            loginError = "设置失败：\(error.localizedDescription)"
        }
        loginEnabled = LoginItem.isEnabled
        loginNeedsApproval = LoginItem.needsApproval
    }

    private func install() {
        do { try CLIInstaller.install(); cliMessage = nil } catch { cliMessage = error.localizedDescription }
        cliStatus = CLIInstaller.status
    }

    private func uninstall() {
        do { try CLIInstaller.uninstall(); cliMessage = nil } catch { cliMessage = error.localizedDescription }
        cliStatus = CLIInstaller.status
    }
}

/// 快捷键录制：点一下进入录制，按下组合键保存，Esc 取消。
private struct ShortcutRecorder: View {
    @Environment(LibraryModel.self) private var model
    @State private var recording = false
    @State private var monitor: Any?
    @State private var error: String?

    var body: some View {
        let current = Shortcut(string: model.library.preferences.launcherShortcut) ?? .default
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Button {
                    recording ? stop() : start()
                } label: {
                    Text(recording ? "请按下新的快捷键…" : current.display)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .frame(minWidth: 140)
                }
                .buttonStyle(.bordered)
                .tint(recording ? .brand : nil)
                if current != .default {
                    Button("恢复默认") { apply(.default) }.buttonStyle(.borderless)
                }
            }
            if let error = error ?? AppDelegate.shared.hotKeyError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        error = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }  // Esc
            if let s = Shortcut(event: event) {
                apply(s)
                stop()
            } else {
                error = "需要包含 ⌘、⌥ 或 ⌃，并配合字母、数字、空格或 F 键"
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func apply(_ s: Shortcut) {
        if let err = AppDelegate.shared.registerHotKey(s.string) {
            error = err
        } else {
            error = nil
            model.setPreferences { $0.launcherShortcut = s.string }
        }
    }
}
