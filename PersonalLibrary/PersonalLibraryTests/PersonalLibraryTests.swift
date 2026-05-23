import Foundation
import Testing
import SwiftData
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

    @Test("columnHeaders 包含26列")
    func columnHeadersCount() {
        #expect(ExcelImportExportService.columnHeaders.count == 26)
        #expect(ExcelImportExportService.columnHeaders[0] == "序号")
        #expect(ExcelImportExportService.columnHeaders[1] == "书名")
        #expect(ExcelImportExportService.columnHeaders[17] == "豆瓣链接")
        #expect(ExcelImportExportService.columnHeaders[24] == "微信读书ID")
        #expect(ExcelImportExportService.columnHeaders[25] == "微信读书进度")
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

    @Test("开启自动同步但距上次不足1小时返回false")
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

    @Test("开启自动同步且超过1小时返回true")
    func enabledOldSync() {
        WeReadSyncService.autoSyncEnabled = true
        WeReadSyncService.lastSyncDate = Date().addingTimeInterval(-7200)
        defer {
            WeReadSyncService.autoSyncEnabled = false
            WeReadSyncService.lastSyncDate = nil
        }

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

@Suite("WeReadSyncService Logic Tests")
struct WeReadSyncLogicTests {

    @Test("未登录时同步返回错误")
    func syncWithoutLogin() async throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // 确保未登录（清除 Keychain）
        KeychainService.delete(key: KeychainService.wereadCookieKey)

        let syncService = WeReadSyncService()
        let result = await syncService.sync(modelContext: context)

        #expect(result.error == "未登录微信读书")
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
