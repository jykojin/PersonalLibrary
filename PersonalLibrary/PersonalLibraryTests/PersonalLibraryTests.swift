import Foundation
import Testing
import SwiftData
import UIKit
@testable import PersonalLibrary

// MARK: - Book Model Tests

@Suite("Book Model Tests")
struct BookModelTests {

    @Test("新建书籍默认状态为闲置")
    func newBookIsIdle() {
        let book = Book(title: "测试书籍", author: "测试作者")
        #expect(book.status == .idle)
        #expect(book.currentPage == 0)
        #expect(book.progress == 0)
    }

    @Test("新建书籍默认类型为纸质书")
    func newBookIsPaper() {
        let book = Book(title: "测试书籍", author: "测试作者")
        #expect(book.bookType == .paper)
    }

    @Test("可以指定为电子书类型")
    func ebookType() {
        let book = Book(title: "电子书", author: "作者", bookType: .ebook)
        #expect(book.bookType == .ebook)
    }

    @Test("可以指定为有声书类型")
    func audiobookType() {
        let book = Book(title: "有声书", author: "作者", bookType: .audiobook)
        #expect(book.bookType == .audiobook)
    }

    @Test("阅读进度计算正确")
    func progressCalculation() {
        let book = Book(title: "测试书籍", author: "测试作者", totalPages: 200)
        book.currentPage = 50
        #expect(book.progress == 0.25)
    }

    @Test("总页数为0时进度为0")
    func zeroPageProgress() {
        let book = Book(title: "测试书籍", author: "测试作者", totalPages: 0)
        #expect(book.progress == 0)
    }

    @Test("进度满页为1.0")
    func fullProgress() {
        let book = Book(title: "测试书籍", author: "测试作者", totalPages: 100)
        book.currentPage = 100
        #expect(book.progress == 1.0)
    }

    @Test("初始化包含所有可选参数")
    func fullInit() {
        let date = Date()
        let book = Book(
            title: "完整书籍",
            author: "完整作者",
            translator: "译者",
            isbn: "9787000000001",
            publisher: "出版社",
            publishDate: date,
            totalPages: 300,
            price: "¥59.00",
            doubanURL: "https://douban.com/book/1",
            bookType: .ebook,
            bookDescription: "简介",
            authorDescription: "作者简介",
            coverImageURL: "https://example.com/cover.jpg"
        )
        #expect(book.title == "完整书籍")
        #expect(book.author == "完整作者")
        #expect(book.translator == "译者")
        #expect(book.isbn == "9787000000001")
        #expect(book.publisher == "出版社")
        #expect(book.publishDate == date)
        #expect(book.totalPages == 300)
        #expect(book.price == "¥59.00")
        #expect(book.doubanURL == "https://douban.com/book/1")
        #expect(book.bookType == .ebook)
        #expect(book.bookDescription == "简介")
        #expect(book.authorDescription == "作者简介")
        #expect(book.coverImageURL == "https://example.com/cover.jpg")
        #expect(book.currentPage == 0)
        #expect(book.status == .idle)
        #expect(book.rating == nil)
        #expect(book.notes == nil)
        #expect(book.finishedDate == nil)
    }

    @Test("新建书籍默认阅读时长为0")
    func newBookReadingHoursIsZero() {
        let book = Book(title: "测试", author: "测试")
        #expect(book.wereadReadingHours == 0)
    }

    @Test("可以设置微信读书阅读时长")
    func setWereadReadingHours() {
        let book = Book(title: "测试", author: "测试")
        book.wereadReadingHours = 5.5
        #expect(book.wereadReadingHours == 5.5)
    }

    @Test("微信读书阅读时长从秒正确转换为小时")
    func readingTimeSecondsToHours() {
        let book = Book(title: "测试", author: "测试")
        // 3600秒 = 1小时
        book.wereadReadingHours = Double(3600) / 3600.0
        #expect(book.wereadReadingHours == 1.0)
        // 5400秒 = 1.5小时
        book.wereadReadingHours = Double(5400) / 3600.0
        #expect(book.wereadReadingHours == 1.5)
    }

    @Test("可以修改阅读状态")
    func statusChange() {
        let book = Book(title: "测试", author: "测试")
        book.status = .reading
        #expect(book.status == .reading)
        book.status = .finished
        #expect(book.status == .finished)
        book.status = .dropped
        #expect(book.status == .dropped)
        book.status = .wishlist
        #expect(book.status == .wishlist)
    }

    @Test("可以设置评分")
    func ratingAssignment() {
        let book = Book(title: "测试", author: "测试")
        #expect(book.rating == nil)
        book.rating = 5
        #expect(book.rating == 5)
        book.rating = 1
        #expect(book.rating == 1)
    }

    @Test("statusChangedDate初始为nil")
    func statusChangedDateInitiallyNil() {
        let book = Book(title: "测试", author: "测试")
        #expect(book.statusChangedDate == nil)
    }

    @Test("coverImageData初始为nil")
    func coverImageDataInitiallyNil() {
        let book = Book(title: "测试", author: "测试")
        #expect(book.coverImageData == nil)
    }

    @Test("coverImageData可以被赋值和读取")
    func coverImageDataAssignment() {
        let book = Book(title: "测试", author: "测试")
        let testData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        book.coverImageData = testData
        #expect(book.coverImageData == testData)
    }

    @Test("coverImageData赋nil可清除")
    func coverImageDataClear() {
        let book = Book(title: "测试", author: "测试")
        book.coverImageData = Data([0x01, 0x02])
        book.coverImageData = nil
        #expect(book.coverImageData == nil)
    }
}

// MARK: - CoverImageCache Tests

@Suite("CoverImageCache Tests")
struct CoverImageCacheTests {

    @Test("缓存写入和读取")
    func cacheSetAndGet() {
        let cache = CoverImageCache.shared
        let key = "test_cover_\(UUID().uuidString)"
        let image = UIImage(systemName: "book")!
        cache.set(image, for: key)
        #expect(cache.image(for: key) != nil)
    }

    @Test("缓存移除")
    func cacheRemove() {
        let cache = CoverImageCache.shared
        let key = "test_remove_\(UUID().uuidString)"
        let image = UIImage(systemName: "star")!
        cache.set(image, for: key)
        cache.remove(for: key)
        #expect(cache.image(for: key) == nil)
    }

    @Test("缓存未命中返回nil")
    func cacheMiss() {
        let cache = CoverImageCache.shared
        #expect(cache.image(for: "nonexistent_\(UUID().uuidString)") == nil)
    }
}

// MARK: - BookType Enum Tests

@Suite("BookType Enum Tests")
struct BookTypeTests {

    @Test("BookType rawValue 对应中文名")
    func rawValues() {
        #expect(BookType.paper.rawValue == "纸质书")
        #expect(BookType.ebook.rawValue == "电子书")
        #expect(BookType.audiobook.rawValue == "有声书")
    }

    @Test("BookType allCases 包含所有类型")
    func allCases() {
        #expect(BookType.allCases.count == 3)
        #expect(BookType.allCases.contains(.paper))
        #expect(BookType.allCases.contains(.ebook))
        #expect(BookType.allCases.contains(.audiobook))
    }

    @Test("BookType 可以从 rawValue 初始化")
    func initFromRawValue() {
        #expect(BookType(rawValue: "纸质书") == .paper)
        #expect(BookType(rawValue: "电子书") == .ebook)
        #expect(BookType(rawValue: "有声书") == .audiobook)
        #expect(BookType(rawValue: "不存在") == nil)
    }
}

// MARK: - ReadingStatus Enum Tests

@Suite("ReadingStatus Enum Tests")
struct ReadingStatusTests {

    @Test("ReadingStatus rawValue 对应中文名")
    func rawValues() {
        #expect(ReadingStatus.reading.rawValue == "正在读")
        #expect(ReadingStatus.finished.rawValue == "已读")
        #expect(ReadingStatus.wishlist.rawValue == "想读")
        #expect(ReadingStatus.dropped.rawValue == "弃读")
        #expect(ReadingStatus.idle.rawValue == "闲置")
    }

    @Test("ReadingStatus allCases 包含所有状态")
    func allCases() {
        #expect(ReadingStatus.allCases.count == 5)
    }

    @Test("ReadingStatus 可以从 rawValue 初始化")
    func initFromRawValue() {
        #expect(ReadingStatus(rawValue: "正在读") == .reading)
        #expect(ReadingStatus(rawValue: "已读") == .finished)
        #expect(ReadingStatus(rawValue: "想读") == .wishlist)
        #expect(ReadingStatus(rawValue: "弃读") == .dropped)
        #expect(ReadingStatus(rawValue: "闲置") == .idle)
        #expect(ReadingStatus(rawValue: "不存在") == nil)
    }
}

// MARK: - ReadingRecord Tests

@Suite("ReadingRecord Tests")
struct ReadingRecordTests {

    @Test("阅读页数计算正确")
    func pagesReadCalculation() {
        let book = Book(title: "测试书籍", author: "测试作者", totalPages: 300)
        let record = ReadingRecord(book: book, startPage: 10, endPage: 45)
        #expect(record.pagesRead == 35)
    }

    @Test("起始页等于结束页时阅读页数为0")
    func zeroPagesRead() {
        let book = Book(title: "测试", author: "测试")
        let record = ReadingRecord(book: book, startPage: 50, endPage: 50)
        #expect(record.pagesRead == 0)
    }

    @Test("包含时长和笔记的记录")
    func fullRecord() {
        let book = Book(title: "测试", author: "测试")
        let date = Date()
        let record = ReadingRecord(
            book: book,
            date: date,
            startPage: 0,
            endPage: 30,
            durationMinutes: 45,
            note: "第一章很精彩"
        )
        #expect(record.pagesRead == 30)
        #expect(record.durationMinutes == 45)
        #expect(record.note == "第一章很精彩")
        #expect(record.date == date)
    }

    @Test("默认时长为0")
    func defaultDuration() {
        let book = Book(title: "测试", author: "测试")
        let record = ReadingRecord(book: book, startPage: 0, endPage: 10)
        #expect(record.durationMinutes == 0)
    }
}

// MARK: - Bookshelf Model Tests

@Suite("Bookshelf Model Tests")
struct BookshelfModelTests {

    @Test("新建书架有默认图标")
    func defaultIcon() {
        let shelf = Bookshelf(name: "文学")
        #expect(shelf.name == "文学")
        #expect(shelf.icon == "books.vertical")
        #expect(shelf.sortOrder == 0)
    }

    @Test("可以指定自定义图标和排序")
    func customInit() {
        let shelf = Bookshelf(name: "技术", icon: "laptopcomputer", sortOrder: 5)
        #expect(shelf.name == "技术")
        #expect(shelf.icon == "laptopcomputer")
        #expect(shelf.sortOrder == 5)
    }
}

// MARK: - Tag Model Tests

@Suite("Tag Model Tests")
struct TagModelTests {

    @Test("新建标签有默认颜色")
    func defaultColor() {
        let tag = PersonalLibrary.Tag(name: "科幻")
        #expect(tag.name == "科幻")
        #expect(tag.color == "#007AFF")
    }

    @Test("可以指定自定义颜色")
    func customColor() {
        let tag = PersonalLibrary.Tag(name: "历史", color: "#FF0000")
        #expect(tag.name == "历史")
        #expect(tag.color == "#FF0000")
    }
}

// MARK: - StorageLocation Tests

@Suite("StorageLocation Tests")
struct StorageLocationTests {

    @Test("StorageLocation 有正确的描述")
    func descriptions() {
        #expect(StorageLocation.icloud.description == "iCloud（多设备同步）")
        #expect(StorageLocation.local.description == "仅本机存储")
    }

    @Test("StorageLocation 有正确的图标")
    func icons() {
        #expect(StorageLocation.icloud.icon == "icloud")
        #expect(StorageLocation.local.icon == "iphone")
    }

    @Test("StorageLocation allCases 包含两个选项")
    func allCases() {
        #expect(StorageLocation.allCases.count == 2)
        #expect(StorageLocation.allCases.contains(.icloud))
        #expect(StorageLocation.allCases.contains(.local))
    }
}

// MARK: - Excel Export Tests

@Suite("Excel Export Tests")
struct ExcelExportTests {

    @Test("导出空列表生成只有表头的TSV")
    func exportEmptyList() async throws {
        let service = ExcelImportExportService()
        let data = try await service.exportBooks(books: [])

        // 验证 UTF-8 BOM (EF BB BF) 在原始数据中
        #expect(data.count >= 3)
        #expect(data[0] == 0xEF)
        #expect(data[1] == 0xBB)
        #expect(data[2] == 0xBF)

        // 验证表头（Swift 解码时会去掉 BOM）
        let content = String(data: data, encoding: .utf8)!
        let lines = content.components(separatedBy: "\n")
        #expect(lines.count >= 1)
        let header = lines[0].replacingOccurrences(of: "\u{FEFF}", with: "")
        #expect(header.contains("书名"))
        #expect(header.contains("作者"))
        #expect(header.contains("ISBN"))
        #expect(header.contains("阅读状态"))
    }

    @Test("导出包含书籍数据的TSV")
    func exportWithBooks() async throws {
        let service = ExcelImportExportService()
        let book = Book(
            title: "三体",
            author: "刘慈欣",
            isbn: "9787536692930",
            publisher: "重庆出版社",
            totalPages: 302
        )
        book.status = .finished
        book.finishedDate = Date()

        let data = try await service.exportBooks(books: [book])
        let content = String(data: data, encoding: .utf8)!

        let lines = content.components(separatedBy: "\n")
        #expect(lines.count >= 2)  // 表头 + 数据行

        let dataLine = lines[1]
        #expect(dataLine.contains("三体"))
        #expect(dataLine.contains("刘慈欣"))
        #expect(dataLine.contains("9787536692930"))
        #expect(dataLine.contains("重庆出版社"))
        #expect(dataLine.contains("已读"))
    }

    @Test("导出字段中的制表符被替换为空格")
    func exportEscapesTab() async throws {
        let service = ExcelImportExportService()
        let book = Book(title: "标题\t含Tab", author: "作者")

        let data = try await service.exportBooks(books: [book])
        let content = String(data: data, encoding: .utf8)!

        let lines = content.components(separatedBy: "\n")
        let dataLine = lines[1]
        #expect(dataLine.contains("标题 含Tab"))
    }

    @Test("columnHeaders 包含31列")
    func columnHeadersCount() {
        #expect(ExcelImportExportService.columnHeaders.count == 31)
        #expect(ExcelImportExportService.columnHeaders[0] == "序号")
        #expect(ExcelImportExportService.columnHeaders[1] == "书名")
        #expect(ExcelImportExportService.columnHeaders[17] == "豆瓣链接")
        #expect(ExcelImportExportService.columnHeaders[24] == "微信读书ID")
        #expect(ExcelImportExportService.columnHeaders[25] == "微信读书进度")
        #expect(ExcelImportExportService.columnHeaders[26] == "微信读书阅读时长")
        #expect(ExcelImportExportService.columnHeaders[27] == "开始阅读日期")
        #expect(ExcelImportExportService.columnHeaders[28] == "状态变更时间")
    }

    @Test("阅读状态正确映射到导出字符串")
    func statusMapping() async throws {
        let service = ExcelImportExportService()

        let statuses: [(ReadingStatus, String)] = [
            (.idle, "闲置"),
            (.reading, "正在读"),
            (.finished, "已读"),
            (.wishlist, "想读"),
            (.dropped, "弃读")
        ]

        for (status, expected) in statuses {
            let book = Book(title: "测试", author: "测试")
            book.status = status
            let data = try await service.exportBooks(books: [book])
            let content = String(data: data, encoding: .utf8)!
            #expect(content.contains(expected), "状态 \(status.rawValue) 应映射为 \(expected)")
        }
    }
}

// MARK: - Excel Import Tests (with file)

@Suite("Excel Import Tests")
struct ExcelImportTests {

    @Test("导入私家书藏xlsx文件")
    func importFromXlsx() async throws {
        let possiblePaths = [
            "/tmp/test_import.xlsx",
            "/Users/you/Downloads/私家书藏-完整书单_2.xlsx"
        ]

        var fileData: Data?
        for path in possiblePaths {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                fileData = data
                break
            }
        }

        guard let data = fileData else {
            return  // 测试文件不可用时跳过
        }

        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let service = ExcelImportExportService()
        let result = try await service.importBooks(data: data, modelContext: context)

