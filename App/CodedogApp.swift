import SwiftUI
import CodedogCore

@main
struct CodedogApp: App {
    var body: some Scene {
        WindowGroup("codedog", id: "main") {
            RootView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}

struct RootView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Label("全部项目", systemImage: "square.grid.2x2")
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            ContentUnavailableView("codedog", systemImage: "pawprint", description: Text("看见所有项目，最快打开它。"))
        }
    }
}
