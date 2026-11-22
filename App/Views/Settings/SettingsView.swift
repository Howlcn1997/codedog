import CodedogCore
import SwiftUI

/// 设置页按用户要做的事分组。
enum SettingsPage: String, CaseIterable, Identifiable {
    case general, scan, open, cli, about

    var id: Self { self }
    var title: String {
        switch self {
        case .general: String(localized: "通用")
        case .scan: String(localized: "扫描")
        case .open: String(localized: "打开方式")
        case .cli: String(localized: "命令行")
        case .about: String(localized: "关于")
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .scan: "folder"
        case .open: "arrow.up.forward.app"
        case .cli: "apple.terminal"
        case .about: "info.circle"
        }
    }
}

/// 系统设置风格的窗口：悬浮毛玻璃侧栏 + 大标题 + 白色分组卡片。
struct SettingsView: View {
    static let size = CGSize(width: 760, height: 500)
    static let sidebarWidth: CGFloat = 176
    @State private var page: SettingsPage = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(page.title)
                        .font(.system(size: 26, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 22)
                    detail
                }
                .padding(.horizontal, 30)
                .padding(.top, 34)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollEdgeEffectHidden(true, for: .top)
            .id(page)
        }
        .background(GlassMaterial(material: .windowBackground))
        .background(SettingsWindowStyler())
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: .title)
        .font(.system(size: 13))
        // 先铺满标题栏区域，再定窗口内容尺寸，避免底部留白。
        .ignoresSafeArea()
        .frame(width: Self.size.width, height: Self.size.height)
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .debugSettingsPage)) { n in
            if let raw = n.object as? String, let p = SettingsPage(rawValue: raw) { page = p }
        }
        #endif
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPage.allCases) { item in
                let selected = item == page
                Button { page = item } label: {
                    HStack(spacing: 8) {
                        SettingsGlyph(symbol: item.symbol, size: 15, filled: selected)
                        Text(item.title).font(.system(size: 14))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)  // 英文等较长的名称不折行
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 34)
                    .background(selected ? SettingsPalette.selection : .clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
            QuitButton()
        }
        .padding(.horizontal, 8)
        .padding(.top, 50)
        .padding(.bottom, 8)
        .frame(width: Self.sidebarWidth)
        .frame(maxHeight: .infinity)
        // 悬浮的玻璃面板代替硬分隔线：圆角、内缩、淡淡的光边和阴影。
        .background {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            GlassMaterial(material: .sidebar)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        }
        .padding(8)
    }

    @ViewBuilder private var detail: some View {
        switch page {
        case .general: GeneralSettingsPage()
        case .scan: ScanSettingsPage()
        case .open: OpenSettingsPage()
        case .cli: CLISettingsPage()
        case .about: AboutSettingsPage()
        }
    }
}

/// 侧栏左下角的退出按钮，悬停变红。
private struct QuitButton: View {
    @State private var hovering = false

    var body: some View {
        Button { NSApp.terminate(nil) } label: {
            Image(systemName: "power")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hovering ? Color.red : Color.secondary)
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(hovering ? 0.08 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("退出 codedog")
        .accessibilityLabel("退出 codedog")
    }
}

// MARK: - 通用

private struct GeneralSettingsPage: View {
    @Environment(LibraryModel.self) private var model
    @State private var loginEnabled = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.needsApproval
    @State private var loginError: String?
    @State private var language = AppLanguage.selected

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection("外观") {
                AppearancePicker(selection: Binding(
                    get: { AppearanceMode(rawValue: model.library.preferences.appearance) ?? .system },
                    set: { mode in
                        AppearanceMode.apply(mode.rawValue)
                        model.setPreferences { $0.appearance = mode.rawValue }
                    }))
                folderTransparencyRow
                SettingsRow("App 图标") {
                    AppIconPicker(selection: Binding(
                        get: { AppIconStyle(rawValue: model.library.preferences.appIcon) ?? .light },
                        set: { style in
                            AppIconStyle.apply(style.rawValue)
                            model.setPreferences { $0.appIcon = style.rawValue }
                        }))
                }
            }

            SettingsSection("语言") {
                languageRow
            }

            SettingsSection("启动") {
                SettingsRow("常驻菜单栏") {
                    SettingsSwitch("常驻菜单栏", isOn: Binding(
                        get: { model.library.preferences.menuBarResident },
                        set: { v in model.setPreferences { $0.menuBarResident = v } }))
                }
                SettingsRow("登录时启动",
                            subtitle: loginError.map { .verbatim($0) } ?? (loginNeedsApproval ? "需要在系统设置的登录项中允许 codedog" : nil),
                            subtitleTone: loginError != nil ? .red : (loginNeedsApproval ? .orange : .secondary)) {
                    if loginNeedsApproval {
                        SettingsButton("打开登录项") { LoginItem.openSystemSettings() }
                    }
                    SettingsSwitch("登录时启动", isOn: Binding(get: { loginEnabled }, set: { v in setLogin(v) }))
                }
            }

