// 演示录制用的界面驱动：用辅助功能 API 找元素，模拟平滑的鼠标移动、点击、按键与输入。
// 编译：swiftc -O driver.swift -o build/driver
// 坐标一律是全局屏幕坐标（左上角原点，单位 pt）。
import AppKit
import ApplicationServices

func app(_ name: String) -> AXUIElement? {
    if let pid = Int32(name) { return AXUIElementCreateApplication(pid) }
    guard let r = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name || $0.bundleIdentifier == name }) else { return nil }
    return AXUIElementCreateApplication(r.processIdentifier)
}

func attr<T>(_ e: AXUIElement, _ a: String) -> T? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success else { return nil }
    return v as? T
}

func frame(_ e: AXUIElement) -> CGRect? {
    guard let p: AXValue = attr(e, kAXPositionAttribute), let s: AXValue = attr(e, kAXSizeAttribute) else { return nil }
    var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(p, .cgPoint, &pt); AXValueGetValue(s, .cgSize, &sz)
    return CGRect(origin: pt, size: sz)
}

func texts(_ e: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute, kAXIdentifierAttribute, kAXPlaceholderValueAttribute].compactMap { attr(e, $0) as String? }.filter { !$0.isEmpty }
}

func walk(_ e: AXUIElement, depth: Int = 0, _ body: (AXUIElement, Int) -> Bool) {
    if !body(e, depth) { return }
    guard depth < 40, let kids: [AXUIElement] = attr(e, kAXChildrenAttribute) else { return }
    for k in kids { walk(k, depth: depth + 1, body) }
}

func current() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

func post(_ type: CGEventType, _ p: CGPoint, button: CGMouseButton = .left, clicks: Int64 = 1) {
    let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button)!
    e.setIntegerValueField(.mouseEventClickState, value: clicks)
    e.post(tap: .cghidEventTap)
}

func move(to target: CGPoint, duration: Double) {
    let start = current()
    let steps = max(1, Int(duration * 120))
    // 略带弧线的缓入缓出，更像人手
    let mid = CGPoint(x: (start.x + target.x) / 2 + (target.y - start.y) * 0.08, y: (start.y + target.y) / 2 - (target.x - start.x) * 0.08)
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        let k = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        let a = CGPoint(x: start.x + (mid.x - start.x) * k, y: start.y + (mid.y - start.y) * k)
        let b = CGPoint(x: mid.x + (target.x - mid.x) * k, y: mid.y + (target.y - mid.y) * k)
        let p = CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
        post(.mouseMoved, p)
        usleep(useconds_t(duration / Double(steps) * 1_000_000))
    }
}

func click(_ p: CGPoint) {
    post(.leftMouseDown, p); usleep(70_000); post(.leftMouseUp, p)
}

let keyCodes: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
    "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
    "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
    ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50, "delete": 51, "esc": 53,
    "left": 123, "right": 124, "down": 125, "up": 126, "pagedown": 121, "pageup": 116,
]

func key(_ combo: String) {
    let parts = combo.lowercased().split(separator: "+").map(String.init)
    var flags: CGEventFlags = []
    for m in parts.dropLast() {
        switch m {
        case "cmd": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "alt", "opt": flags.insert(.maskAlternate)
        case "ctrl": flags.insert(.maskControl)
        default: break
        }
    }
    guard let code = keyCodes[parts.last!] else { fatalError("unknown key \(combo)") }
    let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
    let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)!
    down.flags = flags; up.flags = flags
    down.post(tap: .cghidEventTap); usleep(40_000); up.post(tap: .cghidEventTap)
}

func type(_ text: String, cps: Double) {
    for ch in text {
        var u = Array(String(ch).utf16)
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)!
        down.keyboardSetUnicodeString(stringLength: u.count, unicodeString: &u)
        up.keyboardSetUnicodeString(stringLength: u.count, unicodeString: &u)
        down.post(tap: .cghidEventTap); usleep(20_000); up.post(tap: .cghidEventTap)
        usleep(useconds_t(1_000_000 / cps * Double.random(in: 0.7...1.3)))
    }
}

func scroll(_ dy: Int32, steps: Int) {
    for _ in 0..<steps {
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: dy / Int32(steps), wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
        usleep(12_000)
    }
}