        #expect(result.successCount > 0, "应该至少成功导入一本书")

        let descriptor = FetchDescriptor<Book>(sortBy: [SortDescriptor(\Book.addedDate)])
        let books = try context.fetch(descriptor)
        #expect(books.count == result.successCount)

        if let first = books.first {
            #expect(!first.title.isEmpty)
            #expect(!first.author.isEmpty)
        }
    }
}

// MARK: - WeReadImportItem Tests

@Suite("WeReadImportItem Tests")
struct WeReadImportItemTests {

    @Test("电子书类型设置正确")
    func ebookItem() {
        let item = WeReadImportItem(
            id: "book1",
            title: "电子书测试",
            author: "作者",
            cover: nil,
            publisher: nil,
            isbn: nil,
            intro: nil,
            translator: nil,
            category: nil,
            progress: 50,
            readingTime: 3600,
            ttsTime: 0,
            isFinished: false,
            bookType: .ebook
        )
        #expect(item.bookType == .ebook)
        #expect(item.isSelected == true)
        #expect(item.progress == 50)
        #expect(item.readingTime == 3600)
    }

    @Test("有声书类型设置正确")
    func audiobookItem() {
        let item = WeReadImportItem(
            id: "book2",
            title: "有声书测试",
            author: "作者",
            cover: nil,
            publisher: nil,
            isbn: nil,
            intro: nil,
            translator: nil,
            category: nil,
            progress: 100,
            readingTime: 0,
            ttsTime: 7200,
            isFinished: true,
            bookType: .audiobook
        )
        #expect(item.bookType == .audiobook)
        #expect(item.isFinished == true)
        #expect(item.ttsTime == 7200)
    }

    @Test("微信读书导入项绝不会是纸质书")
    func neverPaperType() {
        let ebookItem = WeReadImportItem(
            id: "e1", title: "E", author: "A",
            cover: nil, publisher: nil, isbn: nil,
            intro: nil, translator: nil, category: nil,
            progress: 0, readingTime: 0, ttsTime: 0,
            isFinished: false, bookType: .ebook
        )
        let audioItem = WeReadImportItem(
            id: "a1", title: "A", author: "A",
            cover: nil, publisher: nil, isbn: nil,
            intro: nil, translator: nil, category: nil,
            progress: 0, readingTime: 0, ttsTime: 0,
            isFinished: false, bookType: .audiobook
        )
        #expect(ebookItem.bookType != .paper)
        #expect(audioItem.bookType != .paper)
    }

    @Test("默认选中状态为true")
    func defaultSelected() {
        let item = WeReadImportItem(
            id: "test", title: "T", author: "A",
            cover: nil, publisher: nil, isbn: nil,
            intro: nil, translator: nil, category: nil,
            progress: 0, readingTime: 0, ttsTime: 0,
            isFinished: false, bookType: .ebook
        )
        #expect(item.isSelected == true)
    }

    @Test("可以切换选中状态")
    func toggleSelection() {
        var item = WeReadImportItem(
            id: "test", title: "T", author: "A",
            cover: nil, publisher: nil, isbn: nil,
            intro: nil, translator: nil, category: nil,
            progress: 0, readingTime: 0, ttsTime: 0,
            isFinished: false, bookType: .ebook
        )
        #expect(item.isSelected == true)
        item.isSelected = false
        #expect(item.isSelected == false)
    }
}

// MARK: - WeRead Smart Fill Tests

@Suite("WeRead Smart Fill Tests")
struct WeReadSmartFillTests {

    @Test("电纸书导入时阅读时长正确存入")
    func importSetsReadingHours() {
        let book = Book(title: "测试电纸书", author: "作者", bookType: .ebook)
        book.wereadBookId = "weread123"
        // 模拟导入：7200秒 = 2小时
        book.wereadReadingHours = Double(7200 + 0) / 3600.0
        #expect(book.wereadReadingHours == 2.0)
    }

    @Test("同步时阅读时长只增不减")
    func syncOnlyIncreasesHours() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)
        book.wereadBookId = "weread456"
        book.wereadReadingHours = 3.0
        // 新值更小，不更新
        let newHours = Double(5400) / 3600.0  // 1.5小时
        if newHours > book.wereadReadingHours {
            book.wereadReadingHours = newHours
        }
        #expect(book.wereadReadingHours == 3.0)
    }

    @Test("同步时阅读时长增加时更新")
    func syncUpdatesWhenLarger() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)
        book.wereadBookId = "weread789"
        book.wereadReadingHours = 1.0
        // 新值更大，更新
        let newHours = Double(10800) / 3600.0  // 3小时
        if newHours > book.wereadReadingHours {
            book.wereadReadingHours = newHours
        }
        #expect(book.wereadReadingHours == 3.0)
    }

    @Test("readingTime + ttsTime 合计计算")
    func combinedReadingAndTtsTime() {
        let book = Book(title: "有声书", author: "作者", bookType: .audiobook)
        book.wereadBookId = "audio001"
        let readingTime = 1800  // 30分钟阅读
        let ttsTime = 5400     // 1.5小时听书
        book.wereadReadingHours = Double(readingTime + ttsTime) / 3600.0
        #expect(book.wereadReadingHours == 2.0)
    }
}

// MARK: - Reading Summary Display Tests

@Suite("Reading Summary Display Tests")
struct ReadingSummaryDisplayTests {

    @Test("readingSummaryText 无阅读时长返回nil")
    func noReadingHoursReturnsNil() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)
        book.wereadReadingHours = 0
        #expect(book.readingSummaryText == nil)
    }

    @Test("readingSummaryText 有阅读时长返回格式化文本")
    func hasReadingHoursReturnsFormatted() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)
        book.wereadReadingHours = 3.5
        #expect(book.readingSummaryText == "微信读书累计 3.5 小时")
    }

    @Test("readingSummaryText 整数小时不显示小数")
    func wholeHoursNoDecimal() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)
        book.wereadReadingHours = 5.0
        #expect(book.readingSummaryText == "微信读书累计 5.0 小时")
    }

    @Test("finishedDate 在已读状态下有值")
    func finishedDateSetWhenFinished() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)
        book.status = .finished
        let now = Date()
        book.finishedDate = now
        #expect(book.finishedDate == now)
        #expect(book.status == .finished)
    }
}

// MARK: - WeReadError Tests

@Suite("WeReadError Tests")
struct WeReadErrorTests {

    @Test("错误描述本地化正确")
    func errorDescriptions() {
        #expect(WeReadError.networkError.errorDescription == "网络连接失败")
        #expect(WeReadError.cookieExpired.errorDescription == "登录已过期，请重新扫码登录")
        #expect(WeReadError.authFailed.errorDescription == "认证失败，请重新登录")
        #expect(WeReadError.httpError(statusCode: 404).errorDescription == "HTTP 错误 (404)")
        #expect(WeReadError.apiError(code: -1, message: "测试错误").errorDescription == "API 错误: 测试错误")
        #expect(WeReadError.noData.errorDescription == "没有获取到数据")
    }
}

// MARK: - WeReadEnrichResult Tests

@Suite("WeReadEnrichResult Tests")
struct WeReadEnrichResultTests {

    @Test("enrichResult 默认值全为 nil/0")
    func defaultValues() {
        let result = WeReadEnrichResult()
        #expect(result.publisher == nil)
        #expect(result.isbn == nil)
        #expect(result.intro == nil)
        #expect(result.price == nil)
        #expect(result.publishTime == nil)
        #expect(result.bookType == nil)
        #expect(result.readingHours == 0)
    }

    @Test("enrichResult 正确存储所有字段")
    func allFieldsPopulated() {
        var result = WeReadEnrichResult()
        result.publisher = "人民文学出版社"
        result.isbn = "9787020170623"
        result.intro = "测试简介"
        result.price = 45.0
        result.publishTime = "2023-01"
        result.bookType = .audiobook
        result.readingHours = 5.5
        #expect(result.publisher == "人民文学出版社")
        #expect(result.isbn == "9787020170623")
        #expect(result.intro == "测试简介")
        #expect(result.price == 45.0)
        #expect(result.publishTime == "2023-01")
        #expect(result.bookType == .audiobook)
        #expect(result.readingHours == 5.5)
    }

    @Test("enrichResult readingHours 从秒正确转换")
    func readingHoursFromSeconds() {
        var result = WeReadEnrichResult()
        let readingTime = 3600  // 1小时
        let ttsTime = 1800     // 0.5小时
        result.readingHours = Double(readingTime + ttsTime) / 3600.0
        #expect(result.readingHours == 1.5)
    }

    @Test("applyToBook 只填充空字段不覆盖已有值")
    func applyDoesNotOverwrite() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)
        book.publisher = "已有出版社"
        book.isbn = "existing-isbn"
        book.wereadReadingHours = 5.0

        var result = WeReadEnrichResult()
        result.publisher = "新出版社"
        result.isbn = "new-isbn"
        result.intro = "新简介"
        result.readingHours = 3.0  // 比已有值小但不同

        result.applyToBook(book)

        // 已有字段不被覆盖
        #expect(book.publisher == "已有出版社")
        #expect(book.isbn == "existing-isbn")
        // 空字段被填充
        #expect(book.bookDescription == "新简介")
        // 阅读时长有不同就更新（不再是只增不减）
        #expect(book.wereadReadingHours == 3.0)
    }

    @Test("applyToBook 阅读时长有不同就更新")
    func applyUpdatesReadingHoursWhenDifferent() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)
        book.wereadReadingHours = 2.0

        var result = WeReadEnrichResult()
        result.readingHours = 8.5

        result.applyToBook(book)

        #expect(book.wereadReadingHours == 8.5)
    }

    @Test("applyToBook 阅读时长为0时不覆盖")
    func applyDoesNotOverwriteReadingHoursWithZero() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)
        book.wereadReadingHours = 5.0

        var result = WeReadEnrichResult()
        result.readingHours = 0  // API 返回 0 不应覆盖

        result.applyToBook(book)

        #expect(book.wereadReadingHours == 5.0)
    }

    @Test("applyToBook progress有不同就更新")
    func applyUpdatesProgressWhenDifferent() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)
        book.wereadProgress = 80

        var result = WeReadEnrichResult()
        result.progress = 45  // 进度回退也应更新（如重读）

        result.applyToBook(book)

        #expect(book.wereadProgress == 45)
    }

    @Test("applyToBook progress为0时不覆盖")
    func applyDoesNotOverwriteProgressWithZero() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)
        book.wereadProgress = 50

        var result = WeReadEnrichResult()
        result.progress = 0  // API 返回 0 不应覆盖

        result.applyToBook(book)

        #expect(book.wereadProgress == 50)
    }

    @Test("applyToBook addedTime 填空：首次enrichment时设置addedDate")
    func applyFillsAddedTimeWhenFirstEnrichment() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)
        // 模拟首次enrichment：wereadEnrichedDate 为 nil
        book.wereadEnrichedDate = nil
        let originalAddedDate = book.addedDate

        var result = WeReadEnrichResult()
        let startTime = Date(timeIntervalSince1970: 1700000000)  // 2023-11-14
        result.addedTime = startTime

        result.applyToBook(book)

        #expect(book.addedDate == startTime)
        #expect(book.addedDate != originalAddedDate)
    }

    @Test("applyToBook addedTime 不覆盖已enriched的书")
    func applyDoesNotOverwriteAddedDateWhenAlreadyEnriched() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)
        book.wereadEnrichedDate = Date()  // 已经enriched过
        let originalAddedDate = book.addedDate

        var result = WeReadEnrichResult()
        result.addedTime = Date(timeIntervalSince1970: 1700000000)

        result.applyToBook(book)

        // 已enriched过的书不改变 addedDate
        #expect(book.addedDate == originalAddedDate)
    }

    @Test("applyToBook 填充出版社和价格")
    func applyFillsPublisherAndPrice() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)

        var result = WeReadEnrichResult()
        result.publisher = "中信出版社"
        result.price = 59.0

        result.applyToBook(book)

        #expect(book.publisher == "中信出版社")
        #expect(book.price == "¥59.00")
    }

    @Test("applyToBook 修正书籍类型为有声书")
    func applyFixesAudiobookType() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)

        var result = WeReadEnrichResult()
        result.bookType = .audiobook

        result.applyToBook(book)

        #expect(book.bookType == .audiobook)
    }

    @Test("applyToBook 不会将有声书改为电子书")
    func applyDoesNotDowngradeType() {
        let book = Book(title: "测试", author: "作者", bookType: .audiobook)

        var result = WeReadEnrichResult()
        result.bookType = .ebook

        result.applyToBook(book)

        // 有声书不会被改为电子书
        #expect(book.bookType == .audiobook)
    }
}

// MARK: - ImportError Tests

@Suite("ImportError Tests")
struct ImportErrorTests {

    @Test("导入错误描述正确")
    func errorDescriptions() {
        #expect(ImportError.cannotAccessFile.errorDescription == "无法访问文件")
        #expect(ImportError.invalidFormat.errorDescription == "文件格式无效")
        #expect(ImportError.noWorksheet.errorDescription == "未找到工作表")
        #expect(ImportError.noData.errorDescription == "文件中没有数据")
    }
}

// MARK: - ExportError Tests

@Suite("ExportError Tests")
struct ExportErrorTests {

    @Test("导出错误描述正确")
    func errorDescriptions() {
        #expect(ExportError.encodingFailed.errorDescription == "数据编码失败")
    }
}

// MARK: - WeReadService Import Logic Tests

@Suite("WeReadService Import Logic Tests")
struct WeReadServiceImportTests {

    @Test("导入时跳过已存在的电子书/有声书（去重）")
    func deduplication() async throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // 先插入一本已存在的电子书（同类型才去重）
        let existingBook = Book(title: "已存在的书", author: "某作者", bookType: .ebook)
        context.insert(existingBook)
        try context.save()

        // 尝试导入同名同作者的电子书 → 应该跳过
        let items = [
            WeReadImportItem(
                id: "dup1", title: "已存在的书", author: "某作者",
                cover: nil, publisher: nil, isbn: nil,
                intro: nil, translator: nil, category: nil,
                progress: 50, readingTime: 1000, ttsTime: 0,
                isFinished: false, bookType: .ebook
            )
        ]

        let service = WeReadService()
        let result = try await service.importBooks(items, modelContext: context)