            SettingsSection("启动器") {
                SettingsRow("快捷键") {
                    ShortcutRecorder()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginEnabled = LoginItem.isEnabled
            loginNeedsApproval = LoginItem.needsApproval
        }
    }

    /// 界面语言：选好后需要重启 App 才能生效，提供"立即重启"。
    /// 文件夹透明度：0% 不透明；调高后能透过文件夹前片看到里面的文件。
    private var folderTransparencyRow: some View {
        let value = model.library.preferences.folderTransparency
        return SettingsRow("文件夹透明度") {
            Slider(value: Binding(
                get: { value },
                set: { v in
                    let snapped = (v * 20).rounded() / 20   // 每档 5%
                    model.setPreferences { $0.folderTransparency = snapped }
                }), in: 0...0.3)
                .frame(width: 140)
                .controlSize(.small)
            Text(verbatim: "\(Int((value * 100).rounded()))%")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private var languageRow: some View {
        let _ = language // 选择变化时刷新
        let pending = AppLanguage.needsRelaunch
        return SettingsRow("界面语言",
                           subtitle: pending ? "重新启动 codedog 后生效" : nil,
                           subtitleTone: pending ? .orange : .secondary) {
            if pending {
                SettingsButton("立即重启", kind: .prominent) { AppLanguage.relaunch() }
            }
            SettingsChoice(title: "界面语言",
                           options: AppLanguage.allCases.map { .init(value: $0, title: $0.title, icon: nil) },
                           selection: Binding(get: { language }, set: { v in
                               AppLanguage.selected = v
                               language = v
                           })) {
                Text(language.title).font(.system(size: 12))
            }
        } icon: {
            SettingsGlyph(symbol: "globe", size: 17)
        }
    }

    private func setLogin(_ on: Bool) {
        do {
            try LoginItem.set(on)
            loginError = nil
        } catch {
            loginError = String(localized: "设置失败：\(error.localizedDescription)")
        }
        loginEnabled = LoginItem.isEnabled
        loginNeedsApproval = LoginItem.needsApproval
    }
}

/// 三张外观卡片：每张画一个迷你窗口预览，选中时描品牌色边框。
private struct AppearancePicker: View {
    @Binding var selection: AppearanceMode

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                let selected = mode == selection
                Button { withAnimation(.spring(duration: 0.3, bounce: 0.3)) { selection = mode } } label: {
                    VStack(spacing: 8) {
                        preview(mode)
                            .frame(height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(selected ? Color.brand : SettingsPalette.hairline, lineWidth: selected ? 2 : 0.5))
                            .padding(selected ? 0 : 1)
                        Text(mode.title)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SettingsPressStyle())
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(12)
    }

    @ViewBuilder private func preview(_ mode: AppearanceMode) -> some View {
        switch mode {
        case .light: MiniWindow(dark: false)
        case .dark: MiniWindow(dark: true)
        case .system:
            // 左亮右暗，斜切拼在一起。
            ZStack {
                MiniWindow(dark: false)
                MiniWindow(dark: true).mask(DiagonalHalf())
            }
        }
    }
}

/// App 图标款式：小黑狗、小白狗两个图标，选中时描品牌色圆角边框。
private struct AppIconPicker: View {
    @Binding var selection: AppIconStyle

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppIconStyle.allCases, id: \.self) { style in
                let selected = style == selection
                Button { selection = style } label: {
                    icon(style)
                        .frame(width: 38, height: 38)
                        .padding(3)
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(selected ? Color.brand : Color.clear, lineWidth: 2))
                        .contentShape(Rectangle())
                }
                .buttonStyle(SettingsPressStyle())
                .help(style.title)
                .accessibilityLabel(style.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private func icon(_ style: AppIconStyle) -> some View {
        if let image = style.image { Image(nsImage: image).resizable().interpolation(.high) }
    }
}

/// 迷你窗口：侧栏 + 两张卡片 + 品牌色强调条。
private struct MiniWindow: View {
    let dark: Bool

    var body: some View {
        let bg = dark ? Color(white: 0.16) : Color(white: 0.96)
        let side = dark ? Color(white: 0.24) : Color(white: 0.88)
        let card = dark ? Color(white: 0.30) : Color.white
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(side).frame(width: 26)
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(Color.brand).frame(width: 30, height: 5)
                RoundedRectangle(cornerRadius: 3).fill(card).frame(height: 14)
                RoundedRectangle(cornerRadius: 3).fill(card).frame(height: 14)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bg)
    }
}

private struct DiagonalHalf: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.maxX * 0.6, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX * 0.4, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

/// 快捷键录制：点一下进入录制，按下组合键保存，Esc 取消。
private struct ShortcutRecorder: View {
    @Environment(LibraryModel.self) private var model
    @State private var recording = false
    @State private var monitor: Any?
    @State private var error: String?
    @State private var hovered = false

