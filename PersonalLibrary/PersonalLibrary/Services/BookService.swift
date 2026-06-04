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
            return CoverImageProcessor.thumbnailData(from: data)  // 入口处压成缩略图，避免大图入库
        } catch {
            return nil
        }
    }
}

// MARK: - ISBN 去重检查

/// ISBN 重复检查工具
enum ISBNDuplicateChecker {

    /// 清理 ISBN（去除连字符和空格，只保留数字和 X）
    static func cleanISBN(_ isbn: String) -> String {
        isbn.replacingOccurrences(of: "[^0-9Xx]", with: "", options: .regularExpression).uppercased()
    }

    /// 查找本地是否已有相同 ISBN 的书籍
    /// - Returns: 已有的书籍，如果没找到返回 nil
    @MainActor
    static func findExisting(isbn: String, in context: ModelContext) -> Book? {
        let cleaned = cleanISBN(isbn)
        guard !cleaned.isEmpty else { return nil }

        // 先用精确匹配快速查（大多数情况 ISBN 格式一致）
        let isbnStr = isbn
        var exactDescriptor = FetchDescriptor<Book>(
            predicate: #Predicate { $0.isbn == isbnStr }
        )
        exactDescriptor.fetchLimit = 1
        if let match = try? context.fetch(exactDescriptor).first {
            return match
        }

        // 精确匹配失败，做清理后的模糊匹配（处理连字符等格式差异）
        var descriptor = FetchDescriptor<Book>(
            predicate: #Predicate { $0.isbn != nil }
        )
        descriptor.fetchLimit = 500  // 保护性上限
        guard let books = try? context.fetch(descriptor) else { return nil }

        return books.first { book in
            guard let bookISBN = book.isbn else { return false }
            return cleanISBN(bookISBN) == cleaned
        }
    }
}
