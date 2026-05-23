import SwiftUI

/// 多选模式下的底部操作栏（标签/移动/状态/评分）
struct BatchActionBar: View {
    let onTag: () -> Void
    let onMove: () -> Void
    let onStatus: () -> Void
    let onRating: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            batchButton(icon: "tag", label: "标签", action: onTag)
            batchButton(icon: "arrow.right.square", label: "移动", action: onMove)
            batchButton(icon: "book", label: "状态", action: onStatus)
            batchButton(icon: "star", label: "评分", action: onRating)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) { Divider() }
    }

    private func batchButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.orange)
        }
    }
}