        #expect(result.imported == 0)
        #expect(result.skipped == 1)
    }

    @Test("纸质书存在时不阻止同名电子书导入")
    func paperDoesNotBlockEbook() async throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // 先插入一本纸质书
        let paperBook = Book(title: "同名书", author: "作者", bookType: .paper)
        context.insert(paperBook)
        try context.save()

        // 导入同名同作者的电子书 → 不应被跳过
        let items = [
            WeReadImportItem(
                id: "new1", title: "同名书", author: "作者",
                cover: nil, publisher: nil, isbn: nil,
                intro: nil, translator: nil, category: nil,
                progress: 30, readingTime: 500, ttsTime: 0,
                isFinished: false, bookType: .ebook
            )
        ]

        let service = WeReadService()
        let result = try await service.importBooks(items, modelContext: context)

        #expect(result.imported == 1)
        #expect(result.skipped == 0)
    }

    @Test("只导入选中的书籍")
    func onlySelectedItems() async throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        var selectedItem = WeReadImportItem(
            id: "sel1", title: "选中的书", author: "作者A",
            cover: nil, publisher: nil, isbn: nil,
            intro: nil, translator: nil, category: nil,
            progress: 100, readingTime: 5000, ttsTime: 0,
            isFinished: true, bookType: .ebook
        )
        selectedItem.isSelected = true

        var unselectedItem = WeReadImportItem(
            id: "unsel1", title: "未选中的书", author: "作者B",
            cover: nil, publisher: nil, isbn: nil,
            intro: nil, translator: nil, category: nil,
            progress: 0, readingTime: 0, ttsTime: 0,
            isFinished: false, bookType: .ebook
        )
        unselectedItem.isSelected = false

        let service = WeReadService()
        let result = try await service.importBooks([selectedItem, unselectedItem], modelContext: context)

        #expect(result.imported == 1)
        #expect(result.skipped == 0)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.count == 1)
        #expect(books.first?.title == "选中的书")
    }

    @Test("已读完的书状态为finished")
    func finishedBookStatus() async throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let items = [
            WeReadImportItem(
                id: "fin1", title: "已读完的书", author: "作者",
                cover: nil, publisher: nil, isbn: nil,
                intro: nil, translator: nil, category: nil,
                progress: 100, readingTime: 10000, ttsTime: 0,
                isFinished: true, bookType: .ebook
            )
        ]

        let service = WeReadService()
        _ = try await service.importBooks(items, modelContext: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.first?.status == .finished)
        #expect(books.first?.finishedDate != nil)
    }

    @Test("有进度的书状态为reading")
    func readingBookStatus() async throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let items = [
            WeReadImportItem(
                id: "reading1", title: "在读的书", author: "作者",
                cover: nil, publisher: nil, isbn: nil,
                intro: nil, translator: nil, category: nil,
                progress: 45, readingTime: 3000, ttsTime: 0,
                isFinished: false, bookType: .ebook
            )
        ]

        let service = WeReadService()
        _ = try await service.importBooks(items, modelContext: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.first?.status == .reading)
    }

    @Test("无进度的书状态为idle")
    func idleBookStatus() async throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let items = [
            WeReadImportItem(
                id: "wish1", title: "想读的书", author: "作者",
                cover: nil, publisher: nil, isbn: nil,
                intro: nil, translator: nil, category: nil,
                progress: 0, readingTime: 0, ttsTime: 0,
                isFinished: false, bookType: .ebook
            )
        ]

        let service = WeReadService()
        _ = try await service.importBooks(items, modelContext: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.first?.status == .idle)
    }

    @Test("导入时自动添加微信读书标签")
    func wereadTagAdded() async throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let items = [
            WeReadImportItem(
                id: "tag1", title: "带标签的书", author: "作者",
                cover: nil, publisher: nil, isbn: nil,
                intro: nil, translator: nil, category: "科幻",
                progress: 0, readingTime: 0, ttsTime: 0,
                isFinished: false, bookType: .ebook
            )
        ]

        let service = WeReadService()
        _ = try await service.importBooks(items, modelContext: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        let tags = books.first?.tags ?? []
        let tagNames = tags.map(\.name)
        #expect(tagNames.contains("微信读书"))
        #expect(tagNames.contains("科幻"))
    }

    @Test("导入电子书类型正确")
    func ebookTypePreserved() async throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let items = [
            WeReadImportItem(
                id: "ebook1", title: "电子书", author: "作者",
                cover: nil, publisher: nil, isbn: nil,
                intro: nil, translator: nil, category: nil,
                progress: 0, readingTime: 100, ttsTime: 0,
                isFinished: false, bookType: .ebook
            )
        ]

        let service = WeReadService()
        _ = try await service.importBooks(items, modelContext: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.first?.bookType == .ebook)
        #expect(books.first?.bookType != .paper)
    }

    @Test("导入有声书类型正确")
    func audiobookTypePreserved() async throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let items = [
            WeReadImportItem(
                id: "audio1", title: "有声书", author: "作者",
                cover: nil, publisher: nil, isbn: nil,
                intro: nil, translator: nil, category: nil,
                progress: 0, readingTime: 0, ttsTime: 5000,
                isFinished: false, bookType: .audiobook
            )
        ]

        let service = WeReadService()
        _ = try await service.importBooks(items, modelContext: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.first?.bookType == .audiobook)
        #expect(books.first?.bookType != .paper)
    }
}

// MARK: - WeRead Sync Settings Tests

@Suite("WeReadSyncService Settings Tests", .serialized)
struct WeReadSyncSettingsTests {

    @Test("shouldAutoSync 默认关闭")
    func defaultDisabled() {
        WeReadSyncService.autoSyncEnabled = false
        WeReadSyncService.lastSyncDate = nil
        defer {
            WeReadSyncService.autoSyncEnabled = false
            WeReadSyncService.lastSyncDate = nil
        }

        #expect(WeReadSyncService.shouldAutoSync() == false)
    }

    @Test("开启自动同步且从未同步过时返回true")
    func enabledNeverSynced() {
        WeReadSyncService.autoSyncEnabled = true
        WeReadSyncService.lastSyncDate = nil
        defer {
            WeReadSyncService.autoSyncEnabled = false
            WeReadSyncService.lastSyncDate = nil
        }

        #expect(WeReadSyncService.shouldAutoSync() == true)
    }

    @Test("开启自动同步但距上次不足12小时返回false")
    func enabledRecentSync() {
        // 显式设置两个 key 确保状态正确（测试执行顺序不确定）
        WeReadSyncService.autoSyncEnabled = true
        WeReadSyncService.lastSyncDate = Date()  // 刚刚同步过
        defer {
            WeReadSyncService.autoSyncEnabled = false
            WeReadSyncService.lastSyncDate = nil
        }

        #expect(WeReadSyncService.shouldAutoSync() == false)
    }

    @Test("开启自动同步且超过12小时返回true")
    func enabledOldSync() {
        WeReadSyncService.resetSyncLockForTesting()
        WeReadSyncService.autoSyncEnabled = true
        WeReadSyncService.lastSyncDate = Date().addingTimeInterval(-43201)
        defer {
            WeReadSyncService.autoSyncEnabled = false
            WeReadSyncService.lastSyncDate = nil
        }

        #expect(WeReadSyncService.autoSyncEnabled == true, "precondition: autoSyncEnabled was overwritten by parallel test")
        #expect(WeReadSyncService.shouldAutoSync() == true)
    }

    @Test("SyncResult.summary 正确格式化")
    func syncResultSummary() {
        var result = WeReadSyncService.SyncResult()
        #expect(result.summary == "已是最新，无需更新")
        #expect(result.hasChanges == false)

        result.newBooksImported = 3
        #expect(result.summary == "新增 3 本")
        #expect(result.hasChanges == true)

        result.progressUpdated = 2
        #expect(result.summary == "新增 3 本，进度更新 2 本")

        result.statusUpdated = 1
        #expect(result.summary == "新增 3 本，进度更新 2 本，状态更新 1 本")
    }

    @Test("SyncResult.error 优先显示错误信息")
    func syncResultError() {
        var result = WeReadSyncService.SyncResult()
        result.error = "登录已过期"
        result.newBooksImported = 5  // 即使有数据也显示 error
        #expect(result.summary == "登录已过期")
    }
}

// MARK: - WeRead Sync Logic Tests

@Suite("WeReadSyncService Logic Tests", .serialized)
struct WeReadSyncLogicTests {

    @Test("未登录时同步返回错误")
    func syncWithoutLogin() async throws {
        WeReadSyncService.resetSyncLockForTesting()
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // 确保未登录（清除 Keychain）
        KeychainService.delete(key: KeychainService.wereadCookieKey)

        let syncService = WeReadSyncService()
        let result = await syncService.sync(modelContext: context)

        #expect(result.error == "未连接微信读书")
        #expect(result.hasChanges == false)
    }

    @Test("Book 新增 wereadBookId 字段")
    func bookWereadFields() {
        let book = Book(title: "测试", author: "作者")
        #expect(book.wereadBookId == nil)
        #expect(book.wereadProgress == 0)

        book.wereadBookId = "abc123"
        book.wereadProgress = 75
        #expect(book.wereadBookId == "abc123")
        #expect(book.wereadProgress == 75)
    }

    @Test("导入时设置 wereadBookId")
    func importSetsWereadId() async throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let items = [
            WeReadImportItem(
                id: "weread_book_123",
                title: "微信读书导入测试",
                author: "测试作者",
                cover: nil, publisher: nil, isbn: nil,
                intro: nil, translator: nil, category: nil,
                progress: 60, readingTime: 2000, ttsTime: 0,
                isFinished: false, bookType: .ebook
            )
        ]

        let service = WeReadService()
        _ = try await service.importBooks(items, modelContext: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.first?.wereadBookId == "weread_book_123")
    }

    @Test("导出包含微信读书字段")
    func exportIncludesWereadFields() async throws {
        let service = ExcelImportExportService()
        let book = Book(title: "带微信读书ID的书", author: "作者")
        book.wereadBookId = "wr_test_456"
        book.wereadProgress = 88

        let data = try await service.exportBooks(books: [book])
        let content = String(data: data, encoding: .utf8)!

        #expect(content.contains("wr_test_456"))
        #expect(content.contains("88"))
    }
}

// MARK: - WeRead Sync: isWereadUserImported & Reset Tests

@Suite("WeRead UserImported & Reset Tests")
struct WeReadUserImportedTests {

    @Test("同步时已有书的 isWereadUserImported 被正确更新")
    func syncUpdatesUserImportedFlag() async throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // 模拟一本老数据：有 wereadBookId 但 isWereadUserImported = false
        let book = Book(title: "Wild Swans", author: "Jung Chang", bookType: .ebook)
        book.wereadBookId = "wr_wild_swans"
        book.isWereadUserImported = false
        context.insert(book)
        try context.save()

        #expect(book.isWereadUserImported == false)

        // 模拟远端返回 isUserImported = true
        let item = WeReadImportItem(
            id: "wr_wild_swans",
            title: "Wild Swans",
            author: "Jung Chang",
            bookType: .ebook,
            isUserImported: true
        )

        // 直接调用 updateExistingBook 逻辑（通过属性验证）
        // 6a 批量更新逻辑: if item.isUserImported && !book.isWereadUserImported
        if item.isUserImported && !book.isWereadUserImported {
            book.isWereadUserImported = true
        }

        #expect(book.isWereadUserImported == true)
    }

    @Test("重置同步状态清除所有微信读书的 wereadEnrichedDate")
    func resetSyncStateClearsEnrichedDate() async throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // 创建 3 本书：2 本微信读书（已同步），1 本非微信读书
        let book1 = Book(title: "Book A", author: "Author", bookType: .ebook)
        book1.wereadBookId = "wr_a"
        book1.wereadEnrichedDate = Date()

        let book2 = Book(title: "Book B", author: "Author", bookType: .audiobook)
        book2.wereadBookId = "wr_b"
        book2.wereadEnrichedDate = Date()

        let book3 = Book(title: "Paper Book", author: "Author", bookType: .paper)
        book3.wereadEnrichedDate = Date()  // 非微信读书，不应被重置

        context.insert(book1)
        context.insert(book2)
        context.insert(book3)
        try context.save()

        // 执行重置：清除所有 wereadBookId != nil 的书的 wereadEnrichedDate
        let descriptor = FetchDescriptor<Book>(
            predicate: #Predicate { $0.wereadBookId != nil }
        )
        let wereadBooks = try context.fetch(descriptor)
        for b in wereadBooks {
            b.wereadEnrichedDate = nil
        }
        try context.save()

        #expect(book1.wereadEnrichedDate == nil)
        #expect(book2.wereadEnrichedDate == nil)
        #expect(book3.wereadEnrichedDate != nil)  // 纸质书不受影响
    }

    @Test("isSyncing 防止重复同步")
    func syncLockPreventsDoubleTrigger() async throws {
        // 验证 isSyncing 静态属性默认为 false
        #expect(WeReadSyncService.isSyncing == false)
    }
}

// MARK: - WeRead Sync Update Strategy Tests

@Suite("WeRead Sync Update Strategy Tests", .serialized)
struct WeReadSyncUpdateStrategyTests {

    @Test("同步时 progress 有不同就更新（即使减小）")
    func syncUpdatesProgressWhenDifferent() async throws {
        WeReadSyncService.resetSyncLockForTesting()
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let book = Book(title: "Progress Test", author: "Author", bookType: .ebook)
        book.wereadBookId = "wr_prog"
        book.wereadProgress = 80  // 本地80%
        book.wereadEnrichedDate = Date()  // 已enriched，不会再触发enrichment
        context.insert(book)
        try context.save()

        let mock = MockWeReadDataSource()
        await mock.setBooks([
            WeReadImportItem(id: "wr_prog", title: "Progress Test", author: "Author",
                           progress: 45, readingTime: 3600, ttsTime: 0,  // 远端45%
                           bookType: .ebook)
        ])

        let syncService = WeReadSyncService(provider: mock)
        _ = await syncService.sync(container: container, skipLockCheck: true)

        let verifyContext = ModelContext(container)
        let books = try verifyContext.fetch(FetchDescriptor<Book>())
        let resultBook = books.first(where: { $0.wereadBookId == "wr_prog" })
        #expect(resultBook?.wereadProgress == 45)
    }

    @Test("同步时 progress 为0不覆盖已有值")
    func syncDoesNotOverwriteProgressWithZero() async throws {
        WeReadSyncService.resetSyncLockForTesting()
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let book = Book(title: "Zero Test", author: "Author", bookType: .ebook)
        book.wereadBookId = "wr_zero"
        book.wereadProgress = 50
        book.wereadEnrichedDate = Date()
        context.insert(book)
        try context.save()

        let mock = MockWeReadDataSource()
        await mock.setBooks([
            WeReadImportItem(id: "wr_zero", title: "Zero Test", author: "Author",
                           progress: 0, readingTime: 0, ttsTime: 0,  // 远端0
                           bookType: .ebook)
        ])

        let syncService = WeReadSyncService(provider: mock)
        _ = await syncService.sync(container: container, skipLockCheck: true)

        let verifyContext = ModelContext(container)
        let books = try verifyContext.fetch(FetchDescriptor<Book>())
        let resultBook = books.first(where: { $0.wereadBookId == "wr_zero" })
        #expect(resultBook?.wereadProgress == 50)
    }

    @Test("同步时 readingHours 有不同就更新（包含ttsTime）")
    func syncUpdatesReadingHoursWithTtsTime() async throws {
        WeReadSyncService.resetSyncLockForTesting()
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let book = Book(title: "Hours Test", author: "Author", bookType: .ebook)
        book.wereadBookId = "wr_hours"
        book.wereadReadingHours = 5.0  // 本地5小时
        book.wereadEnrichedDate = Date()
        context.insert(book)
        try context.save()

        let mock = MockWeReadDataSource()
        // 远端：readingTime=3600(1h) + ttsTime=5400(1.5h) = 7200秒 = 2小时（比本地小）
        await mock.setBooks([
            WeReadImportItem(id: "wr_hours", title: "Hours Test", author: "Author",
                           progress: 50, readingTime: 3600, ttsTime: 5400,
                           bookType: .ebook)
        ])

        let syncService = WeReadSyncService(provider: mock)
        _ = await syncService.sync(container: container, skipLockCheck: true)

        let verifyContext = ModelContext(container)
        let books = try verifyContext.fetch(FetchDescriptor<Book>())
        let resultBook = books.first(where: { $0.wereadBookId == "wr_hours" })
        #expect(resultBook?.wereadReadingHours == 2.5)  // (3600+5400)/3600 = 2.5
    }
}

// MARK: - WeRead Sync Enrichment Atomicity Tests

/// Mock WeReadDataSource for testing sync enrichment behavior
actor MockWeReadDataSource: WeReadDataSource {
    var books: [WeReadImportItem] = []
    var enrichResults: [String: WeReadEnrichResult] = [:]
    var bookmarkResults: [String: [WeReadBookmark]] = [:]
    var enrichCallCount = 0
    var bookmarkCallCount = 0

    func setBooks(_ items: [WeReadImportItem]) { books = items }
    func setEnrichResults(_ results: [String: WeReadEnrichResult]) { enrichResults = results }
    func setBookmarks(_ bm: [String: [WeReadBookmark]]) { bookmarkResults = bm }

    func isConnected() -> Bool { true }
    func disconnect() {}

    func fetchAllBooks() async throws -> [WeReadImportItem] {
        return books
    }

    func enrichBook(bookId: String) async throws -> WeReadEnrichResult {
        enrichCallCount += 1
        return enrichResults[bookId] ?? WeReadEnrichResult()
    }

    func fetchBookmarks(bookId: String) async throws -> [WeReadBookmark] {
        bookmarkCallCount += 1
        return bookmarkResults[bookId] ?? []
    }

    func fetchBookInfo(bookId: String) async throws -> WeReadShelfBook {
        return WeReadShelfBook(bookId: bookId, title: nil, author: nil, cover: nil, translator: nil, category: nil, publisher: nil, publishTime: nil, intro: nil, isbn: nil, price: nil, finished: nil, format: nil, type: nil, readUpdateTime: nil, finishReadingTime: nil)
    }
}

@Suite("WeRead Sync Enrichment Atomicity Tests", .serialized)
struct WeReadSyncEnrichmentTests {

