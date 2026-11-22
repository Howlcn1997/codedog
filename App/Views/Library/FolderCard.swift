import CodedogCore
import SwiftUI

// MARK: - 文件夹轮廓

/// 后片：左上角凸起一截标签，右侧低一级。
struct FolderBackShape: Shape {
    var tab: CGFloat = 24
    var tabEnd: CGFloat = 0.40
    var radius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, t = tab, r = radius
        let x1 = w * tabEnd, slope: CGFloat = 24
        var p = Path()
        p.move(to: CGPoint(x: 0, y: r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
        p.addLine(to: CGPoint(x: x1, y: 0))
        p.addCurve(to: CGPoint(x: x1 + slope, y: t), control1: CGPoint(x: x1 + slope * 0.5, y: 0), control2: CGPoint(x: x1 + slope * 0.5, y: t))
        p.addLine(to: CGPoint(x: w - r, y: t))
        p.addQuadCurve(to: CGPoint(x: w, y: t + r), control: CGPoint(x: w, y: t))
        p.addLine(to: CGPoint(x: w, y: h - r))
        p.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: r, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// 前片口袋：圆角梯形，上沿略宽于底边，像一只微微张口的口袋。
struct FolderPocketShape: Shape {
    var topRadius: CGFloat = 22
    var bottomRadius: CGFloat = 26
    /// 底边每侧比上沿收进去多少
    var taper: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, r = topRadius, R = bottomRadius, k = taper
        func x(_ y: CGFloat) -> CGFloat { k * y / h }   // 左边在 y 处的横坐标
        var p = Path()
        p.move(to: CGPoint(x: x(r), y: r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
        p.addLine(to: CGPoint(x: w - r, y: 0))
        p.addQuadCurve(to: CGPoint(x: w - x(r), y: r), control: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w - x(h - R), y: h - R))
        p.addQuadCurve(to: CGPoint(x: w - k - R, y: h), control: CGPoint(x: w - k, y: h))
        p.addLine(to: CGPoint(x: k + R, y: h))
        p.addQuadCurve(to: CGPoint(x: x(h - R), y: h - R), control: CGPoint(x: k, y: h))
        p.closeSubpath()
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// 边缘向内泛白的弧面感：模糊过的白色内描边。所有卡片的形状和尺寸都一样，只渲染一次成位图共用，滚动时直接贴图。
struct EdgeGlow<S: Shape>: View {
    var shape: S
    var size: CGSize
    var strength: Double = 1
    /// 泛光向内渗进去的宽度比例（1 为默认，越小越贴边）
    var spread: CGFloat = 1

    @MainActor private static var cache: [String: NSImage] { get { glowCache } set { glowCache = newValue } }

    var body: some View {
        Image(nsImage: Self.image(shape, size, spread: spread))
            .resizable()
            .frame(width: size.width, height: size.height)
            .opacity(strength)
            .allowsHitTesting(false)
    }

    @MainActor static func image(_ shape: S, _ size: CGSize, spread: CGFloat = 1) -> NSImage {
        let key = "\(S.self)|\(size.width)x\(size.height)|\(spread)"
        if let img = cache[key] { return img }
        let r = ImageRenderer(content:
            ZStack {
                shape.stroke(.white.opacity(0.6), lineWidth: 11 * spread).blur(radius: 5 * spread)
                shape.stroke(.white.opacity(0.35), lineWidth: 3).blur(radius: 1.2)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape))
        r.scale = 2
        let img = r.nsImage ?? NSImage()
        cache[key] = img
        return img
    }
}

@MainActor private var glowCache: [String: NSImage] = [:]

// MARK: - 每个项目专属的抽象渐变

/// 以技术栈品牌色为主色、项目路径为种子生成的网格渐变，同一项目每次都一样。
struct ProjectArt: View {
    var project: DiscoveredProject

    var body: some View {
        MeshGradient(width: 3, height: 3, points: Self.points(Self.seed(project.path)), colors: colors, smoothsColors: true)
    }

    private var colors: [Color] {
        let seed = Self.seed(project.path)
        let base = StackIcon.of(project)?.brand ?? .brand
        let accent = Self.palette[Int(seed % UInt64(Self.palette.count))]
        let deep = base.mix(with: .black, by: 0.55)
        let light = base.mix(with: .white, by: 0.55)
        return [
            deep, base, light,
            accent, base.mix(with: accent, by: 0.5), deep,
            light, accent.mix(with: .black, by: 0.35), base,
        ]
    }

    private static func points(_ seed: UInt64) -> [SIMD2<Float>] {
        func j(_ k: UInt64) -> Float { Float((seed >> k) & 0xFF) / 255 * 0.3 - 0.15 }
        return [
            [0, 0], [0.5 + j(8), 0], [1, 0],
            [0, 0.5 + j(16)], [0.5 + j(24), 0.5 + j(32)], [1, 0.5 + j(40)],
            [0, 1], [0.5 + j(48), 1], [1, 1],
        ]
    }

    static let palette: [Color] = [.orange, .pink, .purple, .indigo, .teal, .mint, .yellow, .red, .cyan, .blue]

    /// FNV-1a，跨启动稳定（String.hashValue 每次启动都不同）。
    static func seed(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }
}

// MARK: - 项目卡片

/// 文件夹：浅色后片（带标签）+ 口袋里几张白纸 + 前片口袋。默认灰色，可在右键菜单里选颜色；前片上用深一号的同色字写名称和信息，右下角是技术栈图标。
/// 悬停时纸张从口袋里升起散开，前片以底边为轴向前倒下；点击时纸张再飞高一些，然后打开项目面板。
struct ProjectCard: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var item: ProjectItem
    var match: SearchMatch
    var isSelected: Bool
    var onOpen: () -> Void = {}
    /// 调试预览用：强制显示某个状态（0 静止，1 悬停，2 打开）
    var forcedState: Int? = nil

    @State private var hoveringState = false
    @State private var openingState = false
    @State private var papersMounted = false
    @State private var lastHover = false
    private var hovering: Bool { forcedState.map { $0 >= 1 } ?? hoveringState }
    private var opening: Bool { forcedState.map { $0 == 2 } ?? openingState }

    static let size = CGSize(width: 214, height: 226)
    private let frontHeight: CGFloat = 166
    private let backInset: CGFloat = 12
    private let paperSize = CGSize(width: 162, height: 140)

    /// 整张卡是按 cardScale 等比缩放的，缩小后名称和徽章会显得太小；这里给前层文字和图标反向补一点（只补缩小的部分，开方让补偿温和些）
    private var labelBoost: CGFloat { model.cardScale < 1 ? 1 / sqrt(model.cardScale) : 1 }

    /// 文件夹配色：默认灰色，用户在右键菜单里选过颜色就用那个颜色的浅色调。
    private var style: FolderPalette.Style { FolderPalette.style(item.meta.color, dark: scheme == .dark) }

    var body: some View {
        let style = style
        ZStack(alignment: .top) {
            // 后片：同色浅一些，左上角带标签
            FolderBackShape()
                .fill(style.back)
                .overlay(EdgeGlow(shape: FolderBackShape(), size: CGSize(width: Self.size.width - backInset * 2, height: Self.size.height - 16), strength: scheme == .dark ? 0.34 : 0.3, spread: scheme == .dark ? 0.5 : 1))
                .overlay(FolderBackShape().stroke(style.edge, lineWidth: 1))
                .frame(width: Self.size.width - backInset * 2, height: Self.size.height - 16)
                .padding(.top, 14)

            papers
                .frame(height: Self.size.height, alignment: .top)

            // 悬停时浮在升起的纸上：开始创作
            if papersMounted || forcedState != nil {
                resumeButton
                    .padding(.top, 16)
                    .offset(y: hovering ? 0 : 30)
                    .scaleEffect(hovering && !opening ? 1 : 0.85)
                    .opacity(hovering && !opening ? 1 : 0)
                    .allowsHitTesting(hovering && !opening)
            }

            front(style)
                .frame(height: frontHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
                // 以底边为轴向前倒下：底边不动，上沿靠近、透视变宽并下移
                .rotation3DEffect(.degrees(opening ? -30 : hovering ? -26 : 0), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .animation(.spring(response: 0.34, dampingFraction: 0.74), value: hovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: opening)
        .onHover { h in
            lastHover = h
            if h && !papersMounted {
                // 先把带内容的纸以静止状态换进来，下一帧再进入悬停，才有升起的动画
                papersMounted = true
                DispatchQueue.main.async { hoveringState = lastHover }
            } else {
                hoveringState = h
            }
        }
        .task(id: item.project.htmlEntry) {
            if let entry = item.project.htmlEntry, Self.isHTMLProject(item.project), forcedState == nil {
                _ = await HTMLThumbnailer.shared.thumbnail(project: item.project.path, entry: entry)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { open() }
    }

    /// 立刻打开详情，纸张飞出的动画同时播放（不再先等动画播完）。
    private func open() {
        openingState = true
        onOpen()
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            openingState = false
        }
    }

    // MARK: 纸张

    /// 纸张内容，按优先级挑选最多 3 张：等你回复的会话 → HTML 预览 → 便签 → 最近在改的文件 → README。
    enum PaperKind: Hashable {
        case session(SessionSummary)
        case html(entry: String)
        case note(String)
        case file(FileRef)
        case readme(String)
        /// 什么内容都没有时的空白纸，写上项目简介
        case blank(String?)
    }

    /// 纯 HTML 项目：主技术栈是 HTML（没有 package.json 等构建工具，index.html 本身就是页面）。
    static func isHTMLProject(_ p: DiscoveredProject) -> Bool {
        p.stacks.first == .html && p.htmlEntry != nil
    }

    private struct Paper: Identifiable {
        var id: Int
        var kind: PaperKind
    }

    private var paperItems: [Paper] {
        var kinds: [PaperKind] = []
        if item.waiting, let s = item.tools.flatMap(\.recentSessions).filter(\.waiting).max(by: { ($0.lastAt ?? .distantPast) < ($1.lastAt ?? .distantPast) }) {
            kinds.append(.session(s))
        }
        if Self.isHTMLProject(item.project), let entry = item.project.htmlEntry {
            kinds.append(.html(entry: entry))
        }
        let note = item.meta.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { kinds.append(.note(note)) }
        for f in item.project.recentFiles where kinds.count < 3 { kinds.append(.file(f)) }
        if kinds.isEmpty, let readme = item.project.readmeFile { kinds.append(.readme(readme)) }
        if kinds.isEmpty { kinds.append(.blank(item.project.description)) }
        return kinds.prefix(3).enumerated().map { Paper(id: $0.offset, kind: $0.element) }
    }

    /// 静止时是两张空白纸，只露出上沿一小截；第一次悬停时才换成带内容的纸（几十张卡都画内容，滚动会卡）。
    private var papers: some View {
        let items: [Paper] = papersMounted || forcedState != nil
            ? paperItems
            : [Paper(id: 0, kind: .blank(nil)), Paper(id: 1, kind: .blank(nil))]
        let count = max(items.count, 2)
        return ZStack(alignment: .top) {
            ForEach(items.reversed()) { p in
                let t = paperTransform(index: p.id, count: count)
                Group {
                    if case .blank(nil) = p.kind, !(papersMounted || forcedState != nil) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PaperView.paperColor(scheme))
                            .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                    } else {
                        PaperView(kind: p.kind, project: item.project.path, active: true)
                    }
                }
                .frame(width: paperSize.width - CGFloat(p.id) * 6, height: paperSize.height)
                .opacity(p.id == 0 ? 1 : 0.92)
                .rotationEffect(.degrees(t.angle), anchor: .bottom)
                .offset(x: t.x, y: t.y)
            }
        }
        .padding(.top, 44)
    }

    /// 静止：叠在口袋里，只露出上沿；悬停：升起，前面一张略向左歪、后面的向右散开；打开：再飞高一些。
    private func paperTransform(index: Int, count: Int) -> (angle: Double, x: CGFloat, y: CGFloat) {
        let i = CGFloat(index)
        if opening { return ([-6, 12, -16][min(index, 2)], [0, 22, -20][min(index, 2)], -64 - i * 2) }
        if hovering { return ([-4, 9, -12][min(index, 2)], [0, 16, -14][min(index, 2)], -48 - i * 4) }
        return (index == 0 ? 0 : 1.5, i * 3, i * -4)
    }

    // MARK: 开始创作

    /// 黑色胶囊"开始创作"：用这个项目最近用过的 AI 工具接着上次的会话；没用过 AI 就用编辑器打开。
    /// 右键可以挑 AI 工具或编辑器。
    private var resumeButton: some View {
        let tool = item.lastAgent?.tool
        return Button {
            model.open(item, tool.map { .resume($0) } ?? .editor(nil))
        } label: {
            HStack(spacing: 6) {
                // 左边放会被打开的那个工具的标志：Claude Code / Codex；没用过 AI 就是编辑器的图标
                if let tool {
                    ToolIcon(tool: tool, size: 14 * labelBoost)
                } else if let editor = model.editor(for: item) {
                    Image(nsImage: AppIconView.icon(editor)).resizable().frame(width: 16 * labelBoost, height: 16 * labelBoost)
                } else {
                    Image(systemName: "play.fill").font(.system(size: 10 * labelBoost))
                }
                Text("开始创作")
            }
            .font(.system(size: 13 * labelBoost, weight: .semibold))
        }
        .buttonStyle(ResumePillStyle())
        .help(tool.map { model.resumeHelp(item, tool: $0) } ?? String(localized: "在编辑器中打开"))
        .contextMenu { resumeMenu }
    }

    @ViewBuilder private var resumeMenu: some View {
        OpenWithSections(item: item)
    }

    // MARK: 前片口袋

    private func front(_ style: FolderPalette.Style) -> some View {
        let shape = FolderPocketShape()
        return VStack(alignment: .leading, spacing: 0) {
            blurb.padding(.bottom, 4)
            HStack(spacing: 6) {
                Text(item.project.name)
                    .font(.system(size: 18 * labelBoost, weight: .semibold))
                    .lineLimit(1)
                if item.meta.favorite {
                    Image(systemName: "star.fill").font(.system(size: 11 * labelBoost)).foregroundStyle(.yellow)
                }
            }
            meta.padding(.top, 3)
            Spacer(minLength: 6)
            HStack(alignment: .bottom) {
                status
                Spacer(minLength: 6)
                stackGlyph
            }
        }
        .foregroundStyle(style.text)
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            // 透明度来自设置（默认 0 不透明）；调高后口袋里的纸能透出轮廓。
            // 不用系统毛玻璃：它模糊太重，会把纸糊成一片，看不出形状
            shape.fill(LinearGradient(colors: [style.front.mix(with: .white, by: 0.08), style.front], startPoint: .top, endPoint: .bottom))
                .opacity(1 - min(model.library.preferences.folderTransparency, 0.3))
                // 投影直接挂在半透明的前片上（垫一块实心色块投影会从半透明的前片里透出来）
                .shadow(color: style.shadow, radius: hovering ? 12 : 8, y: hovering ? 8 : 5)
                // 边缘一圈向内泛白，像鼓起来的软垫
                .overlay(EdgeGlow(shape: shape, size: CGSize(width: Self.size.width, height: frontHeight), strength: scheme == .dark ? 0.28 : 0.25, spread: scheme == .dark ? 0.5 : 1))
                .overlay(shape.stroke(style.edge, lineWidth: 1))
        }
    }

    /// 上半部只在搜索时显示命中原因；平时留空，不显示项目描述。
    @ViewBuilder private var blurb: some View {
        if let reason = match.reasons.first, !reason.hasPrefix(String(localized: "名称")) {
            Label(reason, systemImage: "magnifyingglass")
                .font(.system(size: 11 * labelBoost, weight: .medium))
                .opacity(0.85)
                .lineLimit(2)
        }
    }

    /// 固定格式：最近活跃 · 未提交数。
    private var meta: some View {
        let dirty = item.project.git?.dirtyFiles ?? 0
        var parts: [String] = []
        if let at = item.project.lastActivity { parts.append(Formatting.relative(at)) }
        if dirty > 0 { parts.append(String(localized: "\(dirty) 未提交")) }
        return Text(parts.joined(separator: " · "))
            .font(.system(size: 11.5 * labelBoost).monospacedDigit())
            .opacity(0.7)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// 左下角：运行中 / 等你回复；没有状态时写项目类型。
    @ViewBuilder private var status: some View {
        HStack(spacing: 5) {
            if !item.running.isEmpty {
                Circle().fill(Color(hex: 0x34C759)).frame(width: 6, height: 6)
                Text("运行中")
            } else if item.waiting {
                Circle().fill(Color(hex: 0xFF9F0A)).frame(width: 6, height: 6)
                Text("等你回复")
            } else {
                Text(item.project.kind.displayName).opacity(0.75)
            }
        }
        .font(.system(size: 12 * labelBoost, weight: .medium))
        .opacity(0.9)
        .lineLimit(1)
    }

    /// 右下角：同色技术栈图标。
    @ViewBuilder private var stackGlyph: some View {
        let size = 20 * labelBoost
        if let icon = StackIcon.of(item.project) {
            Image(icon.asset).renderingMode(.template).resizable().scaledToFit()
                .frame(width: size, height: size)
                .opacity(0.6)
                .help(icon.label)
        } else {
            Image(systemName: item.project.kind.symbol).font(.system(size: size * 0.8, weight: .semibold))
        }
    }
}

// MARK: - 开始创作按钮样式

/// 黑色胶囊按钮：悬停时放大、提亮、投影加深，并显示手形指针；按下时缩一下。
private struct ResumePillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration)
    }

    private struct Pill: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(hovering ? Color(white: 0.2) : Color.black.opacity(0.9)))
                .overlay(Capsule().strokeBorder(.white.opacity(hovering ? 0.22 : 0), lineWidth: 0.8))
                .shadow(color: .black.opacity(hovering ? 0.38 : 0.25), radius: hovering ? 9 : 5, y: hovering ? 4 : 2)
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.96 : hovering ? 1.06 : 1)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: hovering)
                .animation(.spring(response: 0.16, dampingFraction: 0.75), value: configuration.isPressed)
                .onHover { hovering = $0 }
                .pointerStyle(.link)
        }
    }
}

