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
                    NSApp.activate()
                    NSApp.windows.first { $0.title == "codedog" }?.makeKeyAndOrderFront(nil)
                case "quit": NSApp.terminate(nil)
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
