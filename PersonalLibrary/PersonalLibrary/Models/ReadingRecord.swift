import Foundation
import SwiftData

/// 阅读记录 — 记录每次阅读的情况
@Model
final class ReadingRecord {
    var book: Book?
    var date: Date = Date()
    var startPage: Int = 0
    var endPage: Int = 0
    var durationMinutes: Int = 0  // 阅读时长（分钟）
    var note: String?

    init(
        book: Book,
        date: Date = Date(),
        startPage: Int,
        endPage: Int,
        durationMinutes: Int = 0,
        note: String? = nil
    ) {
        self.book = book
        self.date = date
        self.startPage = startPage
        self.endPage = endPage
        self.durationMinutes = durationMinutes
        self.note = note
    }

    /// 本次阅读的页数
    var pagesRead: Int {
        endPage - startPage
    }
}
