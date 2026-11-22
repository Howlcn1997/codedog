import AppKit
import SwiftUI

/// 近一年活动热力图（GitHub 风格）：每列一周，每行一天，圆角方块按活跃度分 5 档上色。
/// 格子大小随可用宽度自适应；传入 `selection` 时可以点选某一天（再点一次取消）。
struct HeatmapView: View {
    /// yyyy-MM-dd → 次数
    var days: [String: Int]
    var selection: Binding<String?>? = nil
    var weeks = 53

    @State private var width: CGFloat = 0

    private let label: CGFloat = 16
    private let monthHeight: CGFloat = 12

    static func key(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private struct Cell: Identifiable {
        var id: Int
        var key: String
        var count: Int
        var future: Bool
    }

    /// 日期骨架（每格的日期键、是否未来、月份标签）每天只算一次，各个热力图共用；
    /// 悬停读数会频繁重算 body，每次都做 371 次日期运算太浪费。
    private struct Skeleton {
        var day: Date
        var weeks: Int
        var keys: [[(key: String, future: Bool)]]
        var months: [(column: Int, label: String)]
    }

    @MainActor private static var skeletonCache: Skeleton?

    @MainActor private static func skeleton(weeks: Int) -> Skeleton {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        if let s = skeletonCache, s.day == today, s.weeks == weeks { return s }
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let start = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)!
        var columns: [[(String, Bool)]] = []
        var months: [(Int, String)] = []
        var lastMonth = -1
        for w in 0..<weeks {
            var col: [(String, Bool)] = []
            for d in 0..<7 {
                let date = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                col.append((key(date), date > today))
                let month = cal.component(.month, from: date)
                if d == 0, month != lastMonth {
                    lastMonth = month
                    // 相邻月份标签太近会重叠：保留后一个
                    if let last = months.last, w - last.0 < 3 { months.removeLast() }
                    if w < weeks - 2 { months.append((w, date.formatted(.dateTime.month(.abbreviated).locale(AppLanguage.locale)))) }
                }
            }
            columns.append(col)
        }
        let s = Skeleton(day: today, weeks: weeks, keys: columns.map { $0.map { (key: $0.0, future: $0.1) } }, months: months.map { (column: $0.0, label: $0.1) })
        skeletonCache = s
        return s
    }

    private var grid: (cells: [[Cell]], months: [(column: Int, label: String)]) {
        let s = Self.skeleton(weeks: weeks)
        let cells = s.keys.enumerated().map { w, col in
            col.enumerated().map { d, k in Cell(id: w * 7 + d, key: k.key, count: days[k.key] ?? 0, future: k.future) }
        }
        return (cells, s.months)
    }

    /// 按非零值的四分位数分成 4 档。
    private func level(_ n: Int, thresholds: [Int]) -> Int {
        guard n > 0 else { return 0 }
        return 1 + thresholds.filter { n > $0 }.count
    }

    /// 每列占的宽度（格子 + 间距）
    private var step: CGFloat { max(4, (width - label) / CGFloat(weeks)) }
    private var spacing: CGFloat { max(1.5, step * 0.22) }
    private var cell: CGFloat { step - spacing }
    private var gridHeight: CGFloat { monthHeight + 4 + 7 * step - spacing }

    @State private var hovered: Cell?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: width > 0 ? gridHeight : 90)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .overlay(alignment: .topLeading) { if width > 0 { content } }
            HStack(spacing: 8) {
                // 悬停的那一天（代替每个格子各自的提示，几百个提示视图会让详情面板打开变慢）
                if let c = hovered, !c.future {
                    Text(c.count > 0 ? String(localized: "\(c.key)：\(c.count) 次活动") : c.key)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                legend
            }
        }
    }

    private var content: some View {
        let g = grid
        let values = days.values.filter { $0 > 0 }.sorted()
        let thresholds: [Int] = values.isEmpty ? [] : [0.25, 0.5, 0.75].map { values[min(values.count - 1, Int(Double(values.count) * $0))] }
        let selectedKey = selection?.wrappedValue
        return VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                ForEach(g.months, id: \.column) { m in
                    Text(m.label)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .offset(x: label + CGFloat(m.column) * step)
                }
            }
            .frame(height: monthHeight, alignment: .topLeading)
            HStack(alignment: .top, spacing: spacing) {
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(0..<7, id: \.self) { d in
                        Text(weekdayLabel(d)).font(.system(size: 8)).foregroundStyle(.secondary)
                            .frame(height: cell)
                    }
                }
                .frame(width: label - spacing, alignment: .leading)
                // 所有格子用一个 Canvas 画完：一年 371 个格子各是一个视图时，打开详情面板要多花上百毫秒
                Canvas { ctx, _ in
                    let radius = max(1.5, cell * 0.22)
                    for (w, col) in g.cells.enumerated() {
                        for (d, c) in col.enumerated() where !c.future {
                            let rect = CGRect(x: CGFloat(w) * step, y: CGFloat(d) * step, width: cell, height: cell)
                            ctx.fill(RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect),
                                     with: .color(color(level(c.count, thresholds: thresholds))))
                            if c.key == selectedKey {
                                ctx.stroke(RoundedRectangle(cornerRadius: radius + 1, style: .continuous).path(in: rect.insetBy(dx: -1.5, dy: -1.5)),
                                           with: .color(.primary), lineWidth: 1.2)
                            }
                        }
                    }
                }
                .frame(width: CGFloat(weeks) * step, height: 7 * step - spacing)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active(let p) = phase { hovered = cellAt(p, in: g.cells) } else { hovered = nil }
                }
                .gesture(SpatialTapGesture().onEnded { e in
                    guard let selection, let c = cellAt(e.location, in: g.cells), !c.future else { return }
                    withAnimation(.snappy(duration: 0.2)) { selection.wrappedValue = selection.wrappedValue == c.key ? nil : c.key }
                })
            }
        }
    }

    private func cellAt(_ p: CGPoint, in cells: [[Cell]]) -> Cell? {
        let w = Int(p.x / step), d = Int(p.y / step)
        guard cells.indices.contains(w), (0..<7).contains(d), cells[w].indices.contains(d) else { return nil }
        return cells[w][d]
    }

    private var legend: some View {
        HStack(spacing: 3) {
            Text("少").padding(.trailing, 2)
            ForEach(0..<5, id: \.self) { l in
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color(l)).frame(width: 8, height: 8)
            }
            Text("多").padding(.leading, 2)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private func weekdayLabel(_ row: Int) -> String {
        let weekday = (Calendar.current.firstWeekday - 1 + row) % 7  // 0 = 周日
        var cal = Calendar.current
        cal.locale = AppLanguage.locale
        return [1, 3, 5].contains(weekday) ? cal.veryShortStandaloneWeekdaySymbols[weekday] : ""
    }

    private func color(_ level: Int) -> Color {
        switch level {
        case 0: Color.primary.opacity(0.07)
        case 1: Self.adaptive(light: 0x9BE9A8, dark: 0x0E4429)
        case 2: Self.adaptive(light: 0x40C463, dark: 0x006D32)
        case 3: Self.adaptive(light: 0x30A14E, dark: 0x26A641)
        default: Self.adaptive(light: 0x216E39, dark: 0x39D353)
        }
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        func ns(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ns(dark) : ns(light)
        })
    }
}
