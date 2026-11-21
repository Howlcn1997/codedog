import CodedogCore
import SwiftUI

@main
struct CodedogApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var model: LibraryModel { delegate.model }

    var body: some Scene {
        Window("codedog", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 620)
        }
        .defaultSize(width: 1240, height: 820)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新…") { Task { await model.checkForUpdates(manual: true) } }
            }
            CommandGroup(after: .newItem) {
                Button("打开启动器") { AppDelegate.shared.launcher.show() }
                Button("重新扫描") { Task { await model.rescan() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("放大卡片") { model.zoomCards(1) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("缩小卡片") { model.zoomCards(-1) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("实际大小") { model.zoomCards(0) }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
                Button(model.viewMode == .grid ? "列表视图" : "卡片视图") {
                    model.viewMode = model.viewMode == .grid ? .list : .grid
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra(isInserted: Binding(
            get: { model.library.preferences.menuBarResident },
            set: { v in model.setPreferences { $0.menuBarResident = v } }
        )) {
            MenuBarContent()
                .environment(model)
        } label: {
            Image("MenuBarDog")
        }
    }
}
