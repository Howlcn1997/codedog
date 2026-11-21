import AppKit
import SwiftUI

/// 可以成为键盘焦点、但不激活整个 App 的浮动面板（不打断当前正在用的 App）。
final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LauncherController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 700, height: 470)
    private let panel: LauncherPanel
    private let model: LibraryModel
    let state = LauncherState()

    init(model: LibraryModel) {
        self.model = model
        panel = LauncherPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                              styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                              backing: .buffered, defer: true)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        let root = LauncherView(state: state, onClose: { [weak self] in self?.hide() })
            .environment(model)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() { panel.isVisible && panel.isKeyWindow ? hide() : show() }

    func show() {
        // 出现在鼠标所在屏幕的上三分之一
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: f.midX - Self.size.width / 2, y: f.minY + f.height * 0.62 - Self.size.height / 2))
        }
        state.reset()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() { panel.orderOut(nil) }

    func windowDidResignKey(_ notification: Notification) { hide() }
}

/// 启动器的交互状态（每次呼出时重置）。
@MainActor @Observable
final class LauncherState {
    var query = ""
    var selection = 0
    var action = 0
    /// 递增以让输入框重新获得焦点
    var focusToken = 0

    func reset() {
        query = ""
        selection = 0
        action = 0
        focusToken += 1
    }
}