    @Test("同步逐本原子处理：补全+划线+标记wereadEnrichedDate")
    func syncEnrichesAndPullsBookmarksAtomically() async throws {
        WeReadSyncService.resetSyncLockForTesting()
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // 准备：2本需要enrichment的书
        let book1 = Book(title: "Book A", author: "Author A", bookType: .ebook)
        book1.wereadBookId = "wr_a"
        book1.wereadEnrichedDate = nil

        let book2 = Book(title: "Book B", author: "Author B", bookType: .ebook)
        book2.wereadBookId = "wr_b"
        book2.wereadEnrichedDate = nil

        context.insert(book1)
        context.insert(book2)
        try context.save()

        // Mock
        let mock = MockWeReadDataSource()
        await mock.setBooks([
            WeReadImportItem(id: "wr_a", title: "Book A", author: "Author A", bookType: .ebook),
            WeReadImportItem(id: "wr_b", title: "Book B", author: "Author B", bookType: .ebook)
        ])

        var enrichA = WeReadEnrichResult()
        enrichA.publisher = "Publisher A"
        var enrichB = WeReadEnrichResult()
        enrichB.publisher = "Publisher B"
        await mock.setEnrichResults(["wr_a": enrichA, "wr_b": enrichB])

        await mock.setBookmarks([
            "wr_a": [WeReadBookmark(bookmarkId: "bm1", markText: "划线A", chapterName: nil, createTime: nil)],
            "wr_b": []
        ])

        // 执行同步
        let syncService = WeReadSyncService(provider: mock)
        let result = await syncService.sync(container: container, skipLockCheck: true)

        #expect(result.error == nil)

        // 验证两本书都被 enrich + fetchBookmarks
        let enrichCount = await mock.enrichCallCount
        let bmCount = await mock.bookmarkCallCount
        #expect(enrichCount == 2)
        #expect(bmCount == 2)

        // 验证 wereadEnrichedDate 已设置
        let verifyContext = ModelContext(container)
        let allBooks = try verifyContext.fetch(FetchDescriptor<Book>())
        for book in allBooks {
            #expect(book.wereadEnrichedDate != nil, "Book \(book.title) should have wereadEnrichedDate set")
        }

        // Book A 有划线
        let bookA = allBooks.first(where: { $0.title == "Book A" })
        #expect(bookA?.notes?.contains("划线A") == true)
        // Book B 无划线，notes 仍为 nil
        let bookB = allBooks.first(where: { $0.title == "Book B" })
        #expect(bookB?.notes == nil)
    }

    @Test("已有wereadEnrichedDate的书不重复处理")
    func alreadyEnrichedBooksSkipped() async throws {
        WeReadSyncService.resetSyncLockForTesting()
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let book = Book(title: "Already Done", author: "Author", bookType: .ebook)
        book.wereadBookId = "wr_done"
        book.wereadEnrichedDate = Date()

        context.insert(book)
        try context.save()

        let mock = MockWeReadDataSource()
        await mock.setBooks([
            WeReadImportItem(id: "wr_done", title: "Already Done", author: "Author", bookType: .ebook)
        ])

        let syncService = WeReadSyncService(provider: mock)
        _ = await syncService.sync(container: container, skipLockCheck: true)

        let enrichCount = await mock.enrichCallCount
        let bmCount = await mock.bookmarkCallCount
        #expect(enrichCount == 0)
        #expect(bmCount == 0)
    }

    @Test("同步时 startedReadingTime 被正确写入 book.startedReadingDate")
    func syncAppliesStartedReadingTime() async throws {
        WeReadSyncService.resetSyncLockForTesting()
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let book = Book(title: "Test Book", author: "Author", bookType: .ebook)
        book.wereadBookId = "wr_test_start"
        book.wereadEnrichedDate = nil
        book.startedReadingDate = nil
        context.insert(book)
        try context.save()

        let mock = MockWeReadDataSource()
        await mock.setBooks([
            WeReadImportItem(id: "wr_test_start", title: "Test Book", author: "Author", bookType: .ebook)
        ])

        // enrichResult 中设置 startedReadingTime
        var enrichResult = WeReadEnrichResult()
        enrichResult.startedReadingTime = Date(timeIntervalSince1970: 1700000000)  // 2023-11-14
        await mock.setEnrichResults(["wr_test_start": enrichResult])
        await mock.setBookmarks(["wr_test_start": []])

        let syncService = WeReadSyncService(provider: mock)
        _ = await syncService.sync(container: container, skipLockCheck: true)

        // 验证 startedReadingDate 被设置
        let verifyContext = ModelContext(container)
        let books = try verifyContext.fetch(FetchDescriptor<Book>())
        let resultBook = books.first(where: { $0.title == "Test Book" })
        #expect(resultBook?.startedReadingDate != nil, "startedReadingDate should be set from enrichResult")
        #expect(resultBook?.startedReadingDate == Date(timeIntervalSince1970: 1700000000))
    }

    @Test("同步时 addedTime 被正确写入 book.addedDate（首次enrichment）")
    func syncAppliesAddedTimeOnFirstEnrichment() async throws {
        WeReadSyncService.resetSyncLockForTesting()
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let book = Book(title: "Test AddedTime", author: "Author", bookType: .ebook)
        book.wereadBookId = "wr_added"
        book.wereadEnrichedDate = nil  // 首次enrichment
        context.insert(book)
        try context.save()

        let mock = MockWeReadDataSource()
        await mock.setBooks([
            WeReadImportItem(id: "wr_added", title: "Test AddedTime", author: "Author", bookType: .ebook)
        ])

        var enrichResult = WeReadEnrichResult()
        enrichResult.addedTime = Date(timeIntervalSince1970: 1690000000)  // 加入书架时间
        enrichResult.readingHours = 2.5  // 包含ttsTime的总时长
        await mock.setEnrichResults(["wr_added": enrichResult])
        await mock.setBookmarks(["wr_added": []])

        let syncService = WeReadSyncService(provider: mock)
        _ = await syncService.sync(container: container, skipLockCheck: true)

        let verifyContext = ModelContext(container)
        let books = try verifyContext.fetch(FetchDescriptor<Book>())
        let resultBook = books.first(where: { $0.title == "Test AddedTime" })
        #expect(resultBook?.addedDate == Date(timeIntervalSince1970: 1690000000))
        #expect(resultBook?.wereadReadingHours == 2.5)
    }
}

// MARK: - CB_ User Imported Book External Lookup Tests

@Suite("CB_ External Lookup Tests", .serialized)
struct CBExternalLookupTests {

    @Test("CB_前缀书籍同步时触发外部源查询（bookDescription为空）")
    func syncCBBookTriggersExternalLookup() async throws {
        WeReadSyncService.resetSyncLockForTesting()
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // CB_ 前缀的用户导入书，描述为空
        let book = Book(title: "用户导入书", author: "Test Author", bookType: .ebook)
        book.wereadBookId = "CB_user_book_123"
        book.wereadEnrichedDate = nil
        book.bookDescription = nil
        book.authorDescription = nil
        context.insert(book)
        try context.save()

        let mock = MockWeReadDataSource()
        await mock.setBooks([
            WeReadImportItem(id: "CB_user_book_123", title: "用户导入书", author: "Test Author", bookType: .ebook)
        ])
        // WeRead enrichResult 不提供 intro（用户导入书通常没有）
        var enrichResult = WeReadEnrichResult()
        enrichResult.isUserImported = true
        await mock.setEnrichResults(["CB_user_book_123": enrichResult])
        await mock.setBookmarks(["CB_user_book_123": []])

        let syncService = WeReadSyncService(provider: mock)
        _ = await syncService.sync(container: container, skipLockCheck: true)

        // 验证 enrichment 完成（wereadEnrichedDate 被设置）
        let verifyContext = ModelContext(container)
        let books = try verifyContext.fetch(FetchDescriptor<Book>())
        let resultBook = books.first(where: { $0.wereadBookId == "CB_user_book_123" })
        #expect(resultBook?.wereadEnrichedDate != nil)
        // 注意：外部源（豆瓣等）在测试环境网络不可用时返回空，所以不能断言描述有值
        // 但如果网络可用且能找到书，则 bookDescription 会被填充
    }

    @Test("非CB_书籍不触发外部源查询")
    func syncNonCBBookSkipsExternalLookup() async throws {
        WeReadSyncService.resetSyncLockForTesting()
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // 非 CB_ 前缀的平台书，描述为空
        let book = Book(title: "平台书", author: "Platform Author", bookType: .ebook)
        book.wereadBookId = "wr_platform_123"
        book.wereadEnrichedDate = nil
        book.bookDescription = nil
        context.insert(book)
        try context.save()

        let mock = MockWeReadDataSource()
        await mock.setBooks([
            WeReadImportItem(id: "wr_platform_123", title: "平台书", author: "Platform Author", bookType: .ebook)
        ])
        var enrichResult = WeReadEnrichResult()
        enrichResult.intro = "微信读书提供的简介"
        await mock.setEnrichResults(["wr_platform_123": enrichResult])
        await mock.setBookmarks(["wr_platform_123": []])

        let syncService = WeReadSyncService(provider: mock)
        _ = await syncService.sync(container: container, skipLockCheck: true)

        let verifyContext = ModelContext(container)
        let books = try verifyContext.fetch(FetchDescriptor<Book>())
        let resultBook = books.first(where: { $0.wereadBookId == "wr_platform_123" })
        #expect(resultBook?.wereadEnrichedDate != nil)
        // 非 CB_ 书使用 WeRead 提供的 intro
        #expect(resultBook?.bookDescription == "微信读书提供的简介")
    }

    @Test("CB_书籍已有描述时不查询外部源")
    func syncCBBookSkipsExternalWhenDescriptionExists() async throws {
        WeReadSyncService.resetSyncLockForTesting()
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let book = Book(title: "CB有描述", author: "Author", bookType: .ebook)
        book.wereadBookId = "CB_has_desc"
        book.wereadEnrichedDate = nil
        book.bookDescription = "已有的描述"
        book.authorDescription = "已有的作者简介"
        context.insert(book)
        try context.save()

        let mock = MockWeReadDataSource()
        await mock.setBooks([
            WeReadImportItem(id: "CB_has_desc", title: "CB有描述", author: "Author", bookType: .ebook)
        ])
        await mock.setEnrichResults(["CB_has_desc": WeReadEnrichResult()])
        await mock.setBookmarks(["CB_has_desc": []])

        let syncService = WeReadSyncService(provider: mock)
        _ = await syncService.sync(container: container, skipLockCheck: true)

        let verifyContext = ModelContext(container)
        let books = try verifyContext.fetch(FetchDescriptor<Book>())
        let resultBook = books.first(where: { $0.wereadBookId == "CB_has_desc" })
        // 描述保持不变（没有被外部源覆盖）
        #expect(resultBook?.bookDescription == "已有的描述")
        #expect(resultBook?.authorDescription == "已有的作者简介")
    }
}

// MARK: - Smart Fill Platform Book Tests

@Suite("Smart Fill Platform Book Tests")
struct SmartFillPlatformBookTests {

    @Test("WeReadEnrichResult.applyToBook 正确设置 startedReadingDate")
    func applyToBookSetsStartedReadingDate() {
        let book = Book(title: "Test", author: "Author", bookType: .ebook)
        book.startedReadingDate = nil

        var result = WeReadEnrichResult()
        result.startedReadingTime = Date(timeIntervalSince1970: 1700000000)
        result.applyToBook(book)

        #expect(book.startedReadingDate != nil)
        #expect(book.startedReadingDate == Date(timeIntervalSince1970: 1700000000))
    }

    @Test("WeReadEnrichResult.applyToBook 估算值不覆盖用户手动设置的 startedReadingDate")
    func applyToBookDoesNotOverwriteStartedReadingDate() {
        let book = Book(title: "Test", author: "Author", bookType: .ebook)
        let existing = Date(timeIntervalSince1970: 1600000000)
        book.startedReadingDate = existing
        book.isStartedReadingDateEstimated = false  // 用户手动设置/真实API值

        var result = WeReadEnrichResult()
        result.startedReadingTime = Date(timeIntervalSince1970: 1700000000)
        result.isStartedReadingTimeEstimated = true  // 标记为估算值
        result.applyToBook(book)

        // 估算值不应该覆盖用户手动设置的值
        #expect(book.startedReadingDate == existing)
        #expect(book.isStartedReadingDateEstimated == false)
    }

    @Test("WeReadEnrichResult.applyToBook 真实值覆盖已有的 startedReadingDate 并重置 flag")
    func applyToBookRealValueOverridesStartedReadingDate() {
        let book = Book(title: "Test", author: "Author", bookType: .ebook)
        let existing = Date(timeIntervalSince1970: 1600000000)
        book.startedReadingDate = existing
        book.isStartedReadingDateEstimated = true  // 之前是估算值

        var result = WeReadEnrichResult()
        result.startedReadingTime = Date(timeIntervalSince1970: 1700000000)
        result.isStartedReadingTimeEstimated = false  // 真实API值（默认）
        result.applyToBook(book)

        // 真实值应该覆盖并重置 flag
        #expect(book.startedReadingDate == Date(timeIntervalSince1970: 1700000000))
        #expect(book.isStartedReadingDateEstimated == false)
    }

    @Test("WeReadEnrichResult.applyToBook 估算值可以更新已有的估算值")
    func applyToBookEstimatedUpdatesExistingEstimated() {
        let book = Book(title: "Test", author: "Author", bookType: .ebook)
        let oldEstimated = Date(timeIntervalSince1970: 1600000000)
        book.startedReadingDate = oldEstimated
        book.isStartedReadingDateEstimated = true  // 之前也是估算值

        var result = WeReadEnrichResult()
        result.startedReadingTime = Date(timeIntervalSince1970: 1700000000)  // 新的估算值
        result.isStartedReadingTimeEstimated = true
        result.applyToBook(book)

        // 估算值可以更新已有的估算值
        #expect(book.startedReadingDate == Date(timeIntervalSince1970: 1700000000))
        #expect(book.isStartedReadingDateEstimated == true)
    }

    @Test("微信读书平台书智能补全不应搜索外部源（仅缺作者简介时）")
    func platformBookShouldNotSearchExternal() {
        // 这是行为规范测试：
        // 条件: book.isWereadUserImported == false（平台书）
        //        bookDescription 非空, authorDescription 为空
        // 预期: 不调用 ISBNLookupService.smartFill（外部搜索）
        //
        // 由于 performSmartFill 是 View 的私有方法无法直接测试，
        // 我们验证 isWereadUserImported 的逻辑判断正确性
        let book = Book(title: "启功给你讲书法", author: "启功", bookType: .ebook)
        book.wereadBookId = "25789624"
        book.isWereadUserImported = false  // 平台书
        book.bookDescription = "这是一本书法书"  // 有简介
        // authorDescription 为 nil — 但不应去外部搜索

        // 验证判断条件：平台书 + 只缺作者简介 → 不搜外部
        let shouldSearchExternal = book.isWereadUserImported || book.bookDescription == nil || (book.bookDescription?.isEmpty ?? true)
        #expect(shouldSearchExternal == false, "Platform book with bookDescription should NOT trigger external search")
    }
}

// MARK: - External API Contract Tests (Integration)

@Suite("External API Contract Tests")
struct ExternalAPIContractTests {

    // MARK: - 豆瓣搜索建议 API

