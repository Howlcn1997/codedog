import CodedogCore
import SwiftUI

@main
struct CodedogApp: App {
    @State private var model = LibraryModel()

    var body: some Scene {
        Window("codedog", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 620)
        }
        .defaultSize(width: 1240, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("重新扫描") { Task { await model.rescan() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
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
    }
}
