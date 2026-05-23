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

    // MARK: - Shared Data Helpers

    /// 查找或创建标签（供 WeReadService / WeReadSyncService 等共用）
    static func findOrCreateTag(name: String, modelContext: ModelContext) throws -> Tag {
        let tagName = name
        var descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate { $0.name == tagName }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let tag = Tag(name: name)
        modelContext.insert(tag)
        return tag
    }

    /// 查找或创建书架（供 WeReadService / WeReadSyncService 等共用）
    static func findOrCreateBookshelf(name: String, icon: String, modelContext: ModelContext) throws -> Bookshelf {
        let shelfName = name
        var descriptor = FetchDescriptor<Bookshelf>(
            predicate: #Predicate { $0.name == shelfName }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let shelf = Bookshelf(name: name, icon: icon)
        modelContext.insert(shelf)
        return shelf
    }

    /// 下载图片数据（供封面下载等共用）
    static func downloadImage(from urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            return data
        } catch {
            return nil
        }
    }
}
