import SwiftUI
import SwiftData

/// 导入/添加历史记录页面
struct ImportHistoryView: View {
    @Query(sort: \ImportRecord.date, order: .reverse) private var records: [ImportRecord]

    var body: some View {
        List {
            if records.isEmpty {
                ContentUnavailableView(
                    "暂无记录",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("导入或添加书籍后会自动记录")
                )
            } else {
                ForEach(records) { record in
                    recordRow(record)
                }
            }
        }
        .navigationTitle("操作历史")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func recordRow(_ record: ImportRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(record.source)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(record.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Label("\(record.totalCount) 本", systemImage: "books.vertical")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("成功 \(record.successCount)", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)

                if record.skippedCount > 0 {
                    Label("跳过 \(record.skippedCount)", systemImage: "arrow.right.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let note = record.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ImportHistoryView()
    }
    .modelContainer(for: ImportRecord.self, inMemory: true)
}
