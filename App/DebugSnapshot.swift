#if DEBUG
import AppKit

/// 调试用：设置 CODEDOG_SNAPSHOT=/path/prefix 后，App 定时把主窗口渲染成 PNG（无需屏幕录制权限）。
/// 可选 CODEDOG_SNAPSHOT_ACTIONS 为逗号分隔的动作脚本，例如 "wait:6,shot:grid,key:list,shot:list"。
@MainActor
enum DebugSnapshot {
    static func startIfRequested(model: LibraryModel) {
        guard let prefix = ProcessInfo.processInfo.environment["CODEDOG_SNAPSHOT"] else { return }
        let script = ProcessInfo.processInfo.environment["CODEDOG_SNAPSHOT_ACTIONS"] ?? "wait:8,shot:main"
        Task { @MainActor in
            for step in script.split(separator: ",") {
                let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
                let arg = parts.count > 1 ? parts[1] : ""
                switch parts[0] {
                case "wait": try? await Task.sleep(for: .seconds(Double(arg) ?? 1))
                case "shot": capture(to: "\(prefix)-\(arg).png")
                case "select": model.selectedID = model.visible.dropFirst(Int(arg) ?? 0).first?.item.id
                case "list": model.viewMode = .list
                case "grid": model.viewMode = .grid
                case "search": model.searchText = arg
                case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
                case "light": NSApp.appearance = NSAppearance(named: .aqua)
                case "detail":
                    if arg == "off" { model.detailID = nil }
                    else if let name = model.visible.first(where: { $0.item.project.name == arg })?.item.id { model.detailID = name }
                    else { model.detailID = model.visible.dropFirst(Int(arg) ?? 0).first?.item.id }
                case "size":
                    let wh = arg.split(separator: "x").compactMap { Double($0) }
                    if wh.count == 2, let w = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
                        w.setContentSize(NSSize(width: wh[0], height: wh[1]))
                    }
                case "activate":
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    NSRunningApplication.current.activate(options: [.activateAllWindows])
                    if let w = NSApp.windows.first(where: { $0.title == "codedog" }) {
                        w.deminiaturize(nil)
                        w.makeKeyAndOrderFront(nil)
                        w.orderFrontRegardless()
                    }
                case "settings": NotificationCenter.default.post(name: .openSettingsRequest, object: nil)
                case "launcher": AppDelegate.shared.launcher.show()
                case "lquery": AppDelegate.shared.launcher.state.query = arg
                case "ldown": AppDelegate.shared.launcher.state.selection += Int(arg) ?? 1
                case "lright": AppDelegate.shared.launcher.state.action += Int(arg) ?? 1
                case "smart": if let f = SmartFolder(rawValue: arg) { model.selection = .smart(f) }
                case "sizes": print("[sizes] measured=\(model.sizes.count) measuring=\(model.isMeasuring) total=\(model.sizes.values.map(\.total).reduce(0, +)) reclaimable=\(model.sizes.values.map(\.reclaimable).reduce(0, +))")
                case "newproject": NotificationCenter.default.post(name: .debugSheet, object: "new")
                case "cleanup": NotificationCenter.default.post(name: .debugSheet, object: "cleanup")
                case "windows":
                    for w in NSApp.windows { print("[window]", String(describing: type(of: w)), w.isVisible, w.frame) }
                case "quit":
                    // 先关掉打开的表单，否则 terminate 会被表单拦下
                    for w in NSApp.windows { if let sheet = w.attachedSheet { w.endSheet(sheet) } }
                    try? await Task.sleep(for: .milliseconds(300))
                    NSApp.terminate(nil)
                    // 兜底：仍被表单等拦住时 2 秒后直接退出（仅调试版）
                    try? await Task.sleep(for: .seconds(2))
                    exit(0)
                default: break
                }
            }
        }
    }

    static func capture(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.title == "codedog" }) ?? NSApp.windows.first(where: \.isVisible),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
    }
}
#endif
