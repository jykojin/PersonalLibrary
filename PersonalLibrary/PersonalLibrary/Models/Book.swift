import Foundation
import SwiftData

/// 书籍类型
enum BookType: String, Codable, CaseIterable {
    case paper = "纸质书"
    case ebook = "电子书"
    case audiobook = "有声书"
}

/// 书籍加入方式
enum AddSource: String, Codable, CaseIterable {
    case manual = "手动添加"
    case scanned = "扫码添加"
    case imported = "导入"
}

/// 书籍的阅读状态
enum ReadingStatus: String, Codable, CaseIterable {
    case reading = "正在读"
    case finished = "已读"
    case wishlist = "想读"
    case dropped = "弃读"
    case idle = "闲置"
}

/// 书籍模型 — 存储一本书的所有信息
@Model
final class Book {
    // 基本信息（所有属性均有默认值以兼容 CloudKit）
    var title: String = ""
    var author: String = ""
    var translator: String?  // 译者
    var isbn: String?
    var publisher: String?
    var publishDate: Date?
    var totalPages: Int = 0
    var price: String?  // 价格字符串，如 "¥59.00"
    var doubanURL: String?  // 豆瓣链接

    // 书籍类型（纸质书/电子书/有声书），默认纸质书
    var bookType: BookType = BookType.paper

    // 加入方式（手动/扫码/导入）
    var addSource: AddSource = AddSource.manual

    // 描述信息
    var bookDescription: String?  // 书籍简介
    var authorDescription: String?  // 作者简介

    // 封面
    var coverImageData: Data?
    var coverImageURL: String?  // 封面图片 URL（备用）

    // 阅读状态
    var currentPage: Int = 0
    var status: ReadingStatus = ReadingStatus.idle
    var rating: Int?  // 1-5 星，无默认值
    var notes: String?

    // 时间
    var addedDate: Date = Date()
    var finishedDate: Date?
    var statusChangedDate: Date?  // 标记阅读状态的时间

    // 微信读书关联
    var wereadBookId: String?  // 微信读书 bookId，用于同步匹配
    var wereadProgress: Int = 0  // 微信读书阅读进度 (0-100)

    // 逻辑删除（取消收藏）
    var isArchived: Bool = false

    // 关系（CloudKit 要求关系为 optional 或有默认值）
    var bookshelf: Bookshelf?
    var tags: [Tag]? = []

    @Relationship(deleteRule: .cascade, inverse: \ReadingRecord.book)
    var readingRecords: [ReadingRecord]? = []

    init(
        title: String,
        author: String,
        translator: String? = nil,
        isbn: String? = nil,
        publisher: String? = nil,
        publishDate: Date? = nil,
        totalPages: Int = 0,
        price: String? = nil,
        doubanURL: String? = nil,
        bookType: BookType = .paper,
        bookDescription: String? = nil,
        authorDescription: String? = nil,
        coverImageURL: String? = nil
    ) {
        self.title = title
        self.author = author
        self.translator = translator
        self.isbn = isbn
        self.publisher = publisher
        self.publishDate = publishDate
        self.totalPages = totalPages
        self.price = price
        self.doubanURL = doubanURL
        self.bookType = bookType
        self.bookDescription = bookDescription
        self.authorDescription = authorDescription
        self.coverImageURL = coverImageURL
        self.currentPage = 0
        self.status = .idle
        self.addedDate = Date()
    }

    /// 阅读进度百分比 (0.0 ~ 1.0)
    var progress: Double {
        guard totalPages > 0 else { return 0 }
        return Double(currentPage) / Double(totalPages)
    }
}
