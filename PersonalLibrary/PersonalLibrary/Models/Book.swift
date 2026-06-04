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
    case imported = "文件导入"
    case wereadImported = "微信读书导入"

    /// 兼容旧数据：rawValue "导入" → .imported
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "导入": self = .imported
        default: self = AddSource(rawValue: rawValue) ?? .manual
        }
    }
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

    // 封面（externalStorage: 大数据存外部文件，不内联 SQLite，避免 query 时加载）
    @Attribute(.externalStorage) var coverImageData: Data?
    var coverImageURL: String?  // 封面图片 URL（备用）

    // 阅读状态
    var currentPage: Int = 0
    var status: ReadingStatus = ReadingStatus.idle
    var rating: Int?  // 1-5 星，无默认值
    var notes: String?

    // 时间
    var addedDate: Date = Date()
    var startedReadingDate: Date?  // 开始阅读日期
    var finishedDate: Date?
    var statusChangedDate: Date?  // 标记阅读状态的时间

    // 微信读书关联
    var wereadBookId: String?  // 微信读书 bookId，用于同步匹配
    var wereadProgress: Int = 0  // 微信读书阅读进度 (0-100)
    var wereadReadingHours: Double = 0  // 微信读书阅读时长（小时）
    var wereadEnrichedDate: Date?  // 上次通过微信读书 API 补全的时间，nil 表示从未补全
    var isWereadUserImported: Bool = false  // true = 用户导入到微信读书的书(epub/pdf), false = 微信读书平台书
    var isStartedReadingDateEstimated: Bool = false  // true = startedReadingDate 是估算值(updateTime-totalSeconds)，下次同步获取到真实值时应覆盖

    // 批量补全标记
    var lastEnrichmentDate: Date?  // 上次批量补全的时间，nil 表示从未处理

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

    /// 是否有有效封面数据（externalStorage 可能返回空 Data 而非 nil）
    var hasCoverData: Bool {
        guard let data = coverImageData else { return false }
        return data.count >= 1024  // <1KB 视为损坏占位（历史写入过38字节坏数据），当作无封面以便重抓自愈
    }

    /// 阅读进度百分比 (0.0 ~ 1.0)
    var progress: Double {
        guard totalPages > 0 else { return 0 }
        return Double(currentPage) / Double(totalPages)
    }

    /// 微信读书阅读时长摘要文本（用于阅读记录区域展示）
    var readingSummaryText: String? {
        guard wereadReadingHours > 0 else { return nil }
        return "微信读书累计 \(String(format: "%.1f", wereadReadingHours)) 小时"
    }

    /// 是否需要外部源数据补全（缺出版社/页数/定价/出版日期/简介/作者简介任一）
    var needsEnrichment: Bool {
        let missingPublisher = publisher == nil || publisher?.isEmpty == true
        let missingPages = totalPages == 0
        let missingPrice = price == nil || price?.isEmpty == true
        let missingPublishDate = publishDate == nil
        let missingBookDesc = bookDescription == nil || bookDescription?.isEmpty == true
        let missingAuthorDesc = authorDescription == nil || authorDescription?.isEmpty == true
        return missingPublisher || missingPages || missingPrice || missingPublishDate
            || missingBookDesc || missingAuthorDesc
    }
}
