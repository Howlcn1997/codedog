import AppKit
import Carbon.HIToolbox

/// 快捷键描述，持久化为 "cmd+shift+space" 这样的字符串。
struct Shortcut: Equatable {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags

    static let `default` = Shortcut(string: "cmd+shift+space")!

    static let keyNames: [(name: String, code: Int, symbol: String)] = {
        var list: [(String, Int, String)] = [
            ("space", kVK_Space, "Space"), ("return", kVK_Return, "↩"), ("tab", kVK_Tab, "⇥"),
            ("left", kVK_LeftArrow, "←"), ("right", kVK_RightArrow, "→"), ("up", kVK_UpArrow, "↑"), ("down", kVK_DownArrow, "↓"),
        ]
        let letters: [(String, Int)] = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D), ("e", kVK_ANSI_E), ("f", kVK_ANSI_F),
            ("g", kVK_ANSI_G), ("h", kVK_ANSI_H), ("i", kVK_ANSI_I), ("j", kVK_ANSI_J), ("k", kVK_ANSI_K), ("l", kVK_ANSI_L),
            ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O), ("p", kVK_ANSI_P), ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R),
            ("s", kVK_ANSI_S), ("t", kVK_ANSI_T), ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X),
            ("y", kVK_ANSI_Y), ("z", kVK_ANSI_Z),
            ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3), ("4", kVK_ANSI_4),
            ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7), ("8", kVK_ANSI_8), ("9", kVK_ANSI_9),
        ]
        list += letters.map { ($0.0, $0.1, $0.0.uppercased()) }
        let f = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        list += f.enumerated().map { ("f\($0.offset + 1)", $0.element, "F\($0.offset + 1)") }
        return list
    }()

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.command, .shift, .option, .control])
    }

    init?(string: String) {
        var mods: NSEvent.ModifierFlags = []
        var code: Int?
        for part in string.lowercased().split(separator: "+").map(String.init) {
            switch part {
            case "cmd", "command": mods.insert(.command)
            case "shift": mods.insert(.shift)
            case "option", "opt", "alt": mods.insert(.option)
            case "ctrl", "control": mods.insert(.control)
            default: code = Self.keyNames.first { $0.name == part }?.code
            }
        }
        guard let code, !mods.intersection([.command, .option, .control]).isEmpty else { return nil }
        self.init(keyCode: UInt32(code), modifiers: mods)
    }

    /// 从按键事件构造；必须包含 ⌘、⌥ 或 ⌃ 之一，且按键在支持列表里。
    init?(event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !mods.intersection([.command, .option, .control]).isEmpty,
              Self.keyNames.contains(where: { $0.code == Int(event.keyCode) }) else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: mods)
    }

    var string: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("option") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        parts.append(Self.keyNames.first { $0.code == Int(keyCode) }?.name ?? "space")
        return parts.joined(separator: "+")
    }

    var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + (Self.keyNames.first { $0.code == Int(keyCode) }?.symbol ?? "?")
    }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifiers.contains(.command) { m |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { m |= UInt32(shiftKey) }
        if modifiers.contains(.option) { m |= UInt32(optionKey) }
        if modifiers.contains(.control) { m |= UInt32(controlKey) }
        return m
    }
}

/// 全局快捷键（Carbon RegisterEventHotKey，不需要辅助功能权限）。
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private let id: UInt32
    private static var nextID: UInt32 = 1
    private static var installed = false
    fileprivate static var handlers: [UInt32: () -> Void] = [:]

    /// 注册失败（被其他 App 占用等）时返回 nil。
    init?(_ shortcut: Shortcut, handler: @escaping () -> Void) {
        Self.installHandlerIfNeeded()
        id = Self.nextID
        Self.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x43444F47), id: id)  // 'CDOG'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, ref != nil else { return nil }
        Self.handlers[id] = handler
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.handlers[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKey.handlers[id]?() } }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
