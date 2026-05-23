import Foundation
import SwiftData

/// 书籍服务 — 提供数据操作的业务逻辑
/// 当前版本使用 SwiftData 本地存储，未来可扩展为网络 API
@Observable
class BookService {
    private var modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// 通过 ISBN 搜索书籍信息
    /// 已通过 ISBNLookupService 在 AddBookView 中实现
    func lookupISBN(_ isbn: String) async throws -> Book? {
        return nil
    }

    /// 获取本月阅读统计
    func monthlyStats() -> (pagesRead: Int, minutesRead: Int, booksFinished: Int) {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!

        let descriptor = FetchDescriptor<ReadingRecord>(
            predicate: #Predicate<ReadingRecord> { record in
                record.date >= startOfMonth
            }
        )

        let records = (try? modelContext.fetch(descriptor)) ?? []
        let pages = records.reduce(0) { $0 + $1.pagesRead }
        let minutes = records.reduce(0) { $0 + $1.durationMinutes }

        // 使用内存过滤避免 SwiftData Predicate 中 enum 比较问题
        // (iOS 17.1+ 中 #Predicate 对 RawRepresentable enum 的比较可能编译失败或运行时崩溃)
        let allBooksDescriptor = FetchDescriptor<Book>()
        let allBooks = (try? modelContext.fetch(allBooksDescriptor)) ?? []
        let booksFinished = allBooks.filter { book in
            book.status == .finished &&
            book.finishedDate != nil &&
            book.finishedDate! >= startOfMonth
        }.count

        return (pages, minutes, booksFinished)
    }
}
