import Foundation
import SwiftData

/// 导入/添加操作的历史记录
@Model
final class ImportRecord {
    /// 操作时间
    var date: Date = Date()
    /// 来源类型（手动添加/扫码添加/文件导入/微信读书导入）
    var source: String = ""
    /// 尝试导入的总数
    var totalCount: Int = 0
    /// 成功导入的数量
    var successCount: Int = 0
    /// 跳过的数量（重复等）
    var skippedCount: Int = 0
    /// 备注信息（如文件名等）
    var note: String?

    init(source: String, totalCount: Int, successCount: Int, skippedCount: Int = 0, note: String? = nil) {
        self.date = Date()
        self.source = source
        self.totalCount = totalCount
        self.successCount = successCount
        self.skippedCount = skippedCount
        self.note = note
    }
}