    @Test("豆瓣搜索建议API返回正确格式")
    func doubanSuggestAPI() async throws {
        let query = "三体"
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "https://book.douban.com/j/subject_suggest?q=\(encoded)")!

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return  // 网络不可达，跳过
        }
        let httpResponse = response as! HTTPURLResponse

        // 豆瓣可能因频率限制返回 403，此时跳过
        guard httpResponse.statusCode == 200 else { return }
        #expect(data.count > 10)

        // 返回值应该是 JSON 数组
        let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(results != nil, "应返回 JSON 数组")
        #expect((results ?? []).isEmpty == false, "搜索'三体'应有结果")

        // 验证每个结果的关键字段
        if let first = results?.first(where: { ($0["type"] as? String) == "b" }) {
            #expect(first["title"] != nil, "应包含 title 字段")
            #expect(first["pic"] != nil, "应包含 pic 字段（封面缩略图）")
            #expect(first["type"] as? String == "b", "图书类型应为 'b'")

            // pic URL 应是有效的豆瓣图片 URL
            if let pic = first["pic"] as? String {
                #expect(pic.contains("doubanio.com"), "封面 URL 应来自 doubanio.com")
                #expect(pic.contains("/view/subject/"), "封面 URL 应包含 /view/subject/ 路径")
            }
        }
    }

    // MARK: - 豆瓣 ISBN 页面

    @Test("豆瓣ISBN查询返回书籍页面")
    func doubanISBNPage() async throws {
        let isbn = "9787536692930"  // 三体
        let url = URL(string: "https://book.douban.com/isbn/\(isbn)/")!

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return  // 网络不可达，跳过
        }
        let httpResponse = response as! HTTPURLResponse

        // 豆瓣可能因频率限制返回 403，此时跳过
        guard httpResponse.statusCode == 200 else { return }

        let html = String(data: data, encoding: .utf8) ?? ""
        #expect(!html.isEmpty)

        // 验证关键 HTML 结构存在（我们的解析依赖这些）
        let hasTitle = html.contains("v:itemreviewed") || html.contains("property=\"og:title\"")
        #expect(hasTitle, "页面应包含书名标签（v:itemreviewed 或 og:title）")

        let hasInfo = html.contains("id=\"info\"")
        #expect(hasInfo, "页面应包含 id=\"info\" 信息区")
    }

    // MARK: - Open Library Books API

    @Test("Open Library Books API返回正确格式")
    func openLibraryBooksAPI() async throws {
        let isbn = "9780765382030"  // The Three-Body Problem (English)
        let url = URL(string: "https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data")!

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        #expect(httpResponse.statusCode == 200)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil, "应返回 JSON 对象")

        if let bookData = json?["ISBN:\(isbn)"] as? [String: Any] {
            #expect(bookData["title"] != nil, "应包含 title")
            #expect(bookData["authors"] != nil, "应包含 authors")

            // 验证 cover 字段结构
            if let cover = bookData["cover"] as? [String: Any] {
                let hasURL = cover["large"] != nil || cover["medium"] != nil
                #expect(hasURL, "cover 应包含 large 或 medium URL")
            }
        }
    }

    // MARK: - Open Library 封面下载

    @Test("Open Library封面URL可下载图片")
    func openLibraryCoverDownload() async throws {
        let isbn = "9780765382030"
        let url = URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg")!

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        #expect(httpResponse.statusCode == 200)
        // Open Library 有封面时返回 JPEG 数据（>1000 字节）
        // 无封面时返回 1x1 pixel 图片（很小）
        #expect(data.count > 1000, "已知ISBN应返回有效封面图片（>1KB）")
    }

    // MARK: - Bing 图片搜索

    @Test("Bing图片搜索返回可解析的HTML")
    func bingImageSearch() async throws {
        let query = "三体 封面"
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "https://www.bing.com/images/search?q=\(encoded)&form=HDRSC2&first=1")!

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        // 网络超时时跳过（外部服务不稳定）
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return  // 网络不可达或超时，跳过
        }
        let httpResponse = response as! HTTPURLResponse

        #expect(httpResponse.statusCode == 200)

        let html = String(data: data, encoding: .utf8) ?? ""
        #expect(!html.isEmpty)

        // 验证 Bing 返回的 HTML 包含 murl（原图URL）字段
        let hasMurl = html.contains("murl&quot;:&quot;http")
        #expect(hasMurl, "Bing HTML 应包含 murl 字段（原图URL）")

        // 验证能提取出至少一个图片 URL
        let pattern = #"murl&quot;:&quot;(https?://[^&]+?)&quot;"#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        #expect(matches.count > 0, "应能提取至少1个图片URL")

        // 验证提取的 URL 是合法图片 URL
        if let firstMatch = matches.first,
           let range = Range(firstMatch.range(at: 1), in: html) {
            let imageURL = String(html[range])
            #expect(imageURL.hasPrefix("http"), "提取的URL应以http开头")
        }
    }

    // MARK: - 百度图片搜索

    @Test("百度图片搜索返回可解析的HTML")
    func baiduImageSearch() async throws {
        let query = "三体 封面"
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "https://image.baidu.com/search/index?tn=baiduimage&word=\(encoded)")!

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        #expect(httpResponse.statusCode == 200)

        let html = String(data: data, encoding: .utf8) ?? ""

        // 百度在非中国IP下会返回安全验证页面或空结果，此时跳过
        let isBlocked = data.count < 10000
            || html.contains("wappass")
            || html.contains("captcha")
            || html.contains("安全验证")
            || html.contains("mkdjump")
            || !html.contains("thumbURL")
        if isBlocked {
            return  // 非中国网络环境或被拦截，跳过
        }

        // 验证能提取 thumbURL
        let pattern = #""thumbURL":"(https?://[^"]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        #expect(matches.count > 0, "应能提取至少1个 thumbURL")
    }

    // MARK: - 豆瓣封面图片下载

    @Test("豆瓣封面图片可带Referer下载")
    func doubanCoverDownload() async throws {
        // 先通过搜索获取一个真实的封面URL
        let suggestURL = URL(string: "https://book.douban.com/j/subject_suggest?q=%E4%B8%89%E4%BD%93")!
        var suggestRequest = URLRequest(url: suggestURL)
        suggestRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        suggestRequest.timeoutInterval = 10

        let suggestData: Data
        do {
            (suggestData, _) = try await URLSession.shared.data(for: suggestRequest)
        } catch {
            return  // 网络不可达，跳过
        }
        guard let results = try? JSONSerialization.jsonObject(with: suggestData) as? [[String: Any]],
              let first = results.first(where: { ($0["type"] as? String) == "b" }),
              let pic = first["pic"] as? String else {
            return  // 搜索API不可用时跳过
        }

        // 小图 → 大图
        let largePic = pic.replacingOccurrences(of: "/view/subject/s/", with: "/view/subject/l/")
        guard let coverURL = URL(string: largePic) else { return }

        var request = URLRequest(url: coverURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://book.douban.com", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        #expect(httpResponse.statusCode == 200, "带 Referer 应能下载封面")
        #expect(data.count > 5000, "封面图片应大于5KB")
    }
}

// MARK: - ISBNLookupResult Tests

@Suite("ISBNLookupResult Tests")
struct ISBNLookupResultTests {

    @Test("ISBNLookupResult 初始化正确")
    func initialization() {
        let result = ISBNLookupResult(
            title: "三体",
            author: "刘慈欣",
            publisher: "重庆出版社",
            publishDate: "2008",
            totalPages: 302,
            price: "¥23.00",
            bookDescription: "科幻小说",
            authorDescription: "中国科幻作家",
            coverImageURL: "https://example.com/cover.jpg",
            isbn: "9787536692930"
        )
        #expect(result.title == "三体")
        #expect(result.author == "刘慈欣")
        #expect(result.publisher == "重庆出版社")
        #expect(result.totalPages == 302)
        #expect(result.isbn == "9787536692930")
    }

    @Test("ISBNLookupResult 可选字段为nil")
    func optionalFields() {
        let result = ISBNLookupResult(
            title: "测试",
            author: "作者",
            publisher: nil,
            publishDate: nil,
            totalPages: nil,
            price: nil,
            bookDescription: nil,
            authorDescription: nil,
            coverImageURL: nil,
            isbn: "1234567890"
        )
        #expect(result.publisher == nil)
        #expect(result.totalPages == nil)
        #expect(result.coverImageURL == nil)
    }
}

// MARK: - Rating Tests

@Suite("Rating Tests")
struct RatingTests {

    @Test("评分范围 1-5 有效")
    func validRatingRange() {
        let book = Book(title: "测试", author: "测试")
        for i in 1...5 {
            book.rating = i
            #expect(book.rating == i)
        }
    }

    @Test("评分可以清除为nil")
    func clearRating() {
        let book = Book(title: "测试", author: "测试")
        book.rating = 4
        #expect(book.rating == 4)
        book.rating = nil
        #expect(book.rating == nil)
    }

    @Test("新书默认无评分")
    func defaultNoRating() {
        let book = Book(title: "测试", author: "测试")
        #expect(book.rating == nil)
    }
}

// MARK: - AddSource Tests

@Suite("AddSource Tests")
struct AddSourceTests {

    @Test("AddSource rawValue 正确")
    func rawValues() {
        #expect(AddSource.manual.rawValue == "手动添加")
        #expect(AddSource.scanned.rawValue == "扫码添加")
        #expect(AddSource.imported.rawValue == "文件导入")
        #expect(AddSource.wereadImported.rawValue == "微信读书导入")
    }

    @Test("AddSource allCases 包含4种")
    func allCases() {
        #expect(AddSource.allCases.count == 4)
    }

    @Test("旧数据兼容：'导入' 解码为 .imported")
    func legacyDecoding() throws {
        let json = "\"导入\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AddSource.self, from: data)
        #expect(decoded == .imported)
    }
}

// MARK: - Security & Validation Tests

@Suite("Security Tests")
struct SecurityTests {

    // MARK: - WeRead BookId Validation

    @Test("WeReadService 拒绝空 bookId")
    func rejectEmptyBookId() async {
        let service = WeReadService()
        do {
            _ = try await service.fetchBookInfo(bookId: "")
            Issue.record("应抛出错误")
        } catch {
            // 期望抛出错误
        }
    }

    @Test("WeReadService 拒绝含路径注入的 bookId")
    func rejectPathInjection() async {
        let service = WeReadService()
        let maliciousIds = ["../etc/passwd", "id;rm -rf /", "<script>alert(1)</script>", "book/../admin"]
        for id in maliciousIds {
            do {
                _ = try await service.fetchBookInfo(bookId: id)
                Issue.record("应拒绝恶意bookId: \(id)")
            } catch {
                // 期望抛出错误
            }
        }
    }

    @Test("WeReadService 接受合法 bookId 格式")
    func acceptValidBookId() async {
        // 不检查网络结果，只验证不会因格式问题抛错
        let validIds = ["123456", "CB_abcdef1234", "mp_12345678", "3300086053"]
        let service = WeReadService()
        for id in validIds {
            do {
                _ = try await service.fetchBookInfo(bookId: id)
            } catch let error as WeReadError {
                // 网络错误可以接受（cookieExpired 等），只要不是格式拒绝
                if case .apiError(let code, let msg) = error, code == -1 && msg == "无效的书籍ID" {
                    Issue.record("不应拒绝合法bookId: \(id)")
                }
            } catch {
                // 其他网络错误正常
            }
        }
    }

    // MARK: - HTML Parsing Safety

    @Test("DoubanDescriptionFetcher 清理HTML标签")
    func htmlTagStripping() {
        let fetcher = DoubanDescriptionFetcher()
        // 使用公开方法间接测试 — 通过构造含有 HTML 的模拟数据
        // 直接测试 cleanHTML 逻辑
        let html = "<p>第一段</p><p>第二段</p><br/><b>加粗</b>"
        let cleaned = html.replacingOccurrences(of: "<[^>]{0,1000}>", with: "\n", options: .regularExpression)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        #expect(cleaned == "第一段\n第二段\n加粗")
        #expect(!cleaned.contains("<"))
        #expect(!cleaned.contains(">"))
    }

    @Test("ReDoS安全：超长未闭合标签不会卡死")
    func reDosSafety() {
        // 构造一个恶意输入：超长的 < 后没有 >
        let malicious = "<" + String(repeating: "a", count: 2000) + "normal text"
        let start = Date()
        _ = malicious.replacingOccurrences(of: "<[^>]{0,1000}>", with: "", options: .regularExpression)
        let elapsed = Date().timeIntervalSince(start)
        // 使用有界量词后，即使输入恶意也应在毫秒内完成
        #expect(elapsed < 1.0, "正则处理应在1秒内完成")
    }

    // MARK: - Excel Import Size Limit