/// 查找：在应用里找文本包含 needle 的元素，返回最小的那个（优先可点击的）。
func find(appName: String, needle: String, role: String?, index: Int) -> CGRect? {
    guard let a = app(appName) else { return nil }
    var hits: [(CGRect, Bool)] = []
    walk(a) { e, _ in
        let r: String = attr(e, kAXRoleAttribute) ?? ""
        if let role, r != role { return true }
        let t = texts(e)
        if t.contains(where: { $0.contains(needle) }), let f = frame(e), f.width > 1, f.height > 1 {
            hits.append((f, t.contains(needle)))
        }
        return true
    }
    // 完全相等优先，其次靠左（侧栏）、靠上
    hits.sort { ($0.1 ? 0 : 1, $0.0.minX, $0.0.minY) < ($1.1 ? 0 : 1, $1.0.minX, $1.0.minY) }
    return index < hits.count ? hits[index].0 : nil
}

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { print("usage"); exit(1) }
func arg(_ i: Int) -> String { i < args.count ? args[i] : "" }
func num(_ i: Int, _ d: Double) -> Double { Double(arg(i)) ?? d }

switch cmd {
case "dump":
    guard let a = app(arg(1)) else { print("no app"); exit(1) }
    walk(a) { e, d in
        let r: String = attr(e, kAXRoleAttribute) ?? ""
        let t = texts(e).joined(separator: " | ")
        let f = frame(e).map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? ""
        print(String(repeating: "  ", count: d) + "\(r) [\(t.prefix(80))] \(f)")
        return true
    }
case "find":
    // find <app> <text> [role] [index]
    guard let f = find(appName: arg(1), needle: arg(2), role: arg(3).isEmpty || arg(3) == "-" ? nil : arg(3), index: Int(arg(4)) ?? 0) else { print("notfound"); exit(2) }
    print("\(f.minX) \(f.minY) \(f.width) \(f.height)")
case "goto":
    // goto <app> <text> [role] [index] [dur] [dx] [dy] —— 移动到元素中心（可偏移），不点击
    guard let f = find(appName: arg(1), needle: arg(2), role: arg(3).isEmpty || arg(3) == "-" ? nil : arg(3), index: Int(arg(4)) ?? 0) else { print("notfound \(arg(2))"); exit(2) }
    move(to: CGPoint(x: f.midX + num(6, 0), y: f.midY + num(7, 0)), duration: num(5, 0.7))
case "tap":
    // tap <app> <text> [role] [index] [dur] [dx] [dy] —— 移动过去并点击
    guard let f = find(appName: arg(1), needle: arg(2), role: arg(3).isEmpty || arg(3) == "-" ? nil : arg(3), index: Int(arg(4)) ?? 0) else { print("notfound \(arg(2))"); exit(2) }
    let p = CGPoint(x: f.midX + num(6, 0), y: f.midY + num(7, 0))
    move(to: p, duration: num(5, 0.7)); usleep(120_000); click(p)
case "move": move(to: CGPoint(x: num(1, 0), y: num(2, 0)), duration: num(3, 0.7))
case "warp": CGWarpMouseCursorPosition(CGPoint(x: num(1, 0), y: num(2, 0)))
case "click":
    if args.count >= 3 { let p = CGPoint(x: num(1, 0), y: num(2, 0)); move(to: p, duration: num(3, 0.7)); usleep(120_000); click(p) }
    else { click(current()) }
case "key": key(arg(1))
case "type": type(arg(1), cps: num(2, 9))
case "scroll": scroll(Int32(num(1, -300)), steps: Int(num(2, 30)))
case "where": print(current())
case "window":
    // window <app> → 主窗口 frame
    guard let a = app(arg(1)), let ws: [AXUIElement] = attr(a, kAXWindowsAttribute) else { exit(2) }
    for w in ws { if let f = frame(w) { print("\(f.minX) \(f.minY) \(f.width) \(f.height) \(attr(w, kAXTitleAttribute) as String? ?? "")") } }
case "setwindow":
    // setwindow <app> x y w h [title]
    guard let a = app(arg(1)), let ws: [AXUIElement] = attr(a, kAXWindowsAttribute) else { exit(2) }
    let w = ws.first { args.count < 7 || (attr($0, kAXTitleAttribute) as String? ?? "").contains(arg(6)) } ?? ws[0]
    var p = CGPoint(x: num(2, 0), y: num(3, 0)), s = CGSize(width: num(4, 1280), height: num(5, 800))
    AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
    AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!)
default: print("unknown"); exit(1)
}
