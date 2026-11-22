import CodedogCore
import SwiftUI

/// 技术栈徽章：圆角方块，填充技术栈主色，写缩写；没有技术栈时显示项目形态图标。
struct StackBadge: View {
    var project: DiscoveredProject
    var size: CGFloat = 40
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let icon = StackIcon.of(project)
        let base = icon?.brand ?? Color.brand
        // 纯黑品牌色在暗色模式下抬亮一点，避免和背景糊在一起
        let fill = scheme == .dark && base.relativeLuminance < 0.02 ? Color(white: 0.16) : base
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(LinearGradient(colors: [fill.mix(with: .white, by: 0.12), fill], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                if let icon {
                    Image(icon.asset)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(icon.glyph)
                        .padding(size * 0.22)
                } else {
                    Image(systemName: project.kind.symbol)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(.white.opacity(scheme == .dark ? 0.14 : 0.3), lineWidth: 0.5)
            )
            .shadow(color: base.opacity(0.3), radius: 6, y: 3)
            .frame(width: size, height: size)
            .help(icon?.label ?? project.kind.displayName)
    }
}

/// 近 N 天活跃度迷你柱（提交 + AI 回复）。
struct ActivitySpark: View {
    var item: ProjectItem
    var days = 28
    var color: Color = .brand

    var body: some View {
        let values = Self.series(item, days: days)
        let maxV = max(values.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                Capsule()
                    .fill(v == 0 ? Color.primary.opacity(0.10) : color.opacity(0.45 + 0.55 * Double(v) / Double(maxV)))
                    .frame(width: 3, height: v == 0 ? 3 : 4 + 16 * CGFloat(v) / CGFloat(maxV))
            }
        }
        .frame(height: 20, alignment: .bottom)
        .accessibilityLabel("近 \(days) 天活跃度")
    }

    static func series(_ item: ProjectItem, days: Int) -> [Int] {
        let cal = Calendar.current
        let commits = item.commitDays, ai = item.aiDays
        let today = cal.startOfDay(for: .now)
        return (0..<days).reversed().map { back in
            let d = cal.date(byAdding: .day, value: -back, to: today)!
            let c = cal.dateComponents([.year, .month, .day], from: d)
            let key = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
            return (commits[key] ?? 0) + (ai[key] ?? 0)
        }
    }
}

/// 状态胶囊：运行中 / 等你回复 / N 个未提交。
struct StatusPill: View {
    var item: ProjectItem

    var body: some View {
        let dirty = item.project.git?.dirtyFiles ?? 0
        if !item.running.isEmpty {
            pill("运行中", .green, pulse: true)
        } else if item.waiting {
            pill("等你回复", .orange)
        } else if dirty > 0 {
            pill("\(dirty) 未提交", .secondary)
        }
    }

    private func pill(_ text: LocalizedStringKey, _ color: Color, pulse: Bool = false) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
                .symbolEffect(.pulse, isActive: pulse)
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(color == .secondary ? .secondary : color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(color == .secondary ? 0.10 : 0.14), in: Capsule())
        .fixedSize()
    }
}