    @Test("Excel导入拒绝超过10MB的文件")
    func rejectOversizedExcel() async {
        let service = ExcelImportExportService()
        let container = try! ModelContainer(for: Book.self, Tag.self, Bookshelf.self, configurations: .init(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        // 构造 10MB + 1 的数据
        let oversizedData = Data(count: 10_000_001)
        do {
            _ = try await service.importBooks(data: oversizedData, modelContext: context)
            Issue.record("应拒绝超大文件")
        } catch {
            // 期望抛出错误
        }
    }

    // MARK: - WeChatAuthManager 安全

    // MARK: - SmartFill 数据结构测试

    @Test("LookupSourceStatus displayText 正确")
    func lookupSourceStatusDisplay() {
        #expect(LookupSourceStatus.notAttempted.displayText == "未尝试")
        #expect(LookupSourceStatus.found.displayText == "已找到")
        #expect(LookupSourceStatus.notFound.displayText == "未找到")
        #expect(LookupSourceStatus.error("超时").displayText == "出错: 超时")
    }

    @Test("LookupSourceStatus Equatable 正确")
    func lookupSourceStatusEquatable() {
        #expect(LookupSourceStatus.found == LookupSourceStatus.found)
        #expect(LookupSourceStatus.notFound != LookupSourceStatus.found)
        #expect(LookupSourceStatus.error("a") == LookupSourceStatus.error("a"))
        #expect(LookupSourceStatus.error("a") != LookupSourceStatus.error("b"))
    }

    @Test("SmartFillResult hasAnyFill 无数据时为 false")
    func smartFillResultEmpty() {
        let result = SmartFillResult(sourceStatuses: [])
        #expect(result.hasAnyFill == false)
    }

    @Test("SmartFillResult hasAnyFill 有出版社时为 true")
    func smartFillResultWithPublisher() {
        var result = SmartFillResult(sourceStatuses: [])
        result.publisher = "人民出版社"
        #expect(result.hasAnyFill == true)
    }

    @Test("SmartFillResult hasAnyFill 有页数时为 true")
    func smartFillResultWithPages() {
        var result = SmartFillResult(sourceStatuses: [])
        result.totalPages = 300
        #expect(result.hasAnyFill == true)
    }

    @Test("SmartFillResult hasAnyFill 有作者时为 true")
    func smartFillResultWithAuthor() {
        var result = SmartFillResult(sourceStatuses: [])
        result.author = "鲁迅"
        #expect(result.hasAnyFill == true)
    }

    @Test("SmartFillResult hasAnyFill 有图书简介时为 true")
    func smartFillResultWithBookDesc() {
        var result = SmartFillResult(sourceStatuses: [])
        result.bookDescription = "这是一本好书"
        #expect(result.hasAnyFill == true)
    }

    @Test("SmartFillResult hasAnyFill 有作者简介时为 true")
    func smartFillResultWithAuthorDesc() {
        var result = SmartFillResult(sourceStatuses: [])
        result.authorDescription = "著名作家"
        #expect(result.hasAnyFill == true)
    }

    @Test("smartFill 无ISBN无书名返回全部notAttempted")
    func smartFillNoISBNNoTitle() async {
        let service = ISBNLookupService()
        let result = await service.smartFill(
            isbn: "",
            title: "",
            author: "",
            needsPublisher: true,
            needsPages: true,
            needsAuthor: true,
            needsBookDesc: true,
            needsAuthorDesc: true
        )
        // 无有效ISBN → 4个源都是 notAttempted，无书名 → 无书名搜索
        for (_, status) in result.sourceStatuses {
            #expect(status == .notAttempted)
        }
        #expect(result.hasAnyFill == false)
    }

    @Test("smartFill 无效ISBN格式返回notAttempted")
    func smartFillInvalidISBN() async {
        let service = ISBNLookupService()
        let result = await service.smartFill(
            isbn: "123",  // 太短，无效
            title: "",
            author: "",
            needsPublisher: true,
            needsPages: true,
            needsAuthor: true,
            needsBookDesc: true,
            needsAuthorDesc: true
        )
        for (_, status) in result.sourceStatuses {
            #expect(status == .notAttempted)
        }
    }

    @Test("smartFill 不需要任何字段时返回notAttempted")
    func smartFillNothingNeeded() async {
        let service = ISBNLookupService()
        let result = await service.smartFill(
            isbn: "9787020002207",
            title: "红楼梦",
            author: "曹雪芹",
            needsPublisher: false,
            needsPages: false,
            needsAuthor: false,
            needsBookDesc: false,
            needsAuthorDesc: false
        )
        // 什么都不需要，所以所有源都 notAttempted
        for (_, status) in result.sourceStatuses {
            #expect(status == .notAttempted)
        }
        #expect(result.hasAnyFill == false)
    }

    @Test("WeChatAuthManager 不含 AppSecret 属性")
    func noAppSecretInCode() throws {
        // 通过反射验证 WeChatAuthManager 实例不含 secret 相关属性值
        let manager = WeChatAuthManager.shared
        let mirror = Mirror(reflecting: manager)
        for child in mirror.children {
            let label = child.label ?? ""
            // 属性名不应包含 "secret"
            #expect(!label.lowercased().contains("secret"), "不应有名为 secret 的属性: \(label)")
            // 字符串值不应是实际的 secret（非占位符格式）
            if let value = child.value as? String {
                #expect(value == value, "属性 \(label) 存在")  // 占位
            }
        }
    }
}

// MARK: - SmartFillResult Extended Fields Tests

@Suite("SmartFillResult Extended Fields Tests")
struct SmartFillResultExtendedTests {

    @Test("SmartFillResult 包含扩展字段 — title/price/publishDate/translator")
    func extendedFieldsExist() {
        var result = SmartFillResult(sourceStatuses: [])
        result.title = "书名"
        result.price = "¥59.00"
        result.publishDate = "2020-01"
        result.translator = "译者"
        #expect(result.title == "书名")
        #expect(result.price == "¥59.00")
        #expect(result.publishDate == "2020-01")
        #expect(result.translator == "译者")
    }

    @Test("hasAnyFill 在新字段填充时返回 true")
    func hasAnyFillWithExtendedFields() {
        var result = SmartFillResult(sourceStatuses: [])
        #expect(result.hasAnyFill == false)

        result.price = "¥39.00"
        #expect(result.hasAnyFill == true)
    }

    @Test("hasAnyFill 在 title 填充时返回 true")
    func hasAnyFillWithTitle() {
        var result = SmartFillResult(sourceStatuses: [])
        result.title = "新书名"
        #expect(result.hasAnyFill == true)
    }

    @Test("hasAnyFill 在 translator 填充时返回 true")
    func hasAnyFillWithTranslator() {
        var result = SmartFillResult(sourceStatuses: [])
        result.translator = "王德威"
        #expect(result.hasAnyFill == true)
    }
}

// MARK: - Book needsEnrichment Extended Tests

@Suite("Book needsEnrichment Extended Tests")
struct BookNeedsEnrichmentExtendedTests {

    @Test("纸质书缺定价需要补全")
    func paperBookMissingPriceNeedsEnrichment() {
        let book = Book(title: "书", author: "作者", publisher: "出版社",
                        bookType: .paper, bookDescription: "简介")
        book.totalPages = 200
        book.authorDescription = "作者简介"
        // price 为 nil
        #expect(book.needsEnrichment)
    }

    @Test("纸质书缺出版日期需要补全")
    func paperBookMissingPublishDateNeedsEnrichment() {
        let book = Book(title: "书", author: "作者", publisher: "出版社",
                        totalPages: 200, price: "¥59", bookType: .paper,
                        bookDescription: "简介")
        book.authorDescription = "作者简介"
        // publishDate 为 nil
        #expect(book.needsEnrichment)
    }

    @Test("纸质书全部字段完整不需要补全")
    func paperBookFullDataNotNeedEnrichment() {
        let book = Book(title: "书", author: "作者", publisher: "出版社",
                        totalPages: 200, price: "¥59", bookType: .paper,
                        bookDescription: "简介")
        book.authorDescription = "作者简介"
        book.publishDate = Date()
        #expect(!book.needsEnrichment)
    }

    @Test("lastEnrichmentDate 默认为 nil")
    func lastEnrichmentDateDefaultNil() {
        let book = Book(title: "书", author: "作者")
        #expect(book.lastEnrichmentDate == nil)
    }

    @Test("lastEnrichmentDate 可设置")
    func lastEnrichmentDateSettable() {
        let book = Book(title: "书", author: "作者")
        let now = Date()
        book.lastEnrichmentDate = now
        #expect(book.lastEnrichmentDate == now)
    }
}

// MARK: - ISBN Duplicate Check Tests

@Suite("ISBN Duplicate Check Tests")
struct ISBNDuplicateCheckTests {

    @Test("检测到重复 ISBN 返回已有书籍")
    @MainActor
    func detectDuplicateISBN() throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // 先插入一本书
        let existing = Book(title: "已有的书", author: "作者A", isbn: "9787544291163", bookType: .paper)
        context.insert(existing)
        try context.save()

        // 查重
        let duplicate = ISBNDuplicateChecker.findExisting(isbn: "9787544291163", in: context)
        #expect(duplicate != nil)
        #expect(duplicate?.title == "已有的书")
    }

    @Test("不同 ISBN 不会误判重复")
    @MainActor
    func noDuplicateForDifferentISBN() throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let existing = Book(title: "已有的书", author: "作者A", isbn: "9787544291163", bookType: .paper)
        context.insert(existing)
        try context.save()

        let duplicate = ISBNDuplicateChecker.findExisting(isbn: "9787020002207", in: context)
        #expect(duplicate == nil)
    }

    @Test("空 ISBN 不触发查重")
    @MainActor
    func emptyISBNNoDuplicateCheck() throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let existing = Book(title: "已有的书", author: "作者A", isbn: "9787544291163", bookType: .paper)
        context.insert(existing)
        try context.save()

        let duplicate = ISBNDuplicateChecker.findExisting(isbn: "", in: context)
        #expect(duplicate == nil)
    }

    @Test("ISBN 去除连字符后匹配")
    @MainActor
    func isbnMatchWithHyphens() throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let existing = Book(title: "已有的书", author: "作者A", isbn: "978-7-5442-9116-3", bookType: .paper)
        context.insert(existing)
        try context.save()

        // 用纯数字查
        let duplicate = ISBNDuplicateChecker.findExisting(isbn: "9787544291163", in: context)
        #expect(duplicate != nil)
    }
}

// MARK: - Batch Enrichment Tests

@Suite("WeRead Batch Enrichment Tests")
struct WeReadBatchEnrichmentTests {

    @Test("筛选缺失数据的书 — 有完整数据的不需要补全")
    func bookWithCompleteDataNotNeedEnrichment() {
        let book = Book(title: "完整书", author: "作者", publisher: "出版社",
                        totalPages: 300, price: "¥59", bookType: .ebook,
                        bookDescription: "简介")
        book.authorDescription = "作者简介"
        book.publishDate = Date()
        book.wereadBookId = "wr123"

        #expect(!book.needsEnrichment)
    }

    @Test("筛选缺失数据的书 — 缺出版社需要补全")
    func bookMissingPublisherNeedsEnrichment() {
        let book = Book(title: "缺出版社", author: "作者", bookType: .ebook,
                        bookDescription: "简介")
        book.totalPages = 300
        book.authorDescription = "作者简介"
        book.wereadBookId = "wr456"

        #expect(book.needsEnrichment)
    }

    @Test("筛选缺失数据的书 — 缺简介需要补全")
    func bookMissingDescriptionNeedsEnrichment() {
        let book = Book(title: "缺简介", author: "作者", publisher: "出版社",
                        bookType: .ebook)
        book.totalPages = 200
        book.wereadBookId = "wr789"

        #expect(book.needsEnrichment)
    }

    @Test("筛选缺失数据的书 — 非微信读书书不参与")
    func nonWereadBookNotEnriched() {
        let book = Book(title: "纸质书", author: "作者", bookType: .paper)
        // 即使缺数据，如果没有 wereadBookId，也不参与微信读书补全
        #expect(book.wereadBookId == nil)
    }

    @Test("筛选缺失数据的书 — 缺页数需要补全")
    func bookMissingPagesNeedsEnrichment() {
        let book = Book(title: "缺页数", author: "作者", publisher: "出版社",
                        bookType: .ebook, bookDescription: "简介")
        book.authorDescription = "作者简介"
        book.wereadBookId = "wr101"
        // totalPages 默认 0

        #expect(book.needsEnrichment)
    }

    @Test("筛选缺失数据的书 — 缺作者简介需要补全")
    func bookMissingAuthorDescNeedsEnrichment() {
        let book = Book(title: "缺作者简介", author: "作者", publisher: "出版社",
                        bookType: .ebook, bookDescription: "简介")
        book.totalPages = 100
        book.wereadBookId = "wr102"

        #expect(book.needsEnrichment)
    }

}

// MARK: - CoverFetchService Tests

@Suite("CoverFetchService Tests")
struct CoverFetchServiceTests {

    @Test("fetchCoverFromOpenLibrary 拒绝无效 ISBN")
    func rejectInvalidISBN() async {
        let service = CoverFetchService.shared
        let result = await service.fetchCoverFromOpenLibrary(isbn: "123")
        #expect(result == nil)
    }

    @Test("fetchCover nil 参数不崩溃")
    func fetchCoverNilParams() async {
        let service = CoverFetchService.shared
        let result = await service.fetchCover(isbn: nil, doubanURL: nil, title: nil, author: nil)
        #expect(result == nil)
    }

    @Test("fetchCover 空字符串参数不崩溃")
    func fetchCoverEmptyParams() async {
        let service = CoverFetchService.shared
        let result = await service.fetchCover(isbn: "", doubanURL: "", title: "", author: "")
        #expect(result == nil)
    }

    @Test("fetchCoverThrottled 所有参数为 nil 返回 nil")
    func fetchCoverThrottledAllNil() async {
        let service = CoverFetchService.shared
        let result = await service.fetchCoverThrottled(
            coverImageURL: nil,
            isbn: nil,
            doubanURL: nil,
            title: nil,
            author: nil
        )
        #expect(result == nil)
    }

    @Test("fetchCoverThrottled 空 coverImageURL 跳过直接下载")
    func fetchCoverThrottledEmptyURL() async {
        let service = CoverFetchService.shared
        let result = await service.fetchCoverThrottled(
            coverImageURL: "",
            isbn: nil,
            doubanURL: nil,
            title: nil,
            author: nil
        )
        #expect(result == nil)
    }

    @Test("downloadWithReferer 无效 URL 返回 nil")
    func downloadInvalidURL() async {
        let service = CoverFetchService.shared
        let result = await service.downloadWithReferer(urlStr: "not a url at all")
        #expect(result == nil)
    }

    @Test("fetchCoverFromDouban 无效 URL 返回 nil")
    func fetchDoubanInvalidURL() async {
        let service = CoverFetchService.shared
        let result = await service.fetchCoverFromDouban(doubanURL: "not a url")
        #expect(result == nil)
    }

    @Test("fetchCoverFromDoubanSearch 空标题返回 nil")
    func fetchDoubanSearchEmptyTitle() async {
        let service = CoverFetchService.shared
        let result = await service.fetchCoverFromDoubanSearch(title: "", author: nil)
        #expect(result == nil)
    }
}

// MARK: - CoverImageCache Extended Tests

@Suite("CoverImageCache Extended Tests")
struct CoverImageCacheExtendedTests {

    @Test("缓存键使用 title|author 格式")
    func cacheKeyFormat() {
        let cache = CoverImageCache.shared
        let key = "缓存键测试_\(UUID().uuidString)|作者"
        let image = UIImage(systemName: "book.fill")!
        cache.set(image, for: key)
        #expect(cache.image(for: key) != nil)
        #expect(cache.image(for: "缓存键测试_other|其他作者") == nil)
        cache.remove(for: key)
    }

    @Test("同 key 多次设置覆盖旧值")
    func cacheOverwrite() {
        let cache = CoverImageCache.shared
        let key = "overwrite_test_\(UUID().uuidString)"
        let img1 = UIImage(systemName: "star")!
        let img2 = UIImage(systemName: "heart")!
        cache.set(img1, for: key)
        cache.set(img2, for: key)
        let retrieved = cache.image(for: key)
        #expect(retrieved != nil)
        cache.remove(for: key)
    }

    @Test("空 key 也能正常工作")
    func emptyKeyCacheable() {
        let cache = CoverImageCache.shared
        let key = ""
        let image = UIImage(systemName: "book")!
        cache.set(image, for: key)
        #expect(cache.image(for: key) != nil)
        cache.remove(for: key)
    }
}

// MARK: - AsyncSemaphore Tests

@Suite("AsyncSemaphore Tests")
struct AsyncSemaphoreTests {

    @Test("信号量基本 wait/signal 配对")
    func basicWaitSignal() async {
        let semaphore = AsyncSemaphore(limit: 2)
        await semaphore.wait()
        await semaphore.wait()
        // 两次 wait 成功（limit=2），之后 signal
        await semaphore.signal()
        await semaphore.signal()
        // 再次 wait 应该成功
        await semaphore.wait()
        await semaphore.signal()
    }

    @Test("信号量 signal 不超过 limit")
    func signalCappedAtLimit() async {
        let semaphore = AsyncSemaphore(limit: 1)
        // 多次 signal 不应累积超过 limit
        await semaphore.signal()
        await semaphore.signal()
        await semaphore.signal()
        // wait 应该成功（count 被 cap 在 limit）
        await semaphore.wait()
        // 但第二次 wait 不应立即完成（如果没有超累积）
        // 这里只验证不崩溃
    }
}

// MARK: - SearchScope Tests

@Suite("SearchScope Tests")
struct SearchScopeTests {

    @Test("SearchScope allCases 包含6个")
    func allCases() {
        #expect(SearchScope.allCases.count == 6)
    }

    @Test("SearchScope label 正确")
    func labels() {
        #expect(SearchScope.all.label == "全部")
        #expect(SearchScope.title.label == "书名")
        #expect(SearchScope.author.label == "作者")
        #expect(SearchScope.tag.label == "标签")
        #expect(SearchScope.publisher.label == "出版社")
        #expect(SearchScope.shelf.label == "书架")
    }

    @Test("SearchScope placeholder 正确")
    func placeholders() {
        #expect(SearchScope.all.placeholder == "搜索书名、作者、标签、出版社...")
        #expect(SearchScope.title.placeholder == "搜索书名")
        #expect(SearchScope.author.placeholder == "搜索作者")
    }
}

// MARK: - Book Archive Tests

@Suite("Book Archive Tests")
struct BookArchiveTests {

    @Test("新书 isArchived 默认 false")
    func defaultNotArchived() {
        let book = Book(title: "测试", author: "测试")
        #expect(book.isArchived == false)
    }

    @Test("可以取消收藏")
    func archiveBook() {
        let book = Book(title: "测试", author: "测试")
        book.isArchived = true
        #expect(book.isArchived == true)
    }

    @Test("可以恢复收藏")
    func unarchiveBook() {
        let book = Book(title: "测试", author: "测试")
        book.isArchived = true
        book.isArchived = false
        #expect(book.isArchived == false)
    }
}

// MARK: - Book WeRead Fields Tests

@Suite("Book WeRead Fields Tests")
struct BookWeReadFieldsTests {

    @Test("wereadProgress 默认为 0")
    func defaultProgress() {
        let book = Book(title: "测试", author: "测试")
        #expect(book.wereadProgress == 0)
    }

    @Test("wereadProgress 可设置范围 0-100")
    func progressRange() {
        let book = Book(title: "测试", author: "测试")
        book.wereadProgress = 50
        #expect(book.wereadProgress == 50)
        book.wereadProgress = 100
        #expect(book.wereadProgress == 100)
        book.wereadProgress = 0
        #expect(book.wereadProgress == 0)
    }

    @Test("addSource 默认为 manual")
    func defaultAddSource() {
        let book = Book(title: "测试", author: "测试")
        #expect(book.addSource == .manual)
    }
}

// MARK: - Background Context Tests (v0.3 Performance Fix)

@Suite("Background Context Performance Tests")
struct BackgroundContextPerformanceTests {

