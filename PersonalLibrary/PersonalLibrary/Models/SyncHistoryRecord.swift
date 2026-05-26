import Foundation
import SwiftData

@Model
final class SyncHistoryRecord {
    var id: UUID
    var eventType: String
    var startTime: Date
    var endTime: Date?
    var totalRemote: Int
    var newImported: Int
    var progressUpdated: Int
    var statusUpdated: Int
    var booksArchived: Int
    var booksEnriched: Int = 0
    var errorMessage: String?
    var triggeredBy: String

    init(
        eventType: String,
        triggeredBy: String,
        startTime: Date = .now
    ) {
        self.id = UUID()
        self.eventType = eventType
        self.startTime = startTime
        self.endTime = nil
        self.totalRemote = 0
        self.newImported = 0
        self.progressUpdated = 0
        self.statusUpdated = 0
        self.booksArchived = 0
        self.booksEnriched = 0
        self.errorMessage = nil
        self.triggeredBy = triggeredBy
    }

    enum EventType {
        static let manualSync = "manualSync"
        static let autoSync = "autoSync"
        static let resetState = "resetState"
    }

    enum Trigger {
        static let user = "user"
        static let system = "system"
    }

    var isInProgress: Bool {
        endTime == nil && errorMessage == nil
    }

    var summary: String {
        if eventType == EventType.resetState {
            return "重置 \(newImported) 本"
        }
        if let error = errorMessage {
            return "失败: \(error)"
        }
        if endTime == nil {
            return "同步中…"
        }
        var parts: [String] = []
        if newImported > 0 { parts.append("新增\(newImported)") }
        if booksEnriched > 0 { parts.append("补全\(booksEnriched)") }
        if progressUpdated > 0 { parts.append("更新\(progressUpdated)") }
        if statusUpdated > 0 { parts.append("状态\(statusUpdated)") }
        if booksArchived > 0 { parts.append("移除\(booksArchived)") }
        if parts.isEmpty { return "无变化" }
        return parts.joined(separator: "，")
    }
}
