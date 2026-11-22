import AppKit
import SwiftUI

// 设置窗口专用的一套控件：比系统控件更圆、更柔和，统一用弹簧动效。
// 视觉参考 BlackBowl（NiceNotch）的设置中心。

private let controlSpring = Animation.spring(duration: 0.32, bounce: 0.35)

/// 毛玻璃配色：半透明窗口与侧栏材质，上面叠磨砂卡片。
enum SettingsPalette {
    /// 透出壁纸色调的磨砂卡片。
    static let card = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.62, darkAlpha: 0.06)
    static let selection = Color.primary.opacity(0.09)
    /// 控件内的凸起面：分段滑块、键帽。
    static let thumb = dynamic(light: 0xFFFFFF, dark: 0x636366)
    static let hairline = Color.primary.opacity(0.08)
    static let separator = Color.primary.opacity(0.07)

    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                           blue: CGFloat(hex & 0xff) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

/// SwiftUI 内容下方的 AppKit 材质，与窗口背后的桌面混合。
struct GlassMaterial: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

/// 把 SwiftUI Settings 场景的窗口改成一整块透明表面：侧栏延伸到红绿灯下方，无标题栏。
struct SettingsWindowStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { StylerView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class StylerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = true
            // 空的 unified 工具栏只让透明标题栏变高，红绿灯正好落进悬浮侧栏里。
            if window.toolbar == nil {
                let toolbar = NSToolbar(identifier: "codedog.settings")
                toolbar.showsBaselineSeparator = false
                window.toolbar = toolbar
            }
            window.toolbarStyle = .unified
        }
    }
}

// MARK: - 布局

/// 一组设置：小号灰色标题、白色卡片、可选脚注。
struct SettingsSection<Content: View, Accessory: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footer: String? = nil,
         @ViewBuilder accessory: () -> Accessory = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                HStack {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    accessory
                }
                .padding(.horizontal, 4)
            }
            _VariadicView.Tree(SeparatedRows()) { content }
                .background(SettingsPalette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(SettingsPalette.hairline, lineWidth: 0.5))
            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.bottom, 16)
    }
}

/// 行与行之间画缩进的细线。
private struct SeparatedRows: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        VStack(spacing: 0) {
            ForEach(children) { child in
                if child.id != children.first?.id {
                    Rectangle().fill(SettingsPalette.separator).frame(height: 0.5).padding(.leading, 12)
                }
                child
            }
        }
    }
}

/// 一行：可选图标、标题与副标题、右侧控件。
struct SettingsRow<Icon: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var subtitleTone: Color = .secondary
    @ViewBuilder var icon: Icon
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, subtitleTone: Color = .secondary,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }, @ViewBuilder icon: () -> Icon = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.subtitleTone = subtitleTone
        self.icon = icon()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    // 永远一行，保持行高一致；完整内容放在悬停提示里。
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(subtitleTone)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(subtitle)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: 40)
    }
}

/// 品牌色线条图标，固定宽度保证文字对齐。
struct SettingsGlyph: View {
    let symbol: String
    var size: CGFloat = 16
    var filled = false
    var tint: Color = .brand

    var body: some View {
        Image(systemName: symbol)
            .symbolVariant(filled ? .fill : .none)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }
}

/// 圆点 + 简短状态，例如 已安装 / 未安装。
struct SettingsStatus: View {
    enum Tone { case good, attention, neutral }
    let text: String
    let tone: Tone

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch tone {
        case .good: .green
        case .attention: .orange
        case .neutral: Color(nsColor: .tertiaryLabelColor)
        }
    }
}

// MARK: - 控件

/// 胶囊开关：按住时滑块拉长，松手弹到另一侧。
struct SettingsSwitch: View {
    let label: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var enabled
    @State private var pressed = false

    init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        _isOn = isOn
    }

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.brand : Color.primary.opacity(0.12))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(isOn ? 0 : 0.05), lineWidth: 0.5))
            Capsule()
                .fill(.white)
                .shadow(color: .black.opacity(0.18), radius: 2.5, y: 1)
                .frame(width: pressed ? 24 : 18, height: 18)
                .padding(2)
        }
        .frame(width: 40, height: 22)
        .opacity(enabled ? 1 : 0.45)
        .contentShape(Capsule())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if enabled, !pressed { withAnimation(controlSpring) { pressed = true } } }
            .onEnded { _ in
                guard enabled else { return }
                withAnimation(controlSpring) { pressed = false; isOn.toggle() }
            })
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "开" : "关")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if enabled { withAnimation(controlSpring) { isOn.toggle() } } }
    }
}

/// 紧凑选择器：当前值放在柔和胶囊里，点开弹出选项列表。
struct SettingsChoice<Value: Hashable, Label: View>: View {
    struct Option {
        var value: Value
        var title: String
        var icon: NSImage?
    }

    let title: String
    let options: [Option]
    @Binding var selection: Value
    /// 列表底部的附加动作，例如「其他…」。
    var extra: (title: String, action: () -> Void)?
    @ViewBuilder var label: Label
    @State private var open = false
    @State private var hovered = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                label
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 10).padding(.trailing, 8)
            .frame(height: 26)
            .background(Capsule().fill(Color.primary.opacity(hovered || open ? 0.1 : 0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(SettingsPressStyle())
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(options.indices, id: \.self) { i in
                    let option = options[i]
                    ChoiceRow(text: option.title, icon: option.icon, selected: option.value == selection) {
                        selection = option.value
                        open = false
                    }
                }
                if let extra {
                    Divider().padding(.vertical, 3).padding(.horizontal, 6)
                    ChoiceRow(text: extra.title, icon: nil, selected: false) {
                        open = false
                        extra.action()
                    }
                }
            }
            .padding(6)
            .frame(minWidth: 200)
        }
    }
}

private struct ChoiceRow: View {
    let text: String
    let icon: NSImage?
    let selected: Bool
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(selected ? 1 : 0)
                    .frame(width: 12)
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text(text)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .foregroundStyle(hovered ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovered ? Color.brand : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// 键帽样式的按键，例如 ⇧ ⌘ Space。
struct SettingsKeycaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .frame(minWidth: 18, minHeight: 18)
                    .padding(.horizontal, 3)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(SettingsPalette.thumb)
                        .shadow(color: .black.opacity(0.12), radius: 0, y: 1))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined())
    }
}

/// 胶囊按钮：一行只有一个主要动作时用 prominent，其余用 quiet。
struct SettingsButton: View {
    enum Kind { case prominent, quiet, destructive }
    let title: String
    var kind: Kind = .quiet
    var action: () -> Void
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled

    init(_ title: String, kind: Kind = .quiet, action: @escaping () -> Void) {
        self.title = title
        self.kind = kind
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(kind == .quiet ? Color.primary : Color.white)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
        }
        .buttonStyle(SettingsPressStyle())
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovered = $0 }
    }

    private var fill: Color {
        switch kind {
        case .prominent: Color.brand.opacity(hovered ? 0.88 : 1)
        case .destructive: Color.red.opacity(hovered ? 0.85 : 1)
        case .quiet: Color.primary.opacity(hovered ? 0.11 : 0.07)
        }
    }
}

/// 只有图标的小圆按钮，例如移除一行。
struct SettingsIconButton: View {
    let symbol: String
    let help: String
    var destructive = false
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovered && destructive ? Color.red : Color.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(hovered ? 0.1 : 0.05)))
                .contentShape(Circle())
        }
        .buttonStyle(SettingsPressStyle())
        .onHover { hovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

struct SettingsPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}