    var body: some View {
        let current = Shortcut(string: model.library.preferences.launcherShortcut) ?? .default
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                if current != .default && !recording {
                    SettingsIconButton(symbol: "arrow.uturn.backward", help: "恢复默认") { apply(.default) }
                }
                Button {
                    recording ? stop() : start()
                } label: {
                    Group {
                        if recording {
                            Text("请按下快捷键…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.brand)
                                .padding(.horizontal, 6)
                        } else {
                            SettingsKeycaps(keys: current.keys)
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(height: 28)
                    .background(Capsule().fill(recording ? Color.brand.opacity(0.12) : Color.primary.opacity(hovered ? 0.1 : 0.06)))
                    .overlay(Capsule().strokeBorder(Color.brand.opacity(recording ? 0.6 : 0), lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(SettingsPressStyle())
                .onHover { hovered = $0 }
                .accessibilityLabel(recording ? Text("正在录制快捷键") : Text("快捷键 \(current.display)"))
            }
            if let error = error ?? AppDelegate.shared.hotKeyError {
                Text(error).font(.system(size: 11)).foregroundStyle(.red)
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.3), value: recording)
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
                error = String(localized: "需要包含 ⌘、⌥ 或 ⌃，并配合字母、数字、空格或 F 键")
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

private extension Shortcut {
    /// 拆成一个个键帽：⌃ ⌥ ⇧ ⌘ + 按键。
    var keys: [String] {
        var k: [String] = []
        if modifiers.contains(.control) { k.append("⌃") }
        if modifiers.contains(.option) { k.append("⌥") }
        if modifiers.contains(.shift) { k.append("⇧") }
        if modifiers.contains(.command) { k.append("⌘") }
        k.append(Self.keyNames.first { $0.code == Int(keyCode) }?.symbol ?? "?")
        return k
    }
}

// MARK: - 扫描

private struct ScanSettingsPage: View {
    @Environment(LibraryModel.self) private var model
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection("扫描目录") {
                SettingsButton("添加…") { picking = true }
            } content: {
                if model.library.scanRoots.isEmpty {
                    SettingsRow("还没有扫描目录") {
                        SettingsButton("添加文件夹", kind: .prominent) { picking = true }
                    }
                } else {
                    ForEach(model.library.scanRoots, id: \.self) { root in
                        SettingsRow(.verbatim((root as NSString).lastPathComponent), subtitle: .verbatim(Formatting.shortPath(root))) {
                            SettingsIconButton(symbol: "minus", help: "移除", destructive: true) {
                                model.setScanRoots(model.library.scanRoots.filter { $0 != root })
                            }
                        } icon: {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: root))
                                .resizable().frame(width: 24, height: 24)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }

            SettingsSection("状态") {
                SettingsRow("已发现项目", subtitle: model.isScanning ? "正在扫描…" : "共 \(model.projects.count) 个项目") {
                    if model.isScanning { ProgressView().controlSize(.small) }
                    SettingsButton("重新扫描") { Task { await model.rescan(full: true) } }
                        .disabled(model.isScanning)
                }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                let added = urls.map { $0.path(percentEncoded: false) }.filter { !model.library.scanRoots.contains($0) }
                model.setScanRoots(model.library.scanRoots + added)
            }
        }
    }
}

// MARK: - 打开方式

private struct OpenSettingsPage: View {
    @Environment(LibraryModel.self) private var model
    @State private var pickingEditor = false
    @State private var pickingTerminal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection("默认应用") {
                appRow("编辑器",
                       current: model.library.preferences.editor, choices: Opener.installedEditors,
                       fallback: Opener.installedEditors.first,
                       set: { app in model.setPreferences { $0.editor = app } },
                       pick: { pickingEditor = true })
                appRow("终端",
                       current: model.library.preferences.terminal, choices: Opener.installedTerminals,
                       fallback: KnownApps.defaultTerminal,
                       set: { app in model.setPreferences { $0.terminal = app } },
                       pick: { pickingTerminal = true })
            }
        }
        .fileImporter(isPresented: $pickingEditor, allowedContentTypes: [.application]) { r in
            if case .success(let url) = r, let ref = Opener.appRef(at: url) { model.setPreferences { $0.editor = ref } }
        }
        .fileImporter(isPresented: $pickingTerminal, allowedContentTypes: [.application]) { r in
            if case .success(let url) = r, let ref = Opener.appRef(at: url) { model.setPreferences { $0.terminal = ref } }
        }
    }

    private func appRow(_ title: LocalizedStringKey, current: AppRef?, choices: [AppRef], fallback: AppRef?,
                        set: @escaping (AppRef?) -> Void, pick: @escaping () -> Void) -> some View {
        var list = choices
        if let current, !list.contains(current) { list.append(current) }
        let shown = current ?? fallback
        let auto = String(localized: "自动（\(fallback?.name ?? String(localized: "未找到"))）")
        let options: [SettingsChoice<AppRef?, AnyView>.Option] =
            [.init(value: nil, title: auto, icon: nil)]
            + list.map { .init(value: $0, title: $0.name, icon: AppIconView.icon($0)) }
        return SettingsRow(title) {
            SettingsChoice(title: title, options: options,
                           selection: Binding(get: { current }, set: { v in set(v) }),
                           extra: (String(localized: "其他应用…"), pick)) {
                AnyView(Text(current?.name ?? auto)
                    .font(.system(size: 12)))
            }
        } icon: {
            Group {
                if let shown {
                    AppIconView(app: shown, size: 28)
                } else {
                    SettingsGlyph(symbol: "app.dashed", size: 17)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

// MARK: - 命令行

private struct CLISettingsPage: View {
    @State private var status = CLIInstaller.status
    @State private var pathOK = true
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection("命令行工具") {
                SettingsRow("codedog", subtitle: message.map { .verbatim($0) } ?? subtitle, subtitleTone: message != nil ? .red : .secondary) {
                    switch status {
                    case .installed:
                        SettingsStatus(text: CLIInstaller.pointsToThisApp ? "已安装" : "指向旧位置",
                                       tone: CLIInstaller.pointsToThisApp ? .good : .attention)
                        if !CLIInstaller.pointsToThisApp { SettingsButton("修复", kind: .prominent) { install() } }
                        SettingsButton("卸载") { uninstall() }
                    case .notInstalled:
                        SettingsStatus(text: "未安装", tone: .neutral)
                        SettingsButton("安装", kind: .prominent) { install() }
                    case .conflict:
                        SettingsStatus(text: "路径被占用", tone: .attention)
                    }
                } icon: {
                    SettingsGlyph(symbol: "apple.terminal", size: 17)
                }
                if status == .installed && !pathOK {
                    SettingsRow("PATH 中没有 ~/.local/bin", subtitle: "在 shell 配置中加入：export PATH=\"$HOME/.local/bin:$PATH\"",
                                subtitleTone: .orange) {
                        SettingsButton("复制") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("export PATH=\"$HOME/.local/bin:$PATH\"", forType: .string)
                        }
                    } icon: {
                        SettingsGlyph(symbol: "exclamationmark.triangle", size: 16, tint: .orange)
                    }
                }
            }

            SettingsSection("常用命令") {
                command("codedog list", "列出所有项目")
                command("codedog open web", "用默认编辑器打开名字匹配 web 的项目")
                command("cd \"$(codedog path web)\"", "跳到项目目录")
            }
        }
        .task { pathOK = await CLIInstaller.pathContainsLocalBin() }
    }

    private var subtitle: LocalizedStringKey? {
        status == .conflict ? "~/.local/bin/codedog 已被其他程序占用" : nil
    }

    private func command(_ cmd: String, _ desc: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Text(cmd)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
            Spacer(minLength: 12)
            Text(desc).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
    }

    private func install() {
        do { try CLIInstaller.install(); message = nil } catch { message = error.localizedDescription }
        status = CLIInstaller.status
    }

    private func uninstall() {
        do { try CLIInstaller.uninstall(); message = nil } catch { message = error.localizedDescription }
        status = CLIInstaller.status
    }
}

// MARK: - 关于

private struct AboutSettingsPage: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().scaledToFit().frame(width: 52, height: 52)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("codedog").font(.system(size: 15, weight: .semibold))
                        Text("版本 \(Codedog.version)").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
            }

            SettingsSection("更新") {
                SettingsRow("自动检查新版本") {
                    SettingsSwitch("自动检查新版本", isOn: Binding(
                        get: { model.library.preferences.checkForUpdates },
                        set: { v in model.setPreferences { $0.checkForUpdates = v } }))
                }
                SettingsRow("检查更新", subtitle: updateSubtitle) {
                    if model.isCheckingUpdate { ProgressView().controlSize(.small) }
                    if let u = model.availableUpdate {
                        SettingsButton("下载 \(u.version)", kind: .prominent) { NSWorkspace.shared.open(u.url) }
                    }
                    SettingsButton("立即检查") { Task { await model.checkForUpdates(manual: true) } }
                        .disabled(model.isCheckingUpdate)
                }
            }
        }
    }

    private var updateSubtitle: LocalizedStringKey? {
        if model.isCheckingUpdate { return "正在检查…" }
        if let u = model.availableUpdate { return "有新版本 \(u.version) 可用" }
        return nil
    }
}
