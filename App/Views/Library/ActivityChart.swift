import SwiftUI

/// 活跃度柱状图：每个时间桶内最后活动的项目数。点击柱子按该时间段筛选。
struct ActivityChart: View {
    @Environment(LibraryModel.self) private var model
    var buckets: [ActivityBucket]

    var body: some View {
        let maxCount = max(buckets.map(\.count).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(buckets) { b in
                let selected = model.bucketFilter?.id == b.id
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: b.count == 0 ? 1.5 : 4, style: .continuous)
                        .fill(selected ? Color.accentColor : Color.secondary.opacity(b.count == 0 ? 0.35 : 0.55))
                        .frame(width: 26, height: b.count == 0 ? 3 : 8 + 54 * CGFloat(b.count) / CGFloat(maxCount))
                    Text(showLabel(b) ? b.label : " ")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: 0)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.snappy) { model.bucketFilter = selected ? nil : b }
                }
                .help("\(b.label)：\(b.count) 个项目")
            }
        }
        .frame(height: 92)
    }

    private func showLabel(_ b: ActivityBucket) -> Bool {
        b.id == 0 || b.id == buckets.count - 1 || b.id % 2 == 0 && b.id < buckets.count - 2
    }
}
