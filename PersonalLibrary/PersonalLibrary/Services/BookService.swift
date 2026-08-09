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

    /// 当月零点（1 号 00:00）。日历计算理论上不会失败，但避免强解包导致崩溃。
    static func startOfCurrentMonth(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        calendar.date(from: calendar.dateComponents([.year, .month], from: now))
    }

    /// 获取本月阅读统计
    func monthlyStats() -> (pagesRead: Int, minutesRead: Int, booksFinished: Int) {
        guard let startOfMonth = Self.startOfCurrentMonth() else { return (0, 0, 0) }

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
            guard book.status == .finished, let finished = book.finishedDate else { return false }
            return finished >= startOfMonth
        }.count

        return (pages, minutes, booksFinished)
    }

    // MARK: - Shared Data Helpers

    /// 查找或创建标签（供 WeReadService / WeReadSyncService 等共用）
    /// 按 trim 后的名字查找/创建，避免「签名」与「签名 」被当作两个标签。
    static func findOrCreateTag(name: String, modelContext: ModelContext) throws -> Tag {
        let tagName = name.trimmingCharacters(in: .whitespaces)
        var descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate { $0.name == tagName }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let tag = Tag(name: tagName)
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

    /// WeRead 封面图片最大允许 10MB（防超大响应耗尽内存）
    private static let maxCoverSize = 10 * 1024 * 1024

    /// 下载图片数据（供封面下载等共用）
    /// 注：URL 来自微信读书 API（可信源，非用户输入），故不做域名白名单——
    /// WeRead 封面 CDN 域名不固定，白名单会静默掐断正常封面同步。仅做 https + 大小上限。
    static func downloadImage(from urlString: String) async -> Data? {
        guard let url = URL(string: urlString), url.scheme == "https" else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  data.count <= maxCoverSize else { return nil }
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
    /// - Parameter bookType: 限定载体。同一 ISBN 的纸质书与电子书是两本不同的书
    ///   （常见于"实体书 + 微信读书电子版都收"），传入类型可避免电子书拦住纸质书的添加。
    ///   传 nil 表示不限载体（保持旧行为）。
    /// - Returns: 已有的书籍，如果没找到返回 nil
    @MainActor
    static func findExisting(isbn: String, bookType: BookType? = nil, in context: ModelContext) -> Book? {
        matchingBooks(isbn: isbn, in: context).first { book in
            guard let bookType else { return true }
            return book.bookType == bookType
        }
    }

    /// 查找同 ISBN 但载体不同的版本（用于"你已有电子书版"这类温和提示）。
    @MainActor
    static func findOtherEditions(isbn: String, excluding bookType: BookType, in context: ModelContext) -> [Book] {
        matchingBooks(isbn: isbn, in: context).filter { $0.bookType != bookType }
    }

    /// 取出所有 ISBN 匹配的书（已做连字符等格式归一化）
    @MainActor
    private static func matchingBooks(isbn: String, in context: ModelContext) -> [Book] {
        let cleaned = cleanISBN(isbn)
        guard !cleaned.isEmpty else { return [] }

        var descriptor = FetchDescriptor<Book>(
            predicate: #Predicate { $0.isbn != nil }
        )
        descriptor.fetchLimit = 500  // 保护性上限
        guard let books = try? context.fetch(descriptor) else { return [] }

        return books.filter { book in
            guard let bookISBN = book.isbn else { return false }
            return cleanISBN(bookISBN) == cleaned
        }
    }
}
