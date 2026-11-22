import SwiftUI

/// 统一的空态：玻璃图标块 + 柔和光晕 + 圆体标题 + 说明 + 可选操作。
/// 主窗口、列表、启动器共用，替代系统默认的 ContentUnavailableView。
struct EmptyStateView<Actions: View>: View {
    var symbol: String
    var title: String
    var message: String?
    var tint: Color = .brand
    var compact = false
    /// 图标轻微呼吸，用于"正在扫描"这类进行中的状态
    var animating = false
    @ViewBuilder var actions: () -> Actions

    init(_ title: String, symbol: String, message: String? = nil, tint: Color = .brand,
         compact: Bool = false, animating: Bool = false, @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }) {
        self.title = title
        self.symbol = symbol
        self.message = message
        self.tint = tint
        self.compact = compact
        self.animating = animating
        self.actions = actions
    }

    var body: some View {
        let box: CGFloat = compact ? 60 : 84
        VStack(spacing: compact ? 14 : 20) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 24 : 34, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .symbolEffect(.breathe, isActive: animating)
                .frame(width: box, height: box)
                .glassEffect(.regular.tint(tint.opacity(0.10)), in: RoundedRectangle(cornerRadius: box * 0.3, style: .continuous))
                .background {
                    // 图标背后的光晕，和主窗口背景的品牌色光晕呼应
                    Circle()
                        .fill(RadialGradient(colors: [tint.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: box * 1.3))
                        .frame(width: box * 2.6, height: box * 2.6)
                        .allowsHitTesting(false)
                }
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: compact ? 16 : 20, weight: .semibold, design: .rounded))
                if let message {
                    Text(message)
                        .font(.system(size: compact ? 12 : 13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 380)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) { actions() }
                .controlSize(compact ? .regular : .large)
                .padding(.top, compact ? 0 : 4)
        }
        .padding(compact ? 20 : 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
