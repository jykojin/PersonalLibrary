import Foundation
import CoreXLSX
import SwiftData

/// Excel 导入导出服务
/// 支持导入/导出格式：序号, 书名, 作者, 译者, 出版社, 出版年份, ISBN, 定价, 总页数,
/// 加入时间, 阅读状态, 读完时间, 所在书架, 标签, 图书简介, 作者简介, 备注, 豆瓣链接
actor ExcelImportExportService {

    // MARK: - Column Mapping

    /// Excel 列标题（与"私家书藏"格式兼容，扩展字段追加在后）
    static let columnHeaders = [
        "序号", "书名", "作者", "译者", "出版社", "出版年份",
        "ISBN", "定价", "总页数", "加入时间", "阅读状态", "读完时间",
        "所在书架", "标签", "图书简介", "作者简介", "备注", "豆瓣链接",
        "封面链接", "书籍类型", "加入方式", "评分", "当前页码", "是否归档",
        "微信读书ID", "微信读书进度"
    ]

    // MARK: - Import

    struct ImportResult {
        var successCount: Int
        var failedCount: Int
        var errors: [String]
    }

    /// 从 XLSX 文件导入书籍
    func importBooks(from fileURL: URL, modelContext: ModelContext) throws -> ImportResult {
        let didStartAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            throw ImportError.cannotAccessFile
        }

        return try importBooks(data: data, modelContext: modelContext)
    }

    /// 从 XLSX 数据导入书籍
    func importBooks(data: Data, modelContext: ModelContext) throws -> ImportResult {
        // 安全限制：最大 10MB，防止恶意超大文件耗尽内存
        guard data.count <= 10_000_000 else {
            throw ImportError.invalidFormat
        }

        let xlsxFile: XLSXFile
        do {
            xlsxFile = try XLSXFile(data: data)
        } catch {
            print("[ExcelImport] XLSXFile(data:) failed: \(error)")
            throw ImportError.invalidFormat
        }
        // sharedStrings 可能不存在（某些导出工具使用 inline strings）
        let sharedStrings = try xlsxFile.parseSharedStrings()

        let worksheetPaths = try xlsxFile.parseWorksheetPaths()
        guard let firstPath = worksheetPaths.first else {
            throw ImportError.noWorksheet
        }

        let worksheet = try xlsxFile.parseWorksheet(at: firstPath)
        guard let rows = worksheet.data?.rows, rows.count > 1 else {
            throw ImportError.noData
        }

        // 解析表头确定列映射
        let headerRow = rows[0]
        let columnMap = buildColumnMap(headerRow: headerRow, sharedStrings: sharedStrings)

        var successCount = 0
        var failedCount = 0
        var errors: [String] = []

        // 获取已有书架和标签缓存
        var bookshelfCache: [String: Bookshelf] = [:]
        var tagCache: [String: Tag] = [:]

        let existingBookshelves = try modelContext.fetch(FetchDescriptor<Bookshelf>())
        for shelf in existingBookshelves {
            bookshelfCache[shelf.name] = shelf
        }

        let existingTags = try modelContext.fetch(FetchDescriptor<Tag>())
        for tag in existingTags {
            tagCache[tag.name] = tag
        }

        // 逐行导入
        for rowIndex in 1..<rows.count {
            let row = rows[rowIndex]
            do {
                let book = try parseBookFromRow(
                    row: row,
                    columnMap: columnMap,
                    sharedStrings: sharedStrings,
                    bookshelfCache: &bookshelfCache,
                    tagCache: &tagCache,
                    modelContext: modelContext
                )
                if let book {
                    modelContext.insert(book)
                    successCount += 1
                }
            } catch {
                failedCount += 1
                errors.append("第 \(rowIndex + 1) 行: \(error.localizedDescription)")
            }
        }

        try modelContext.save()
        return ImportResult(successCount: successCount, failedCount: failedCount, errors: errors)
    }

    // MARK: - Export

    /// 导出所有书籍为 TSV 数据（UTF-8 BOM，Excel 兼容）
    func exportBooks(books: [Book]) throws -> Data {
        var csvContent = "\u{FEFF}"  // BOM for Excel to detect UTF-8

        // 写入表头
        csvContent += Self.columnHeaders.joined(separator: "\t") + "\n"

        // 写入数据行
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        for (index, book) in books.enumerated() {
            let fields: [String] = [
                String(index + 1),                                         // 序号
                book.title,                                                // 书名
                book.author,                                               // 作者
                book.translator ?? "",                                     // 译者
                book.publisher ?? "",                                      // 出版社
                formatPublishDate(book.publishDate),                        // 出版年份
                book.isbn ?? "",                                           // ISBN
                book.price ?? "",                                          // 定价
                book.totalPages > 0 ? String(book.totalPages) : "",        // 总页数
                dateFormatter.string(from: book.addedDate),                // 加入时间
                mapStatusToExport(book.status),                            // 阅读状态
                book.finishedDate.map { dateFormatter.string(from: $0) } ?? "",  // 读完时间
                book.bookshelf?.name ?? "",                                // 所在书架
                (book.tags ?? []).map(\.name).joined(separator: " / "),     // 标签
                book.bookDescription ?? "",                                // 图书简介
                book.authorDescription ?? "",                              // 作者简介
                book.notes ?? "",                                          // 备注
                book.doubanURL ?? "",                                       // 豆瓣链接
                book.coverImageURL ?? "",                                   // 封面链接
                book.bookType.rawValue,                                    // 书籍类型
                book.addSource.rawValue,                                   // 加入方式
                book.rating.map { String($0) } ?? "",                      // 评分
                book.currentPage > 0 ? String(book.currentPage) : "",      // 当前页码
                book.isArchived ? "是" : "",                                 // 是否归档
                book.wereadBookId ?? "",                                     // 微信读书ID
                book.wereadProgress > 0 ? String(book.wereadProgress) : ""  // 微信读书进度
            ]
            // 对每个字段进行转义（替换制表符为空格）
            let escaped = fields.map { escapeField($0) }
            csvContent += escaped.joined(separator: "\t") + "\n"
        }

        guard let data = csvContent.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }
        return data
    }

    // MARK: - Private Helpers

    private func buildColumnMap(headerRow: Row, sharedStrings: SharedStrings?) -> [String: Int] {
        var map: [String: Int] = [:]
        for cell in headerRow.cells {
            if let value = cellStringValue(cell, sharedStrings: sharedStrings) {
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                let colRef = cell.reference.column
                map[trimmed] = colRef.columnIndex
            }
        }
        return map
    }

    private func getCellValue(row: Row, columnIndex: Int, sharedStrings: SharedStrings?) -> String? {
        for cell in row.cells {
            let colRef = cell.reference.column
            if colRef.columnIndex == columnIndex {
                if let stringValue = cellStringValue(cell, sharedStrings: sharedStrings) {
                    let trimmed = stringValue.trimmingCharacters(in: .whitespaces)
                    return trimmed.isEmpty ? nil : trimmed
                }
            }
        }
        return nil
    }

    /// 获取 cell 的字符串值，支持 shared strings、inline strings 和直接值
    private func cellStringValue(_ cell: Cell, sharedStrings: SharedStrings?) -> String? {
        // 如果有 shared strings 且 cell 类型是 shared string
        if let sharedStrings {
            if let value = cell.stringValue(sharedStrings) {
                return value
            }
        }
        // 尝试 inline string
        if let inlineText = cell.inlineString?.text {
            return inlineText
        }
        // 直接值
        return cell.value
    }

    private func parseBookFromRow(
        row: Row,
        columnMap: [String: Int],
        sharedStrings: SharedStrings?,
        bookshelfCache: inout [String: Bookshelf],
        tagCache: inout [String: Tag],
        modelContext: ModelContext
    ) throws -> Book? {
        // 书名是必须的
        guard let titleCol = columnMap["书名"],
              let title = getCellValue(row: row, columnIndex: titleCol, sharedStrings: sharedStrings),
              !title.isEmpty else {
            return nil  // 跳过空行
        }

        let authorRaw = columnMap["作者"].flatMap { getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) } ?? "未知作者"
        // 作者字段用分号分隔多个作者，保存时用逗号连接（不用顿号）
        let author = splitMultiValue(authorRaw).joined(separator: ", ")
        let translatorRaw = columnMap["译者"].flatMap { getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }
        let translator = translatorRaw.map { splitMultiValue($0).joined(separator: ", ") }
        let publisherRaw = columnMap["出版社"].flatMap { getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }
        let publisher = publisherRaw.map { splitMultiValue($0).joined(separator: ", ") }
        let isbn = columnMap["ISBN"].flatMap { getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }
        let priceStr = columnMap["定价"].flatMap { getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }
        let pagesStr = columnMap["总页数"].flatMap { getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }
        let bookDesc = columnMap["图书简介"].flatMap { getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }
        let authorDesc = columnMap["作者简介"].flatMap { getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }
        let notes = columnMap["备注"].flatMap { getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }
        let doubanURL = columnMap["豆瓣链接"].flatMap { getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }
        // 支持"封面链接"列（私家书藏导出格式）
        let coverLink = columnMap["封面链接"].flatMap { getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }
        let publishYear = columnMap["出版年份"].flatMap { getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }

        let totalPages = pagesStr.flatMap { Int($0.replacingOccurrences(of: ".0", with: "")) } ?? 0

        // 封面优先用 Excel 里的"封面链接"，其次用 ISBN 拼接
        let finalCoverURL = coverLink ?? coverURL(isbn: isbn, doubanURL: doubanURL)

        let book = Book(
            title: title,
            author: author,
            translator: translator,
            isbn: isbn,
            publisher: publisher,
            publishDate: parsePublishDate(publishYear),
            totalPages: totalPages,
            price: priceStr,
            doubanURL: doubanURL,
            bookDescription: bookDesc,
            authorDescription: authorDesc,
            coverImageURL: finalCoverURL
        )
        book.notes = notes

        // 书籍类型
        if let typeStr = columnMap["书籍类型"].flatMap({ getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }) {
            book.bookType = BookType.allCases.first(where: { $0.rawValue == typeStr }) ?? .paper
        }

        // 加入方式（如果导入文件有此列则使用，否则标记为"导入"）
        if let sourceStr = columnMap["加入方式"].flatMap({ getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }) {
            book.addSource = AddSource.allCases.first(where: { $0.rawValue == sourceStr }) ?? .imported
        } else {
            book.addSource = .imported
        }

        // 评分
        if let ratingStr = columnMap["评分"].flatMap({ getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }),
           let ratingVal = Int(ratingStr.replacingOccurrences(of: ".0", with: "")), ratingVal >= 1 && ratingVal <= 5 {
            book.rating = ratingVal
        }

        // 当前页码
        if let pageStr = columnMap["当前页码"].flatMap({ getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }),
           let page = Int(pageStr.replacingOccurrences(of: ".0", with: "")) {
            book.currentPage = page
        }

        // 是否归档
        if let archivedStr = columnMap["是否归档"].flatMap({ getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }) {
            book.isArchived = (archivedStr == "是")
        }

        // 微信读书ID
        if let wereadId = columnMap["微信读书ID"].flatMap({ getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }) {
            book.wereadBookId = wereadId
        }

        // 微信读书进度
        if let progressStr = columnMap["微信读书进度"].flatMap({ getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }),
           let progress = Int(progressStr.replacingOccurrences(of: ".0", with: "")) {
            book.wereadProgress = progress
        }

        // 解析加入时间
        if let addedStr = columnMap["加入时间"].flatMap({ getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }) {
            book.addedDate = parseDateTime(addedStr) ?? Date()
        }

        // 解析阅读状态
        if let statusStr = columnMap["阅读状态"].flatMap({ getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }) {
            book.status = mapStatusFromImport(statusStr)
        }

        // 解析读完时间
        if let finishedStr = columnMap["读完时间"].flatMap({ getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }) {
            book.finishedDate = parseDateTime(finishedStr)
        }

        // 解析书架
        if let shelfName = columnMap["所在书架"].flatMap({ getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }) {
            if let existing = bookshelfCache[shelfName] {
                book.bookshelf = existing
            } else {
                let newShelf = Bookshelf(name: shelfName)
                modelContext.insert(newShelf)
                bookshelfCache[shelfName] = newShelf
                book.bookshelf = newShelf
            }
        }

        // 解析标签（支持 / ； ; 分隔，限制最多20个标签防止恶意输入）
        if let tagsStr = columnMap["标签"].flatMap({ getCellValue(row: row, columnIndex: $0, sharedStrings: sharedStrings) }) {
            let tagNames = Array(splitMultiValue(tagsStr)
                .prefix(20))

            var bookTags: [Tag] = []
            for tagName in tagNames {
                if let existing = tagCache[tagName] {
                    bookTags.append(existing)
                } else {
                    let newTag = Tag(name: tagName)
                    modelContext.insert(newTag)
                    tagCache[tagName] = newTag
                    bookTags.append(newTag)
                }
            }
            book.tags = bookTags
        }

        return book
    }

    private func parsePublishDate(_ yearStr: String?) -> Date? {
        guard let yearStr else { return nil }
        let cleaned = yearStr.replacingOccurrences(of: ".0", with: "")
        if let year = Int(cleaned) {
            var components = DateComponents()
            components.year = year
            return Calendar.current.date(from: components)
        }
        // 尝试 "2020-01" 或 "2020-01-15" 格式
        let formatter = DateFormatter()
        for format in ["yyyy-MM-dd", "yyyy-MM", "yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) {
                return date
            }
        }
        return nil
    }

    private func parseDateTime(_ str: String) -> Date? {
        let formatter = DateFormatter()
        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "yyyy/MM/dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: str) {
                return date
            }
        }
        return nil
    }

    private func mapStatusFromImport(_ str: String) -> ReadingStatus {
        switch str {
        case "读过", "已读": return .finished
        case "在读", "正在读": return .reading
        case "想读": return .wishlist
        case "弃读": return .dropped
        case "搁置", "闲置": return .idle
        default: return .idle
        }
    }

    private func mapStatusToExport(_ status: ReadingStatus) -> String {
        switch status {
        case .idle: return "闲置"
        case .reading: return "正在读"
        case .finished: return "已读"
        case .wishlist: return "想读"
        case .dropped: return "弃读"
        }
    }

    private func formatPublishDate(_ date: Date?) -> String {
        guard let date else { return "" }
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        return String(year)
    }

    /// 根据 ISBN 生成封面 URL
    private func coverURL(isbn: String?, doubanURL: String?) -> String? {
        // 使用 ISBN 通过 Open Library 获取封面（国际通用）
        if let isbn, !isbn.isEmpty {
            let cleanISBN = isbn.replacingOccurrences(of: "[^0-9Xx]", with: "", options: .regularExpression)
            if cleanISBN.count == 10 || cleanISBN.count == 13 {
                return "https://covers.openlibrary.org/b/isbn/\(cleanISBN)-L.jpg"
            }
        }
        return nil
    }

    /// 分割多值字段（支持 ；; / 作为分隔符）
    private func splitMultiValue(_ str: String) -> [String] {
        // 支持中文分号、英文分号、斜杠、中文逗号、英文逗号作为分隔符
        let separators = CharacterSet(charactersIn: "；;/，,")
        return str.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func escapeField(_ field: String) -> String {
        field.replacingOccurrences(of: "\t", with: " ")
    }
}

// MARK: - Errors

enum ImportError: Error, LocalizedError {
    case cannotAccessFile
    case invalidFormat
    case noWorksheet
    case noData

    var errorDescription: String? {
        switch self {
        case .cannotAccessFile: return "无法访问文件"
        case .invalidFormat: return "文件格式无效"
        case .noWorksheet: return "未找到工作表"
        case .noData: return "文件中没有数据"
        }
    }
}

enum ExportError: Error, LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "数据编码失败"
        }
    }
}

// MARK: - Column Reference Helper

extension ColumnReference {
    /// Convert column letter(s) to integer index (A=1, B=2, ..., Z=26, AA=27, ...)
    var columnIndex: Int {
        let str = self.value.uppercased()
        var result = 0
        for char in str {
            result = result * 26 + Int(char.asciiValue! - 64)
        }
        return result
    }
}
