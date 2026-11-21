import CodedogCore
import SwiftUI

/// 菜单栏菜单：启动器、等你回复、最近打开、主窗口、设置、退出。
struct MenuBarContent: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if let update = model.availableUpdate {
            Button("新版本 \(update.version) 可下载…") { NSWorkspace.shared.open(update.url) }
            Divider()
        }
        let shortcut = Shortcut(string: model.library.preferences.launcherShortcut)?.display ?? ""
        Button("打开启动器\t\(shortcut)") { AppDelegate.shared.launcher.show() }

        let items = model.items.filter { !$0.meta.hidden }
        let waiting = items.filter(\.waiting).sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
        if !waiting.isEmpty {
            Divider()
            Section("等你回复") {
                ForEach(waiting.prefix(5)) { item in
                    Button {
                        if let tool = item.lastAgent?.tool { model.open(item, .resume(tool)) } else { model.open(item) }
                    } label: {
                        Label { Text(item.project.name) } icon: { if let t = item.lastAgent?.tool { ToolIcon(tool: t) } }
                    }
                }
            }
        }

        let recent = items.filter { $0.meta.lastOpened != nil }.sorted(by: LibrarySnapshot.defaultOrder).prefix(6)
        if !recent.isEmpty {
            Divider()
            Section("最近打开") {
                ForEach(Array(recent)) { item in
                    Button(item.project.name) { model.open(item) }
                }
            }
        }

        Divider()
        Button("显示主窗口") { AppDelegate.shared.showMainWindow(openWindow) }
        Button("重新扫描") { Task { await model.rescan() } }
        Button("设置…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("退出 codedog") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