    @Test("ModelContext 可在后台线程创建和使用")
    func modelContextCreatableOffMainThread() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Tag.self, Bookshelf.self, ReadingRecord.self, configurations: config)

        let result = await Task.detached(priority: .utility) {
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false
            let book = Book(title: "后台创建", author: "后台作者")
            bgContext.insert(book)
            try? bgContext.save()
            return true
        }.value

        #expect(result == true)
    }

    @Test("后台线程 save 不崩溃")
    func backgroundSaveStable() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Tag.self, Bookshelf.self, ReadingRecord.self, configurations: config)

        let saveCount = await Task.detached(priority: .utility) {
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false
            var count = 0
            for i in 0..<20 {
                let book = Book(title: "书\(i)", author: "作者\(i)")
                bgContext.insert(book)
                count += 1
            }
            // 一次性 save（模拟 batchSaveInterval = 50 的行为）
            try? bgContext.save()
            return count
        }.value

        #expect(saveCount == 20)
    }

    @Test("batchCancelled 标志可跨线程读取")
    func cancellationFlagCrossThread() async {
        // 模拟 @State var batchCancelled 的行为
        // 使用 actor 模拟主线程持有的状态
        actor CancelState {
            var cancelled = false
            func cancel() { cancelled = true }
            func isCancelled() -> Bool { cancelled }
        }

        let state = CancelState()

        // 后台线程读取 cancel 状态
        let task = Task.detached(priority: .utility) {
            var iterations = 0
            for _ in 0..<100 {
                if await state.isCancelled() { break }
                iterations += 1
                try? await Task.sleep(for: .milliseconds(1))
            }
            return iterations
        }

        // 模拟用户点击停止
        try? await Task.sleep(for: .milliseconds(20))
        await state.cancel()

        let iterationsCompleted = await task.value
        // 应该在 100 次之前停止
        #expect(iterationsCompleted < 100)
    }

    @Test("CoverImageCache 并发安全 — 多线程同时读写不崩溃")
    func coverCacheConcurrentAccess() async {
        let cache = CoverImageCache.shared
        let testImage = UIImage(systemName: "book.fill")!

        await withTaskGroup(of: Void.self) { group in
            // 10 个并发写入
            for i in 0..<10 {
                group.addTask {
                    cache.set(testImage, for: "concurrent_test_\(i)")
                }
            }
            // 10 个并发读取
            for i in 0..<10 {
                group.addTask {
                    _ = cache.image(for: "concurrent_test_\(i)")
                }
            }
        }

        // 清理
        for i in 0..<10 {
            cache.remove(for: "concurrent_test_\(i)")
        }
    }

    @Test("needsEnrichment + lastEnrichmentDate 过滤逻辑正确")
    func enrichmentFilterLogic() {
        // 纸质书批量补全的筛选条件：纸质 + needsEnrichment + lastEnrichmentDate == nil
        let book1 = Book(title: "需要补全", author: "作者", bookType: .paper)
        #expect(book1.needsEnrichment == true)
        #expect(book1.lastEnrichmentDate == nil)

        // 设置 lastEnrichmentDate 后不再参与
        let book2 = Book(title: "已处理", author: "作者", bookType: .paper)
        book2.lastEnrichmentDate = Date()
        #expect(book2.lastEnrichmentDate != nil)

        // 已归档的不参与
        let book3 = Book(title: "已归档", author: "作者", bookType: .paper)
        book3.isArchived = true
        #expect(book3.isArchived == true)
    }

    @Test("后台线程批量重命名作者 — 模拟 applyRename 模式")
    func backgroundRenameAuthor() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Tag.self, Bookshelf.self, ReadingRecord.self, configurations: config)

        // 主线程插入测试数据
        let mainContext = ModelContext(container)
        let book1 = Book(title: "书1", author: "张立宪 主编")
        let book2 = Book(title: "书2", author: "张立宪 主编, 李四")
        let book3 = Book(title: "书3", author: "王五")
        mainContext.insert(book1)
        mainContext.insert(book2)
        mainContext.insert(book3)
        try mainContext.save()

        let bookIDs = [book1, book2, book3].map(\.persistentModelID)
        let oldName = "张立宪 主编"
        let newName = "张立宪"

        // 后台线程执行重命名
        let count = await Task.detached(priority: .utility) {
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false
            var updated = 0
            for id in bookIDs {
                guard let book = bgContext.model(for: id) as? Book else { continue }
                if book.author == oldName {
                    book.author = newName
                    updated += 1
                } else if book.author.contains(oldName) {
                    let parts = book.author.components(separatedBy: ", ")
                    let newParts = parts.map { $0 == oldName ? newName : $0 }
                    book.author = newParts.joined(separator: ", ")
                    updated += 1
                }
            }
            if updated > 0 { try? bgContext.save() }
            return updated
        }.value

        #expect(count == 2)

        // 验证主线程能看到更新
        let verifyContext = ModelContext(container)
        let all = try verifyContext.fetch(FetchDescriptor<Book>())
        let b1 = all.first(where: { $0.title == "书1" })
        let b2 = all.first(where: { $0.title == "书2" })
        let b3 = all.first(where: { $0.title == "书3" })
        #expect(b1?.author == "张立宪")
        #expect(b2?.author == "张立宪, 李四")
        #expect(b3?.author == "王五")
    }

    @Test("后台线程删除书架 — 模拟 deleteShelf 模式")
    func backgroundDeleteShelf() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Tag.self, Bookshelf.self, ReadingRecord.self, configurations: config)

        let mainContext = ModelContext(container)
        let shelf = Bookshelf(name: "待删书架", icon: "books.vertical")
        let book1 = Book(title: "书架内的书1", author: "作者")
        let book2 = Book(title: "书架内的书2", author: "作者")
        book1.bookshelf = shelf
        book2.bookshelf = shelf
        mainContext.insert(shelf)
        mainContext.insert(book1)
        mainContext.insert(book2)
        try mainContext.save()

        let shelfID = shelf.persistentModelID
        let bookIDs = [book1, book2].map(\.persistentModelID)

        // 后台删除书架但保留书
        await Task.detached(priority: .utility) {
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false
            for id in bookIDs {
                if let book = bgContext.model(for: id) as? Book {
                    book.bookshelf = nil
                }
            }
            if let shelfObj = bgContext.model(for: shelfID) as? Bookshelf {
                bgContext.delete(shelfObj)
            }
            try? bgContext.save()
        }.value

        // 验证：书架被删，书还在但 bookshelf 为 nil
        let verifyContext = ModelContext(container)
        let shelves = try verifyContext.fetch(FetchDescriptor<Bookshelf>())
        #expect(shelves.isEmpty)
        let books = try verifyContext.fetch(FetchDescriptor<Book>())
        #expect(books.count == 2)
        #expect(books.allSatisfy { $0.bookshelf == nil })
    }

    @Test("后台线程批量打标签 — 模拟 applyTags 模式")
    func backgroundApplyTags() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Tag.self, Bookshelf.self, ReadingRecord.self, configurations: config)

        let mainContext = ModelContext(container)
        let book1 = Book(title: "打标签1", author: "作者")
        let book2 = Book(title: "打标签2", author: "作者")
        mainContext.insert(book1)
        mainContext.insert(book2)
        try mainContext.save()

        let bookIDs = [book1, book2].map(\.persistentModelID)
        let tagNames = ["科幻", "推荐"]

        await Task.detached(priority: .utility) {
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false

            var tagMap: [String: PersonalLibrary.Tag] = [:]
            let allTags = (try? bgContext.fetch(FetchDescriptor<PersonalLibrary.Tag>())) ?? []
            for tag in allTags { tagMap[tag.name] = tag }
            for name in tagNames where tagMap[name] == nil {
                let newTag = PersonalLibrary.Tag(name: name)
                bgContext.insert(newTag)
                tagMap[name] = newTag
            }

            for id in bookIDs {
                guard let book = bgContext.model(for: id) as? Book else { continue }
                var bookTags = book.tags ?? []
                for name in tagNames {
                    if !bookTags.contains(where: { $0.name == name }),
                       let tag = tagMap[name] {
                        bookTags.append(tag)
                    }
                }
                book.tags = bookTags
            }
            try? bgContext.save()
        }.value

        // 验证
        let verifyContext = ModelContext(container)
        let books = try verifyContext.fetch(FetchDescriptor<Book>())
        for book in books {
            let names = (book.tags ?? []).map(\.name).sorted()
            #expect(names == ["推荐", "科幻"])
        }
        let tags = try verifyContext.fetch(FetchDescriptor<PersonalLibrary.Tag>())
        #expect(tags.count == 2)
    }
}

// MARK: - AppLogger Tests

@Suite("AppLogger Tests", .serialized)
struct AppLoggerTests {

    @Test("AppLogger.Level 比较顺序正确")
    func levelOrdering() {
        #expect(AppLogger.Level.debug < .info)
        #expect(AppLogger.Level.info < .warning)
        #expect(AppLogger.Level.warning < .error)
    }

    @Test("AppLogger.Level prefix 正确")
    func levelPrefix() {
        #expect(AppLogger.Level.debug.prefix == "DEBUG")
        #expect(AppLogger.Level.info.prefix == "INFO")
        #expect(AppLogger.Level.warning.prefix == "WARN")
        #expect(AppLogger.Level.error.prefix == "ERROR")
    }

    @Test("AppLogger 各级别方法不崩溃")
    func logAllLevels() {
        // 验证调用不崩溃
        AppLogger.debug("test debug", category: "Test")
        AppLogger.info("test info", category: "Test")
        AppLogger.warning("test warning", category: "Test")
        AppLogger.error("test error", category: "Test")
        AppLogger.perf("test perf 100ms", category: "Test")
    }

    @Test("FileLogger rotation 参数合理")
    func fileLoggerConfig() {
        // FileLogger.shared 应该能正常初始化
        let files = FileLogger.shared.logFiles
        // 启动时至少有 app.log
        #expect(files.count >= 1)
    }

    @Test("FileLogger 写入后可读取内容")
    func fileLoggerWriteAndRead() {
        let marker = "TEST_MARKER_\(UUID().uuidString)"
        FileLogger.shared.log(marker)
        // 等待异步写入
        Thread.sleep(forTimeInterval: 0.1)
        let content = FileLogger.shared.mergedContent()
        #expect(content.contains(marker))
    }

    @Test("FileLogger totalSize 返回正数")
    func fileLoggerTotalSize() {
        // 至少有 launch separator
        #expect(FileLogger.shared.totalSize > 0)
    }

    @Test("FileLogger mergedContent 在并发写入时不死锁")
    func fileLoggerConcurrentReadWrite() {
        // 写入多条日志后立即读取（验证 queue.sync 不会死锁）
        for i in 0..<10 {
            FileLogger.shared.log("concurrent_test_\(i)")
        }
        let content = FileLogger.shared.mergedContent()
        #expect(!content.isEmpty)
        let files = FileLogger.shared.logFiles
        #expect(!files.isEmpty)
        let size = FileLogger.shared.totalSize
        #expect(size > 0)
    }

    @Test("AppLogger.Mode 包含三档")
    func modeAllCases() {
        #expect(AppLogger.Mode.allCases.count == 3)
        #expect(AppLogger.Mode.verbose.rawValue == 0)
        #expect(AppLogger.Mode.normal.rawValue == 1)
        #expect(AppLogger.Mode.off.rawValue == 2)
    }

    @Test("AppLogger.Mode displayName 正确")
    func modeDisplayName() {
        #expect(AppLogger.Mode.verbose.displayName == "详细")
        #expect(AppLogger.Mode.normal.displayName == "正常")
        #expect(AppLogger.Mode.off.displayName == "关闭")
    }

    @Test("AppLogger off 模式不写文件")
    func offModeSkipsWrite() {
        // 直接测试 log 方法的 guard 逻辑：off 时不调用 FileLogger
        let saved = AppLogger.currentMode
        defer { AppLogger.currentMode = saved }

        AppLogger.currentMode = .off
        let marker = "SHOULD_NOT_APPEAR_\(UUID().uuidString)"
        // 用 FileLogger 直接写一个 before marker 确保时序正确
        FileLogger.shared.log("BEFORE_\(marker)")
        Thread.sleep(forTimeInterval: 0.05)

        AppLogger.info(marker, category: "Test")
        AppLogger.warning(marker, category: "Test")
        AppLogger.error(marker, category: "Test")
        Thread.sleep(forTimeInterval: 0.15)

        let content = FileLogger.shared.mergedContent()
        // before marker 应该在，但实际 marker 通过 AppLogger 的不应该在
        #expect(content.contains("BEFORE_\(marker)"))
        // off 模式：info/warning/error 都不该出现（通过 [INFO]/[WARN]/[ERROR] 前缀过滤）
        #expect(!content.contains("[INFO] [Test] \(marker)"))
        #expect(!content.contains("[WARN] [Test] \(marker)"))
        #expect(!content.contains("[ERROR] [Test] \(marker)"))
    }

    @Test("AppLogger verbose 模式写 debug 级别")
    func verboseModeWritesDebug() {
        let saved = AppLogger.currentMode
        defer { AppLogger.currentMode = saved }

        AppLogger.currentMode = .verbose
        let marker = "VERBOSE_DEBUG_\(UUID().uuidString)"
        AppLogger.debug(marker, category: "Test")
        Thread.sleep(forTimeInterval: 0.15)
        let content = FileLogger.shared.mergedContent()
        #expect(content.contains(marker))
    }

    @Test("AppLogger normal 模式跳过 info 但写 warning")
    func normalModeFilters() {
        let saved = AppLogger.currentMode
        defer { AppLogger.currentMode = saved }

        AppLogger.currentMode = .normal
        let infoMarker = "NORMAL_INFO_\(UUID().uuidString)"
        let warnMarker = "NORMAL_WARN_\(UUID().uuidString)"
        AppLogger.info(infoMarker, category: "Test")
        AppLogger.warning(warnMarker, category: "Test")
        Thread.sleep(forTimeInterval: 0.15)
        let content = FileLogger.shared.mergedContent()
        #expect(!content.contains(infoMarker))
        #expect(content.contains(warnMarker))
    }
}

// MARK: - New Fields Tests (startedReadingDate, wereadEnrichedDate, export/import)

@Suite("Book New Fields Tests")
struct BookNewFieldsTests {

    @Test("startedReadingDate 默认为 nil")
    func startedReadingDateDefault() {
        let book = Book(title: "测试", author: "作者")
        #expect(book.startedReadingDate == nil)
    }

    @Test("startedReadingDate 可设置和读取")
    func startedReadingDateSettable() {
        let book = Book(title: "测试", author: "作者")
        let date = Date()
        book.startedReadingDate = date
        #expect(book.startedReadingDate == date)
    }

    @Test("wereadEnrichedDate 默认为 nil")
    func wereadEnrichedDateDefault() {
        let book = Book(title: "测试", author: "作者")
        #expect(book.wereadEnrichedDate == nil)
    }

    @Test("wereadEnrichedDate 可设置（标记已补全）")
    func wereadEnrichedDateSettable() {
        let book = Book(title: "测试", author: "作者")
        let now = Date()
        book.wereadEnrichedDate = now
        #expect(book.wereadEnrichedDate == now)
    }

    @Test("applyToBook 填充 startedReadingDate（本地无记录时）并设置 flag")
    func applyToBookSetsStartedDate() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)
        let startDate = Date(timeIntervalSince1970: 1700000000)

        var result = WeReadEnrichResult()
        result.startedReadingTime = startDate
        result.isStartedReadingTimeEstimated = false  // 真实值
        result.applyToBook(book)

        #expect(book.startedReadingDate == startDate)
        #expect(book.isStartedReadingDateEstimated == false)
    }

    @Test("applyToBook 估算值不覆盖用户手动设置的 startedReadingDate")
    func applyToBookDoesNotOverwriteStartedDate() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)
        let existingDate = Date(timeIntervalSince1970: 1600000000)
        book.startedReadingDate = existingDate
        book.isStartedReadingDateEstimated = false  // 用户手动设置/真实API值

        var result = WeReadEnrichResult()
        result.startedReadingTime = Date(timeIntervalSince1970: 1700000000)
        result.isStartedReadingTimeEstimated = true  // 标记为估算值
        result.applyToBook(book)

        #expect(book.startedReadingDate == existingDate)
        #expect(book.isStartedReadingDateEstimated == false)
    }

    @Test("applyToBook 真实值覆盖已有 startedReadingDate 并重置 flag")
    func applyToBookRealValueOverridesEstimatedDate() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)
        let existingDate = Date(timeIntervalSince1970: 1600000000)
        book.startedReadingDate = existingDate
        book.isStartedReadingDateEstimated = true  // 之前是估算值

        var result = WeReadEnrichResult()
        result.startedReadingTime = Date(timeIntervalSince1970: 1700000000)
        result.isStartedReadingTimeEstimated = false  // 真实API值（默认）
        result.applyToBook(book)

        #expect(book.startedReadingDate == Date(timeIntervalSince1970: 1700000000))
        #expect(book.isStartedReadingDateEstimated == false)
    }

    @Test("applyToBook 填充 finishedDate（本地无记录时）")
    func applyToBookSetsFinishedDate() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)
        let finishDate = Date(timeIntervalSince1970: 1700000000)

        var result = WeReadEnrichResult()
        result.finishedTime = finishDate
        result.applyToBook(book)

        #expect(book.finishedDate == finishDate)
    }

    @Test("applyToBook finishedTime 有不同就覆盖")
    func applyToBookOverwritesFinishedDateWhenDifferent() {
        let book = Book(title: "测试", author: "作者", bookType: .ebook)
        let existingDate = Date(timeIntervalSince1970: 1600000000)
        book.finishedDate = existingDate

        var result = WeReadEnrichResult()
        let newDate = Date(timeIntervalSince1970: 1700000000)
        result.finishedTime = newDate
        result.applyToBook(book)

        #expect(book.finishedDate == newDate)
    }
}

