import CodedogCore
import SwiftUI

// MARK: - 文件夹轮廓

/// 后层：右上角凸起的标签页。
struct FolderBackShape: Shape {
    var radius: CGFloat = 18
    var tab: CGFloat = 26
    var tabStart: CGFloat = 0.52

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, r = radius, t = tab
        let x0 = w * tabStart, slope: CGFloat = 22
        var p = Path()
        p.move(to: CGPoint(x: 0, y: t + r))
        p.addQuadCurve(to: CGPoint(x: r, y: t), control: CGPoint(x: 0, y: t))
        p.addLine(to: CGPoint(x: x0 - slope, y: t))
        p.addCurve(to: CGPoint(x: x0, y: 0), control1: CGPoint(x: x0 - slope * 0.45, y: t), control2: CGPoint(x: x0 - slope * 0.55, y: 0))
        p.addLine(to: CGPoint(x: w - r, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h - r))
        p.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: r, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// 前层：左上角凸起的标签页。
struct FolderFrontShape: Shape {
    var radius: CGFloat = 18
    var tab: CGFloat = 22
    var tabEnd: CGFloat = 0.40

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, r = radius, t = tab
        let x1 = w * tabEnd, slope: CGFloat = 22
        var p = Path()
        p.move(to: CGPoint(x: 0, y: r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
        p.addLine(to: CGPoint(x: x1, y: 0))
        p.addCurve(to: CGPoint(x: x1 + slope, y: t), control1: CGPoint(x: x1 + slope * 0.55, y: 0), control2: CGPoint(x: x1 + slope * 0.45, y: t))
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

/// 玻璃拟态文件夹：后层渐变图 + 磨砂玻璃前层，左下名称与信息，右下项目类型徽章。
/// 悬停时前层后仰、露出里面的"纸张"（最近会话 / 提交）；点击时纸张扇形展开后打开项目面板。
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
    private var hovering: Bool { forcedState.map { $0 >= 1 } ?? hoveringState }
    private var opening: Bool { forcedState.map { $0 == 2 } ?? openingState }

    static let size = CGSize(width: 264, height: 214)
    private let frontHeight: CGFloat = 150

    var body: some View {
        ZStack(alignment: .bottom) {
            ProjectArt(project: item.project)
                .clipShape(FolderBackShape())
                .overlay(FolderBackShape().stroke(.white.opacity(0.18), lineWidth: 0.5))
                .frame(height: Self.size.height)

            papers
                .frame(height: Self.size.height, alignment: .top)

            front
                .frame(height: frontHeight)
                .rotation3DEffect(.degrees(opening ? -20 : hovering ? -14 : 0), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.55)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .compositingGroup()
        .shadow(color: .black.opacity(hovering ? 0.22 : 0.12), radius: hovering ? 18 : 10, y: hovering ? 12 : 6)
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: hovering)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: opening)
        .onHover { hoveringState = $0 }
        .task(id: item.project.htmlEntry) {
            if let entry = item.project.htmlEntry, Self.isHTMLProject(item.project), forcedState == nil {
                _ = await HTMLThumbnailer.shared.thumbnail(project: item.project.path, entry: entry)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { open() }
    }

    private func open() {
        openingState = true
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            onOpen()
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
        return kinds.prefix(3).enumerated().map { Paper(id: $0.offset, kind: $0.element) }
    }

    private var papers: some View {
        let items = paperItems
        return ZStack(alignment: .top) {
            ForEach(items.reversed()) { p in
                let t = paperTransform(index: p.id, count: items.count)
                paperView(p)
                    .frame(width: Self.size.width - 44 - CGFloat(p.id) * 8, height: 110)
                    .rotationEffect(.degrees(t.angle), anchor: .bottom)
                    .offset(x: t.x, y: t.y)
                    .opacity(hovering || opening ? 1 : 0)
            }
        }
        .padding(.top, 36)
    }

    /// 静止：纸张藏在前层后面；悬停：上探一截并微微散开；打开：扇形飞出。
    private func paperTransform(index: Int, count: Int) -> (angle: Double, x: CGFloat, y: CGFloat) {
        let i = Double(index)
        let fan = i - Double(count - 1) / 2
        if opening { return (fan * 7, CGFloat(fan) * 18, -62 + CGFloat(i) * 8) }
        if hovering { return (fan * 2.5, 0, -14 + CGFloat(i) * 6) }
        return (0, 0, 60 + CGFloat(i) * 4)   // 完全藏在前层后面
    }

    private func paperView(_ p: Paper) -> some View {
        PaperView(kind: p.kind, project: item.project.path, active: hovering || opening)
    }

    // MARK: 前层玻璃

    private var front: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(item.project.name)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        if item.meta.favorite {
                            Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow)
                        }
                    }
                    subtitle
                }
                Spacer(minLength: 0)
                StackBadge(project: item.project, size: 36)   // 项目类型放在右下角
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background {
            FolderFrontShape()
                .fill(.ultraThinMaterial)
                .overlay(FolderFrontShape().fill(scheme == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.42)))
        }
        .overlay {
            FolderFrontShape()
                .stroke(
                    LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.35 : 0.9), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.8)
        }
        .overlay {
            if isSelected { FolderFrontShape().stroke(Color.brand, lineWidth: 2) }
        }
    }

    @ViewBuilder private var subtitle: some View {
        HStack(spacing: 5) {
            if !item.running.isEmpty {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("运行中")
            } else if item.waiting {
                Circle().fill(.orange).frame(width: 6, height: 6)
                Text("等你回复")
            } else if let reason = match.reasons.first, !reason.hasPrefix("名称") {
                Text(reason)
            } else {
                Text([item.size.map { Formatting.bytes($0.total) }, item.project.git?.branch].compactMap { $0 }.joined(separator: " · "))
            }
            if let dirty = item.project.git?.dirtyFiles, dirty > 0, item.running.isEmpty, !item.waiting {
                Text("· \(dirty) 未提交").foregroundStyle(.pink)
            }
        }
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)
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

    private var paperColor: Color { scheme == .dark ? Color(white: 0.2) : .white }

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
                header(title: Formatting.plain(s.title ?? s.lastPrompt ?? "会话"), trailing: s.lastAt.map { Formatting.relative($0) } ?? "")
                HStack(spacing: 4) {
                    Circle().fill(.orange).frame(width: 5, height: 5)
                    Text("等你回复").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(.orange)
                }
                Text(Formatting.plain(s.lastReply ?? "AI 已经答完，等你回复。"))
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
        case .modified: "已修改"
        case .added: "新增"
        case .untracked: "新文件"
        case .renamed: "已重命名"
        case .deleted: "已删除"
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
