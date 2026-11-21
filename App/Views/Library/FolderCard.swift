import CodedogCore
import SwiftUI

/// 文件夹轮廓：左上角凸起的标签页，向右平滑下降。
struct FolderShape: Shape {
    var radius: CGFloat = 16
    var tabHeight: CGFloat = 12
    var tabWidthRatio: CGFloat = 0.42

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, r = radius, t = tabHeight
        let split = w * tabWidthRatio, slope: CGFloat = 18
        var p = Path()
        p.move(to: CGPoint(x: 0, y: r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
        p.addLine(to: CGPoint(x: split, y: 0))
        p.addCurve(to: CGPoint(x: split + slope, y: t),
                   control1: CGPoint(x: split + slope * 0.55, y: 0),
                   control2: CGPoint(x: split + slope * 0.45, y: t))
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

/// 项目卡片：后层文件夹 + 露出的纸张（类型图标）+ 前层玻璃面板（名称、状态、徽标）。
struct FolderCard: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var item: ProjectItem
    var match: SearchMatch
    var isSelected: Bool

    @State private var hovering = false

    static let size = CGSize(width: 224, height: 200)

    private var tint: Color? {
        item.meta.categories.lazy.compactMap { id in
            model.library.categories.first { $0.id == id }.flatMap { CategoryPalette.color($0.color) }
        }.first
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 后层
            FolderShape()
                .fill(scheme == .dark ? Color(white: 0.36) : Color(white: 0.78))
                .frame(height: 178)
                .offset(y: 22)

            // 纸张
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(scheme == .dark ? Color(white: 0.80) : Color.white)
                .overlay(alignment: .top) {
                    Image(systemName: item.project.kind.symbol)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Color(white: 0.45))
                        .padding(.top, 26)
                }
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                .frame(width: Self.size.width - 44, height: 120)
                .offset(y: hovering ? -6 : 4)

            // 前层玻璃面板
            front
                .frame(height: 122)
                .offset(y: 78)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
    }

    private var front: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(item.project.name)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if item.meta.favorite {
                    Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(.yellow)
                }
            }
            statusLine
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let stack = item.project.stacks.first {
                    Text(stack.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(item.project.kind.displayName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(.black.opacity(scheme == .dark ? 0.22 : 0.08), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular.tint((tint ?? Color(white: 0.55)).opacity(tint == nil ? 0.25 : 0.45)), in: FolderShape(radius: 18, tabHeight: 12, tabWidthRatio: 0.38))
        .overlay {
            FolderShape(radius: 18, tabHeight: 12, tabWidthRatio: 0.38)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
        }
        .shadow(color: .black.opacity(hovering ? 0.28 : 0.18), radius: hovering ? 14 : 8, y: hovering ? 8 : 4)
    }

    @ViewBuilder private var statusLine: some View {
        if let reason = match.reasons.first, !reason.hasPrefix("名称") {
            Text(reason)
        } else {
            let dirty = item.project.git?.dirtyFiles ?? 0
            HStack(spacing: 4) {
                if dirty > 0 {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                }
                Text(Formatting.activity(item.lastActivity))
                if dirty > 0 { Text("· \(dirty) 处改动") }
                else if let branch = item.project.git?.branch { Text("· \(branch)") }
            }
        }
    }
}

extension FolderShape: InsettableShape {
    func inset(by amount: CGFloat) -> some InsettableShape { InsetFolder(base: self, amount: amount) }
}

struct InsetFolder: InsettableShape {
    var base: FolderShape
    var amount: CGFloat
    func path(in rect: CGRect) -> Path { base.path(in: rect.insetBy(dx: amount, dy: amount)) }
    func inset(by more: CGFloat) -> InsetFolder { InsetFolder(base: base, amount: amount + more) }
}
