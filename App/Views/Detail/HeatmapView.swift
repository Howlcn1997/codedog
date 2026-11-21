import SwiftUI

/// 近一年活动圆点图：每列一周，每行一天，空白日为小灰点。
struct HeatmapView: View {
    /// yyyy-MM-dd → 次数
    var days: [String: Int]
    var unit: String
    var weeks = 53
    var cell: CGFloat = 7.4
    var spacing: CGFloat = 3

    private struct Cell: Identifiable {
        var id: Int
        var date: Date
        var key: String
        var count: Int
        var future: Bool
    }

    private var grid: (cells: [[Cell]], months: [(column: Int, label: String)]) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let start = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)!
        var columns: [[Cell]] = []
        var months: [(Int, String)] = []
        var lastMonth = -1
        for w in 0..<weeks {
            var col: [Cell] = []
            for d in 0..<7 {
                let date = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                let c = cal.dateComponents([.year, .month, .day], from: date)
                let key = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
                col.append(Cell(id: w * 7 + d, date: date, key: key, count: days[key] ?? 0, future: date > today))
                if d == 0, c.month! != lastMonth {
                    lastMonth = c.month!
                    if w < weeks - 2 { months.append((w, "\(c.month!)月")) }
                }
            }
            columns.append(col)
        }
        return (columns, months)
    }

    /// 按非零值的四分位数分成 4 档。
    private func level(_ n: Int, thresholds: [Int]) -> Int {
        guard n > 0 else { return 0 }
        return 1 + thresholds.filter { n > $0 }.count
    }

    private let label: CGFloat = 18

    var body: some View {
        let g = grid
        let values = days.values.filter { $0 > 0 }.sorted()
        let thresholds: [Int] = values.isEmpty ? [] : [0.25, 0.5, 0.75].map { values[min(values.count - 1, Int(Double(values.count) * $0))] }
        return VStack(alignment: .leading, spacing: 4) {
            monthRow(g.months)
            HStack(alignment: .top, spacing: spacing) {
                weekdayColumn
                ForEach(Array(g.cells.enumerated()), id: \.offset) { _, col in
                    column(col, thresholds: thresholds)
                }
            }
        }
        .frame(height: 12 + 4 + 7 * cell + 6 * spacing, alignment: .top)
    }

    private func monthRow(_ months: [(column: Int, label: String)]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(months, id: \.column) { m in
                Text(m.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .offset(x: label + CGFloat(m.column) * (cell + spacing))
            }
        }
        .frame(height: 12)
    }

    private var weekdayColumn: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<7, id: \.self) { d in
                Text(weekdayLabel(d)).font(.system(size: 8)).foregroundStyle(.tertiary).frame(height: cell)
            }
        }
        .frame(width: label - spacing, alignment: .leading)
    }

    private func column(_ col: [Cell], thresholds: [Int]) -> some View {
        VStack(spacing: spacing) {
            ForEach(col) { c in
                dot(c, level: level(c.count, thresholds: thresholds))
            }
        }
    }

    private func dot(_ c: Cell, level: Int) -> some View {
        Circle()
            .fill(color(level))
            .scaleEffect(c.count == 0 ? 0.62 : 1)
            .opacity(c.future ? 0 : 1)
            .frame(width: cell, height: cell)
            .help(c.count > 0 ? "\(c.key)：\(c.count) \(unit)" : c.key)
    }

    private func weekdayLabel(_ row: Int) -> String {
        let cal = Calendar.current
        let weekday = (cal.firstWeekday - 1 + row) % 7  // 0 = 周日
        return [1, 3, 5].contains(weekday) ? ["日", "一", "二", "三", "四", "五", "六"][weekday] : ""
    }

    private func color(_ level: Int) -> Color {
        switch level {
        case 0: Color.primary.opacity(0.12)
        case 1: Color.brand.opacity(0.35)
        case 2: Color.brand.opacity(0.55)
        case 3: Color.brand.opacity(0.78)
        default: Color.brand
        }
    }
}
