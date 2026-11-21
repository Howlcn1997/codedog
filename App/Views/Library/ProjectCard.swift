import CodedogCore
import SwiftUI

/// 技术栈徽章：圆角方块，填充技术栈主色，写缩写；没有技术栈时显示项目形态图标。
struct StackBadge: View {
    var project: DiscoveredProject
    var size: CGFloat = 40

    var body: some View {
        let stack = project.stacks.first
        let base = stack?.color ?? Color.brand
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(LinearGradient(colors: [base.mix(with: .white, by: 0.18), base], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                if let stack {
                    Text(stack.abbreviation)
                        .font(.system(size: size * (stack.abbreviation.count > 2 ? 0.30 : 0.38), weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: project.kind.symbol)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
            )
            .shadow(color: base.opacity(0.35), radius: 6, y: 3)
            .frame(width: size, height: size)
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

    private func pill(_ text: String, _ color: Color, pulse: Bool = false) -> some View {
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

/// 项目卡：徽章 + 名称 + 描述，底部是 4 周活跃度与 AI 助手图标。
struct ProjectCard: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var item: ProjectItem
    var match: SearchMatch
    var isSelected: Bool

    @State private var hovering = false

    static let size = CGSize(width: 272, height: 156)

    private var tint: Color { item.project.stacks.first?.color ?? .brand }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                StackBadge(project: item.project)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(item.project.name)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        if item.meta.favorite {
                            Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow)
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 8)
            HStack(alignment: .bottom, spacing: 8) {
                ActivitySpark(item: item, color: tint)
                Spacer(minLength: 0)
                HStack(spacing: -4) {
                    ForEach(item.tools.prefix(4), id: \.tool) { t in
                        ToolIcon(tool: t.tool, size: 18)
                            .padding(1.5)
                            .background(Circle().fill(.background.opacity(0.8)))
                            .help(t.tool.displayName)
                    }
                }
            }
            HStack(spacing: 6) {
                Text(Formatting.activity(item.lastActivity)).lineLimit(1).fixedSize()
                if let size = item.size {
                    Text("·")
                    Text(Formatting.bytes(size.total)).monospacedDigit().lineLimit(1).fixedSize()
                }
                if let branch = item.project.git?.branch {
                    Text("·")
                    Label(branch, systemImage: "arrow.triangle.branch").labelStyle(.titleAndIcon).lineLimit(1)
                        .layoutPriority(-1)  // 空间不够时分支名先截断
                }
                Spacer(minLength: 4)
                StatusPill(item: item)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
        .padding(14)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background {
            // 技术栈色的柔光，从左上角铺开
            RadialGradient(colors: [tint.opacity(scheme == .dark ? 0.28 : 0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 220)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isSelected ? Color.brand : .white.opacity(scheme == .dark ? 0.08 : 0.5), lineWidth: isSelected ? 2 : 0.5)
        )
        .shadow(color: .black.opacity(hovering ? 0.18 : 0.08), radius: hovering ? 14 : 6, y: hovering ? 8 : 3)
        .offset(y: hovering ? -3 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var subtitle: String {
        if let reason = match.reasons.first, !reason.hasPrefix("名称") { return reason }
        return item.project.description.map(Formatting.plain) ?? "\(item.project.kind.displayName) · \(Formatting.shortPath(item.id))"
    }
}
