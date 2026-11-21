import CodedogCore
import Foundation

enum SmartFolder: String, CaseIterable, Hashable, Codable {
    case favorites, waiting, recent, dirty, hidden

    var title: String {
        switch self {
        case .favorites: "收藏"
        case .waiting: "在等你"
        case .recent: "最近打开"
        case .dirty: "有改动没提交"
        case .hidden: "已隐藏"
        }
    }

    var symbol: String {
        switch self {
        case .favorites: "star"
        case .waiting: "hourglass"
        case .recent: "clock"
        case .dirty: "pencil.and.outline"
        case .hidden: "eye.slash"
        }
    }

    func contains(_ item: ProjectItem, now: Date = .now) -> Bool {
        switch self {
        case .favorites: item.meta.favorite
        case .waiting: item.waiting
        case .recent: item.meta.lastOpened.map { now.timeIntervalSince($0) < 14 * 86_400 } ?? false
        case .dirty: (item.project.git?.dirtyFiles ?? 0) > 0
        case .hidden: item.meta.hidden
        }
    }
}

enum SidebarSelection: Hashable, Codable {
    case all
    case smart(SmartFolder)
    case category(UUID)
    case kind(ProjectKind)
    case tool(AITool)
}

enum TimeRange: String, CaseIterable, Identifiable {
    case week, month, quarter, halfYear, all
    var id: Self { self }

    var title: String {
        switch self {
        case .week: "近一周"
        case .month: "近1月"
        case .quarter: "近3月"
        case .halfYear: "近半年"
        case .all: "全部"
        }
    }

    var cutoff: Date? {
        let cal = Calendar.current
        let now = Date.now
        switch self {
        case .week: return cal.date(byAdding: .day, value: -7, to: now)
        case .month: return cal.date(byAdding: .month, value: -1, to: now)
        case .quarter: return cal.date(byAdding: .month, value: -3, to: now)
        case .halfYear: return cal.date(byAdding: .month, value: -6, to: now)
        case .all: return nil
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case activity, frecency, name, created
    var id: Self { self }

    var title: String {
        switch self {
        case .activity: "最近活动"
        case .frecency: "最常打开"
        case .name: "名称"
        case .created: "创建时间"
        }
    }

    func areInIncreasingOrder(_ a: ProjectItem, _ b: ProjectItem) -> Bool {
        switch self {
        case .activity:
            let x = a.lastActivity ?? .distantPast, y = b.lastActivity ?? .distantPast
            return x != y ? x > y : a.project.name.localizedStandardCompare(b.project.name) == .orderedAscending
        case .frecency:
            return LibrarySnapshot.defaultOrder(a, b)
        case .name:
            return a.project.name.localizedStandardCompare(b.project.name) == .orderedAscending
        case .created:
            return (a.project.createdAt ?? .distantPast) > (b.project.createdAt ?? .distantPast)
        }
    }
}

enum ViewMode: String, CaseIterable {
    case grid, list
}

/// 活跃度柱状图的一个时间桶。
struct ActivityBucket: Identifiable, Hashable {
    var id: Int
    var label: String
    var start: Date
    var end: Date
    var count: Int
}

enum OpenAction: Hashable {
    case resume(AITool)
    case newSession(AITool)
    case editor(AppRef?)
    case terminal
    case finder
    case repository
}
