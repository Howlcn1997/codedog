import AppKit
import CodedogCore
import SwiftUI

/// App 生命周期：启动扫描、注册全局快捷键、常驻菜单栏时的 Dock 图标策略。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate!

    let model = LibraryModel()
    private(set) lazy var launcher = LauncherController(model: model)
    private var hotKey: HotKey?
    private(set) var hotKeyError: String?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await model.start()
            registerHotKey(model.library.preferences.launcherShortcut)
            await model.checkForUpdates()
        }
        installZoomKeys()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let isMain = (note.object as? NSWindow)?.title == "codedog"
            MainActor.assumeIsolated {
                guard isMain, AppDelegate.shared.model.library.preferences.menuBarResident else { return }
                // 主窗口关闭后只留菜单栏图标
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    /// 主窗口里的 ⌘= / ⌘+ / ⌘- / ⌘0：⌘+ 实际按键是 ⌘=（不按 Shift），菜单快捷键不一定能匹配，这里统一处理。
    private func installZoomKeys() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .option, .control])
            guard mods == .command, NSApp.keyWindow?.title == "codedog",
                  let ch = event.charactersIgnoringModifiers else { return event }
            let step: Int? = switch ch {
            case "=", "+": 1
            case "-", "_": -1
            case "0": 0
            default: nil
            }
            guard let step else { return event }
            MainActor.assumeIsolated { AppDelegate.shared.model.zoomCards(step) }
            return nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !model.library.preferences.menuBarResident
    }

    /// 注册启动器快捷键；失败（被占用）时返回错误描述并保留旧快捷键。
    @discardableResult
    func registerHotKey(_ string: String) -> String? {
        guard let shortcut = Shortcut(string: string) else {
            hotKeyError = "快捷键格式无效"
            return hotKeyError
        }
        let old = hotKey
        old?.unregister()
        if let new = HotKey(shortcut, handler: { [weak self] in self?.launcher.toggle() }) {
            hotKey = new
            hotKeyError = nil
            return nil
        }
        // 恢复旧的
        if let previous = Shortcut(string: model.library.preferences.launcherShortcut), previous != shortcut {
            hotKey = HotKey(previous) { [weak self] in self?.launcher.toggle() }
        }
        hotKeyError = "\(shortcut.display) 已被其他 App 占用"
        return hotKeyError
    }

    /// 从菜单栏等处重新显示主窗口。
    func showMainWindow(_ openWindow: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate()
    }
}
