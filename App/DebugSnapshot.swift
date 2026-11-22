#if DEBUG
import AppKit
import CodedogCore
import SwiftUI

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
                case "noroots": model.debugNoRoots = arg != "off"
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
                case "spage": NotificationCenter.default.post(name: .debugSettingsPage, object: arg)
                case "sshot": captureSettings(to: "\(prefix)-\(arg).png")
                case "launcher": AppDelegate.shared.launcher.show()
                case "lquery": AppDelegate.shared.launcher.state.query = arg
                case "ldown": AppDelegate.shared.launcher.state.selection += Int(arg) ?? 1
                case "lright": AppDelegate.shared.launcher.state.action += Int(arg) ?? 1
                case "smart": if let f = SmartFolder(rawValue: arg) { model.selection = .smart(f) }
                case "sizes": print("[sizes] measured=\(model.sizes.count) measuring=\(model.isMeasuring) total=\(model.sizes.values.map(\.total).reduce(0, +)) reclaimable=\(model.sizes.values.map(\.reclaimable).reduce(0, +))")
                case "newproject": NotificationCenter.default.post(name: .debugSheet, object: "new")
                case "cleanup": NotificationCenter.default.post(name: .debugSheet, object: "cleanup")
                case "icons":
                    for dark in [false, true] {
                        let view = IconGallery().environment(\.colorScheme, dark ? .dark : .light)
                        let r = ImageRenderer(content: view)
                        r.scale = 2
                        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: "\(prefix)-icons-\(dark ? "dark" : "light").png"))
                        }
                    }
                case "cards":
                    // 挑不同类型：等你回复、HTML、未提交改动、有备注
                    let all = model.items.filter { !$0.meta.hidden }
                    var picks: [ProjectItem] = []
                    func add(_ p: ProjectItem?) { if let p, !picks.contains(where: { $0.id == p.id }) { picks.append(p) } }
                    add(all.first { $0.waiting })
                    add(all.first { $0.project.htmlEntry != nil && ($0.project.kind == .web || $0.project.stacks.first == .html) && $0.project.stacks.first == .html })
                    add(all.first { $0.project.htmlEntry != nil && $0.project.kind == .web })
                    add(all.first { ($0.project.git?.dirtyFiles ?? 0) > 0 && !$0.waiting })
                    add(all.first { !$0.meta.notes.isEmpty })
                    if let demo = ProcessInfo.processInfo.environment["CODEDOG_HTML_DEMO"], let p = await DiscoveryService.inspect(path: demo) {
                        picks.insert(ProjectItem(project: p, meta: ProjectMeta(), categoryNames: []), at: 0)
                    }
                    for p in picks {
                        if let e = p.project.htmlEntry { _ = await HTMLThumbnailer.shared.thumbnail(project: p.id, entry: e) }
                        for f in p.project.recentFiles { _ = await FilePreviews.shared.load(p.id + "/" + f.path) }
                    }
                    print("[cards]", picks.map { "\($0.project.name) html=\($0.project.htmlEntry ?? "-") files=\($0.project.recentFiles.map(\.path)) note=\(!$0.meta.notes.isEmpty)" })
                    for dark in [false, true] {
                        let view = CardStates(items: picks).environment(model).environment(\.colorScheme, dark ? .dark : .light)
                        let r = ImageRenderer(content: view)
                        r.scale = 2
                        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: "\(prefix)-cards-\(dark ? "dark" : "light").png"))
                        }
                    }
                case "zoom": model.zoomCards(Int(arg) ?? 0)
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

    static func captureSettings(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.identifier?.rawValue.contains("Settings") == true }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
    }

    static func capture(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.title == "codedog" }) ?? NSApp.windows.first(where: \.isVisible),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
    }
}
/// 调试：卡片三种状态（静止 / 悬停 / 打开）。
struct CardStates: View {
    var items: [ProjectItem]
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 40) {
                    ForEach(0..<3, id: \.self) { s in
                        ProjectCard(item: item, match: .none, isSelected: false, forcedState: s)
                    }
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 90)
        .padding(.bottom, 30)
        .background(BackdropView())
    }
}

/// 调试：全部技术栈图标一览。
struct IconGallery: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let fws = Framework.allCases.map { (StackIcon.framework($0), $0.displayName) }
        let langs = TechStack.allCases.map { (StackIcon.language($0), $0.displayName) }
        VStack(alignment: .leading, spacing: 14) {
            Text("AI 助手与编辑器").font(.headline)
            HStack(spacing: 22) {
                ForEach(AITool.allCases, id: \.self) { t in
                    VStack(spacing: 6) {
                        HStack(spacing: 10) { ToolIcon(tool: t, size: 16); ToolIcon(tool: t, size: 28) }
                        Text(t.displayName).font(.caption2)
                    }
                }
            }
            ForEach([("语言", langs), ("框架", fws)], id: \.0) { title, items in
                Text(title).font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(84)), count: 9), spacing: 12) {
                    ForEach(items, id: \.1) { icon, name in
                        VStack(spacing: 6) {
                            BadgePreview(icon: icon)
                            Text(name).font(.caption2).lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(scheme == .dark ? Color(white: 0.1) : Color(white: 0.96))
    }
}

private struct BadgePreview: View {
    var icon: StackIcon
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let fill = scheme == .dark && icon.brand.relativeLuminance < 0.02 ? Color(white: 0.16) : icon.brand
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LinearGradient(colors: [fill.mix(with: .white, by: 0.12), fill], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { Image(icon.asset).renderingMode(.template).resizable().scaledToFit().foregroundStyle(icon.glyph).padding(9) }
            .frame(width: 40, height: 40)
    }
}
#endif
