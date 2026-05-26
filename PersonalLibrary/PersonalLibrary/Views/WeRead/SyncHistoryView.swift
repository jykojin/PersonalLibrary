import SwiftUI
import SwiftData

struct SyncHistoryView: View {
    @Query(sort: \SyncHistoryRecord.startTime, order: .reverse)
    private var records: [SyncHistoryRecord]

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    var body: some View {
        List {
            if records.isEmpty {
                ContentUnavailableView("暂无同步记录", systemImage: "clock.arrow.circlepath")
            } else {
                ForEach(records) { record in
                    HStack(spacing: 12) {
                        Image(systemName: iconName(for: record))
                            .foregroundStyle(iconColor(for: record))
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(eventLabel(for: record))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if record.isInProgress {
                                    ProgressView()
                                        .controlSize(.mini)
                                }
                            }

                            Text(record.summary)
                                .font(.caption)
                                .foregroundStyle(record.errorMessage != nil ? .red : .secondary)

                            HStack(spacing: 4) {
                                Text(Self.timeFormatter.string(from: record.startTime))
                                if let end = record.endTime {
                                    Text("→")
                                    Text(Self.timeFormatter.string(from: end))
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        if record.totalRemote > 0 {
                            Text("\(record.totalRemote)本")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("同步历史")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func iconName(for record: SyncHistoryRecord) -> String {
        switch record.eventType {
        case SyncHistoryRecord.EventType.resetState:
            return "arrow.counterclockwise"
        case SyncHistoryRecord.EventType.autoSync:
            return "arrow.triangle.2.circlepath"
        default:
            return "arrow.clockwise"
        }
    }

    private func iconColor(for record: SyncHistoryRecord) -> Color {
        if record.errorMessage != nil { return .red }
        switch record.eventType {
        case SyncHistoryRecord.EventType.resetState: return .orange
        case SyncHistoryRecord.EventType.autoSync: return .green
        default: return .blue
        }
    }

    private func eventLabel(for record: SyncHistoryRecord) -> String {
        switch record.eventType {
        case SyncHistoryRecord.EventType.resetState: return "重置同步状态"
        case SyncHistoryRecord.EventType.autoSync: return "自动同步"
        default: return "手动同步"
        }
    }
}
