import CodedogCore
import SwiftUI

struct ProjectTable: View {
    @Environment(LibraryModel.self) private var model
    var rows: [(item: ProjectItem, match: SearchMatch)]

    struct Row: Identifiable {
        var item: ProjectItem
        var match: SearchMatch
        var id: String { item.id }
    }

    var body: some View {
        @Bindable var model = model
        let data = rows.map { Row(item: $0.item, match: $0.match) }
        Table(data, selection: $model.selectedID) {
            TableColumn("名称") { row in
                HStack(spacing: 10) {
                    Image(systemName: row.item.project.kind.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(row.item.project.name).fontWeight(.medium)
                            if row.item.meta.favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                        }
                        Text(row.match.reasons.first.flatMap { $0.hasPrefix("名称") ? nil : $0 } ?? Formatting.shortPath(row.item.id))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 3)
            }
            .width(min: 220, ideal: 320)
            TableColumn("类型") { row in Text(row.item.project.kind.displayName) }
                .width(min: 60, ideal: 80)
            TableColumn("技术栈") { row in Text(row.item.project.stacks.map(\.displayName).joined(separator: "、")).foregroundStyle(.secondary) }
                .width(min: 80, ideal: 120)
            TableColumn("分支") { row in
                HStack(spacing: 4) {
                    if let dirty = row.item.project.git?.dirtyFiles, dirty > 0 {
                        Circle().fill(.orange).frame(width: 6, height: 6)
                    }
                    Text(row.item.project.git?.branch ?? "—").foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .width(min: 80, ideal: 140)
            TableColumn("分类") { row in Text(row.item.categoryNames.joined(separator: "、")).foregroundStyle(.secondary) }
                .width(min: 60, ideal: 120)
            TableColumn("最近活动") { row in Text(Formatting.activity(row.item.lastActivity)).foregroundStyle(.secondary) }
                .width(min: 70, ideal: 90)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let row = data.first(where: { $0.id == id }) {
                ProjectMenu(item: row.item)
            }
        } primaryAction: { ids in
            if let id = ids.first, let row = data.first(where: { $0.id == id }) { model.open(row.item) }
        }
        .scrollContentBackground(.hidden)
    }
}