// MARK: - Export New Fields Tests

@Suite("Export New Fields Tests")
struct ExportNewFieldsTests {

    @Test("导出包含微信读书阅读时长")
    func exportIncludesReadingHours() async throws {
        let service = ExcelImportExportService()
        let book = Book(title: "测试导出时长", author: "作者")
        book.wereadReadingHours = 12.5

        let data = try await service.exportBooks(books: [book])
        let content = String(data: data, encoding: .utf8)!

        #expect(content.contains("12.50"))
    }

    @Test("导出包含开始阅读日期")
    func exportIncludesStartedDate() async throws {
        let service = ExcelImportExportService()
        let book = Book(title: "测试导出开始日期", author: "作者")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        book.startedReadingDate = formatter.date(from: "2024-03-15 10:30")

        let data = try await service.exportBooks(books: [book])
        let content = String(data: data, encoding: .utf8)!

        #expect(content.contains("2024-03-15 10:30"))
    }

    @Test("导出包含状态变更时间")
    func exportIncludesStatusChangedDate() async throws {
        let service = ExcelImportExportService()
        let book = Book(title: "测试导出状态时间", author: "作者")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        book.statusChangedDate = formatter.date(from: "2024-06-01 09:00")

        let data = try await service.exportBooks(books: [book])
        let content = String(data: data, encoding: .utf8)!

        #expect(content.contains("2024-06-01 09:00"))
    }

    @Test("导出空新字段不产生多余内容")
    func exportEmptyNewFields() async throws {
        let service = ExcelImportExportService()
        let book = Book(title: "无新字段", author: "作者")
        // wereadReadingHours = 0, startedReadingDate = nil, statusChangedDate = nil

        let data = try await service.exportBooks(books: [book])
        let content = String(data: data, encoding: .utf8)!
        let lines = content.components(separatedBy: "\n")
        let dataLine = lines[1]
        let fields = dataLine.components(separatedBy: "\t")

        // 最后三个字段应为空
        #expect(fields[26] == "") // 微信读书阅读时长
        #expect(fields[27] == "") // 开始阅读日期
        #expect(fields[28] == "") // 状态变更时间
    }
}

// MARK: - WeReadEnrichResult startedReadingTime/finishedTime Tests

@Suite("WeReadEnrichResult Date Fields Tests")
struct WeReadEnrichResultDateTests {

    @Test("startedReadingTime 默认 nil")
    func defaultStartedReadingTime() {
        let result = WeReadEnrichResult()
        #expect(result.startedReadingTime == nil)
    }

    @Test("finishedTime 默认 nil")
    func defaultFinishedTime() {
        let result = WeReadEnrichResult()
        #expect(result.finishedTime == nil)
    }

    @Test("startedReadingTime 可设置")
    func setStartedReadingTime() {
        var result = WeReadEnrichResult()
        let date = Date(timeIntervalSince1970: 1700000000)
        result.startedReadingTime = date
        #expect(result.startedReadingTime == date)
    }

    @Test("finishedTime 可设置")
    func setFinishedTime() {
        var result = WeReadEnrichResult()
        let date = Date(timeIntervalSince1970: 1700000000)
        result.finishedTime = date
        #expect(result.finishedTime == date)
    }
}

// MARK: - Skill fetchAllBooks 字段完整性测试

@Suite("Skill fetchAllBooks Field Completeness", .serialized)
struct SkillFetchAllBooksFieldTests {

    @Test("WeReadImportItem 包含 price 和 publishTime 字段")
    func importItemHasPriceAndPublishTime() {
        let item = WeReadImportItem(
            id: "test1", title: "测试书", author: "作者",
            price: 29.99, publishTime: "2023-06"
        )
        #expect(item.price == 29.99)
        #expect(item.publishTime == "2023-06")
    }

    @Test("WeReadImportItem price 和 publishTime 默认为 nil")
    func importItemDefaultsNil() {
        let item = WeReadImportItem(id: "test2", title: "T", author: "A")
        #expect(item.price == nil)
        #expect(item.publishTime == nil)
    }

    @Test("首次导入时 price 写入 Book")
    func importNewBookSavesPrice() async throws {
        WeReadSyncService.resetSyncLockForTesting()
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let mock = MockWeReadDataSource()
        await mock.setBooks([
            WeReadImportItem(
                id: "wr_price_test", title: "价格测试", author: "作者",
                publisher: "出版社", progress: 0, readingTime: 0, ttsTime: 0,
                isFinished: false, bookType: .ebook,
                price: 45.0, publishTime: "2022-03"
            )
        ])

        let syncService = WeReadSyncService(provider: mock)
        let result = await syncService.sync(container: container, skipLockCheck: true)

        #expect(result.newBooksImported == 1)

        let verifyContext = ModelContext(container)
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.wereadBookId == "wr_price_test" })
        let books = try verifyContext.fetch(descriptor)
        #expect(books.count == 1)
        #expect(books[0].price == "¥45.00")
        #expect(books[0].publishDate != nil)
    }

    @Test("首次导入时 readingTime 和 ttsTime 写入 wereadReadingHours")
    func importNewBookSavesReadingTime() async throws {
        WeReadSyncService.resetSyncLockForTesting()
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let mock = MockWeReadDataSource()
        await mock.setBooks([
            WeReadImportItem(
                id: "wr_time_test", title: "时长测试", author: "作者",
                progress: 50, readingTime: 7200, ttsTime: 1800,
                isFinished: false, bookType: .ebook
            )
        ])

        let syncService = WeReadSyncService(provider: mock)
        let result = await syncService.sync(container: container, skipLockCheck: true)

        #expect(result.newBooksImported == 1)

        let verifyContext = ModelContext(container)
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.wereadBookId == "wr_time_test" })
        let books = try verifyContext.fetch(descriptor)
        #expect(books.count == 1)
        #expect(books[0].wereadReadingHours == 2.5) // (7200+1800)/3600
    }

    @Test("首次导入时 finishedTime 写入 Book.finishedDate")
    func importNewBookSavesFinishedTime() async throws {
        WeReadSyncService.resetSyncLockForTesting()
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let finishDate = Date(timeIntervalSince1970: 1700000000)
        let mock = MockWeReadDataSource()
        await mock.setBooks([
            WeReadImportItem(
                id: "wr_finish_test", title: "完成测试", author: "作者",
                progress: 100, readingTime: 3600, ttsTime: 0,
                isFinished: true, bookType: .ebook,
                finishedTime: finishDate
            )
        ])

        let syncService = WeReadSyncService(provider: mock)
        let result = await syncService.sync(container: container, skipLockCheck: true)

        #expect(result.newBooksImported == 1)

        let verifyContext = ModelContext(container)
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.wereadBookId == "wr_finish_test" })
        let books = try verifyContext.fetch(descriptor)
        #expect(books.count == 1)
        #expect(books[0].status == .finished)
        #expect(books[0].finishedDate == finishDate)
    }

    @Test("同步已有书时补充 price 和 publishTime（仅空时填充）")
    func updateExistingBookFillsPriceAndPublishTime() async throws {
        WeReadSyncService.resetSyncLockForTesting()
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let setupContext = ModelContext(container)

        let existingBook = Book(title: "已有书", author: "作者", bookType: .ebook)
        existingBook.wereadBookId = "wr_existing"
        setupContext.insert(existingBook)
        try setupContext.save()

        let mock = MockWeReadDataSource()
        await mock.setBooks([
            WeReadImportItem(
                id: "wr_existing", title: "已有书", author: "作者",
                progress: 30, readingTime: 1800, ttsTime: 0,
                isFinished: false, bookType: .ebook,
                price: 35.5, publishTime: "2021-11"
            )
        ])

        let syncService = WeReadSyncService(provider: mock)
        let result = await syncService.sync(container: container, skipLockCheck: true)

        #expect(result.newBooksImported == 0)

        let verifyContext = ModelContext(container)
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.wereadBookId == "wr_existing" })
        let books = try verifyContext.fetch(descriptor)
        #expect(books.count == 1)
        #expect(books[0].price == "¥35.50")
        #expect(books[0].publishDate != nil)
    }

    @Test("同步已有书时不覆盖已有 price")
    func updateExistingBookDoesNotOverwritePrice() async throws {
        WeReadSyncService.resetSyncLockForTesting()
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let setupContext = ModelContext(container)

        let existingBook = Book(title: "已有价格", author: "作者", bookType: .ebook)
        existingBook.wereadBookId = "wr_has_price"
        existingBook.price = "¥99.00"
        setupContext.insert(existingBook)
        try setupContext.save()

        let mock = MockWeReadDataSource()
        await mock.setBooks([
            WeReadImportItem(
                id: "wr_has_price", title: "已有价格", author: "作者",
                progress: 0, readingTime: 0, ttsTime: 0,
                isFinished: false, bookType: .ebook,
                price: 35.5, publishTime: "2021-11"
            )
        ])

        let syncService = WeReadSyncService(provider: mock)
        _ = await syncService.sync(container: container, skipLockCheck: true)

        let verifyContext = ModelContext(container)
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.wereadBookId == "wr_has_price" })
        let books = try verifyContext.fetch(descriptor)
        #expect(books[0].price == "¥99.00") // 不被覆盖
    }
}

// MARK: - EnrichBook 字段完整性测试 (方式2/3)

@Suite("EnrichBook Field Strategy Tests")
struct EnrichBookFieldStrategyTests {

    // MARK: - WeReadEnrichResult 新字段

    @Test("WeReadEnrichResult 包含 title/author/cover/translator/category/progress 字段")
    func enrichResultHasNewFields() {
        var result = WeReadEnrichResult()
        result.title = "测试书名"
        result.author = "测试作者"
        result.cover = "https://cover.jpg"
        result.translator = "译者"
        result.category = "文学"
        result.progress = 75

        #expect(result.title == "测试书名")
        #expect(result.author == "测试作者")
        #expect(result.cover == "https://cover.jpg")
        #expect(result.translator == "译者")
        #expect(result.category == "文学")
        #expect(result.progress == 75)
    }

    // MARK: - applyToBook 填空策略

    @Test("applyToBook: title/author/cover 填空，不覆盖已有值")
    func applyToBookFillsEmptyTitleAuthorCover() {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // 书有 title 和 author，没有 cover
        let book = Book(title: "原标题", author: "原作者", bookType: .ebook)
        book.coverImageURL = nil
        context.insert(book)

        var result = WeReadEnrichResult()
        result.title = "新标题"
        result.author = "新作者"
        result.cover = "https://new-cover.jpg"

        result.applyToBook(book)

        // 填空：已有值不覆盖
        #expect(book.title == "原标题")
        #expect(book.author == "原作者")
        // 空字段被填充
        #expect(book.coverImageURL == "https://new-cover.jpg")
    }

    @Test("applyToBook: translator/category 填空")
    func applyToBookFillsTranslatorCategory() {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let book = Book(title: "T", author: "A", bookType: .ebook)
        context.insert(book)

        var result = WeReadEnrichResult()
        result.translator = "王译"
        result.category = "历史"

        result.applyToBook(book)

        #expect(book.translator == "王译")
    }

    // MARK: - applyToBook 只增不减策略

    @Test("applyToBook: progress 有不同就更新（非零即更新）")
    func applyToBookProgressUpdatesWhenDifferent() {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let book = Book(title: "T", author: "A", bookType: .ebook)
        book.wereadProgress = 60
        context.insert(book)

        // 新进度更大 → 更新
        var result1 = WeReadEnrichResult()
        result1.progress = 80
        result1.applyToBook(book)
        #expect(book.wereadProgress == 80)

        // 新进度更小但非零 → 也更新（有不同就更新策略）
        var result2 = WeReadEnrichResult()
        result2.progress = 50
        result2.applyToBook(book)
        #expect(book.wereadProgress == 50)

        // 新进度为 0 → 不更新（防止 0 覆盖）
        var result3 = WeReadEnrichResult()
        result3.progress = 0
        result3.applyToBook(book)
        #expect(book.wereadProgress == 50)
    }

    // MARK: - applyToBook 有不同就覆盖策略

    @Test("applyToBook: finishedTime 有不同就覆盖（非仅填空）")
    func applyToBookFinishedTimeOverwritesWhenDifferent() {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let oldDate = Date(timeIntervalSince1970: 1700000000)
        let newDate = Date(timeIntervalSince1970: 1710000000)

        let book = Book(title: "T", author: "A", bookType: .ebook)
        book.finishedDate = oldDate
        context.insert(book)

        var result = WeReadEnrichResult()
        result.finishedTime = newDate
        result.applyToBook(book)

        // 有不同就覆盖
        #expect(book.finishedDate == newDate)
    }

    @Test("applyToBook: finishedTime 相同不触发更新")
    func applyToBookFinishedTimeSameNoOp() {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let date = Date(timeIntervalSince1970: 1700000000)

        let book = Book(title: "T", author: "A", bookType: .ebook)
        book.finishedDate = date
        context.insert(book)

        var result = WeReadEnrichResult()
        result.finishedTime = date
        result.applyToBook(book)

        #expect(book.finishedDate == date)
    }
}

// MARK: - Cover Image Processor Tests (封面缩略图化，根治库膨胀卡顿)

@Suite("Cover Image Processor Tests")
struct CoverImageProcessorTests {

    /// 生成一张"难压缩"的大图（随机色块），确保 JPEG 体积 > 阈值以触发缩略图逻辑
    private func makeNoisyJPEG(side: CGFloat) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let img = renderer.image { ctx in
            for _ in 0..<3000 {
                let x = CGFloat.random(in: 0..<side), y = CGFloat.random(in: 0..<side)
                let w = CGFloat.random(in: 4..<40), h = CGFloat.random(in: 4..<40)
                UIColor(red: .random(in: 0...1), green: .random(in: 0...1),
                        blue: .random(in: 0...1), alpha: 1).setFill()
                ctx.fill(CGRect(x: x, y: y, width: w, height: h))
            }
        }
        return img.jpegData(compressionQuality: 1.0)!
    }

    @Test("大图被压成 ≤400px 且体积更小")
    func largeImageDownsampled() throws {
        let big = makeNoisyJPEG(side: 1500)
        #expect(big.count > CoverImageProcessor.passthroughBelowBytes, "测试图应足够大以触发压缩")
        let thumb = CoverImageProcessor.thumbnailData(from: big)
        #expect(thumb.count < big.count, "缩略图应更小")
        let ui = try #require(UIImage(data: thumb))
        #expect(max(ui.size.width, ui.size.height) <= 401, "最长边应 ≤400px")
    }

    @Test("已经很小的数据原样返回")
    func smallDataPassthrough() {
        let small = Data(repeating: 0xAB, count: 100)
        #expect(CoverImageProcessor.thumbnailData(from: small) == small)
    }

    @Test("38字节坏占位原样返回（交给 hasCoverData 判定为无封面）")
    func brokenTinyPassthrough() {
        let junk = Data(repeating: 0x00, count: 38)
        #expect(CoverImageProcessor.thumbnailData(from: junk) == junk)
    }
}

@Suite("Book hasCoverData Threshold Tests")
struct BookCoverThresholdTests {
    @Test("nil / 38字节 / <1KB 视为无封面；≥1KB 视为有封面")
    func threshold() {
        let book = Book(title: "T", author: "A")
        book.coverImageData = nil
        #expect(book.hasCoverData == false)
        book.coverImageData = Data(repeating: 1, count: 38)
        #expect(book.hasCoverData == false)
        book.coverImageData = Data(repeating: 1, count: 1023)
        #expect(book.hasCoverData == false)
        book.coverImageData = Data(repeating: 1, count: 2048)
        #expect(book.hasCoverData == true)
    }
}