// MARK: - 纸张

/// 单张纸：不同内容用不同样式。预览内容只在纸张露出（悬停 / 打开）时加载。
struct PaperView: View {
    var kind: ProjectCard.PaperKind
    var project: String
    var active: Bool
    @Environment(\.colorScheme) private var scheme
    @State private var lines: [String]?
    @State private var thumbnail: NSImage?

    /// 纸张底色：占位纸和带内容的纸共用，暗色下是深灰
    static func paperColor(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(white: 0.2) : .white }
    private var paperColor: Color { Self.paperColor(scheme) }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
            .task(id: active) { if active { await loadPreview() } }
            .onAppear {
                // 先用已缓存的内容，避免每次悬停都闪一下占位
                switch kind {
                case .html(let entry): thumbnail = HTMLThumbnailer.shared.cached(project: project, entry: entry)
                case .file(let f): lines = FilePreviews.shared.lines(project + "/" + f.path)
                case .readme(let name): lines = FilePreviews.shared.lines(project + "/" + name)
                default: break
                }
            }
    }

    private var background: Color {
        if case .note = kind { return scheme == .dark ? Color(red: 0.36, green: 0.32, blue: 0.14) : Color(red: 1, green: 0.95, blue: 0.68) }
        return paperColor
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .session(let s):
            VStack(alignment: .leading, spacing: 5) {
                header(title: Formatting.plain(s.title ?? s.lastPrompt ?? String(localized: "会话")), trailing: s.lastAt.map { Formatting.relative($0) } ?? "")
                HStack(spacing: 4) {
                    Circle().fill(.orange).frame(width: 5, height: 5)
                    Text("等你回复").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(.orange)
                }
                Text(Formatting.plain(s.lastReply ?? String(localized: "AI 已经答完，等你回复。")))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                Spacer(minLength: 0)
            }
            .padding(10)

        case .html(let entry):
            ZStack(alignment: .bottomLeading) {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipped()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "safari").font(.system(size: 20)).foregroundStyle(.tertiary)
                        if active { ProgressView().controlSize(.mini) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.04))
                }
                Text(entry)
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(6)
            }

        case .note(let text):
            VStack(alignment: .leading, spacing: 5) {
                Label("便签", systemImage: "note.text").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(.secondary)
                Text(text)
                    .font(.system(size: 10.5, design: .rounded))
                    .lineLimit(5)
                Spacer(minLength: 0)
            }
            .padding(10)

        case .file(let f):
            VStack(alignment: .leading, spacing: 3) {
                header(title: f.name, trailing: statusText(f))
                if !f.directory.isEmpty {
                    Text(f.directory).font(.system(size: 8, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                }
                codeLines.padding(.top, 2)
                Spacer(minLength: 0)
            }
            .padding(10)

        case .readme(let name):
            VStack(alignment: .leading, spacing: 4) {
                header(title: name, trailing: "")
                codeLines
                Spacer(minLength: 0)
            }
            .padding(10)

        case .blank(let text):
            VStack(alignment: .leading, spacing: 4) {
                if let text, !text.isEmpty {
                    Text(Formatting.plain(text)).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(5)
                } else {
                    codeLines
                }
                Spacer(minLength: 0)
            }
            .padding(10)
        }
    }

    private func header(title: String, trailing: String) -> some View {
        HStack(spacing: 5) {
            Text(title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 4)
            Text(trailing).font(.system(size: 8.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    /// 代码预览；未加载时用占位条。
    @ViewBuilder private var codeLines: some View {
        if let lines, !lines.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.prefix(7).enumerated()), id: \.offset) { _, l in
                    Text(l.isEmpty ? " " : l).font(.system(size: 7.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<3, id: \.self) { k in
                    Capsule().fill(Color.primary.opacity(0.08)).frame(height: 4).padding(.trailing, CGFloat(k) * 28)
                }
            }
        }
    }

    private func statusText(_ f: FileRef) -> String {
        switch f.status {
        case .modified: String(localized: "已修改")
        case .added: String(localized: "新增")
        case .untracked: String(localized: "新文件")
        case .renamed: String(localized: "已重命名")
        case .deleted: String(localized: "已删除")
        case .committed, .recent: f.modifiedAt.map { Formatting.relative($0) } ?? ""
        }
    }

    private func loadPreview() async {
        switch kind {
        case .file(let f): if lines == nil { lines = await FilePreviews.shared.load(project + "/" + f.path) }
        case .readme(let name): if lines == nil { lines = await FilePreviews.shared.load(project + "/" + name) }
        case .html(let entry): if thumbnail == nil { thumbnail = await HTMLThumbnailer.shared.thumbnail(project: project, entry: entry) }
        default: break
        }
    }
}
