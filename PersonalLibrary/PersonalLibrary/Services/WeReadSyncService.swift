import Foundation
import SwiftData

/// 微信读书同步服务
/// 负责增量同步：新书导入 + 已有书进度更新
actor WeReadSyncService {

    private let weReadService = WeReadService()

    // MARK: - Sync Settings (UserDefaults)

    /// 自动同步开关
    static var autoSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "weread_auto_sync_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "weread_auto_sync_enabled") }
    }

    /// 上次同步时间
    static var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: "weread_last_sync_date") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "weread_last_sync_date") }
    }

    /// 同步间隔（秒），默认 1 小时
    static let syncInterval: TimeInterval = 3600

    /// 是否应该触发自动同步（已开启 + 距上次同步超过 1 小时 + 已登录）
    static func shouldAutoSync() -> Bool {
        guard autoSyncEnabled else { return false }
        guard let lastSync = lastSyncDate else { return true }
        return Date().timeIntervalSince(lastSync) > syncInterval
    }

    // MARK: - Sync Result

    struct SyncResult {
        var newBooksImported: Int = 0
        var progressUpdated: Int = 0
        var statusUpdated: Int = 0
        var totalRemote: Int = 0
        var error: String?

        var hasChanges: Bool {
            newBooksImported > 0 || progressUpdated > 0 || statusUpdated > 0
        }

        var summary: String {
            if let error { return error }
            if !hasChanges { return "已是最新，无需更新" }
            var parts: [String] = []
            if newBooksImported > 0 { parts.append("新增 \(newBooksImported) 本") }
            if progressUpdated > 0 { parts.append("进度更新 \(progressUpdated) 本") }
            if statusUpdated > 0 { parts.append("状态更新 \(statusUpdated) 本") }
            return parts.joined(separator: "，")
        }
    }

    // MARK: - Core Sync

    /// 同步进度信息
    struct SyncProgress: Sendable {
        let current: Int
        let total: Int
        let phase: String  // "检查登录" / "拉取书架" / "处理书籍" / "保存数据"
    }

    /// 执行增量同步（带进度回调）
    func sync(modelContext: ModelContext, onProgress: (@Sendable (SyncProgress) -> Void)? = nil) async -> SyncResult {
        var result = SyncResult()

        // 1. 检查登录状态
        onProgress?(SyncProgress(current: 0, total: 0, phase: "检查登录"))
        guard await weReadService.isLoggedIn() else {
            result.error = "未登录微信读书"
            return result
        }

        // 2. 尝试续期 Cookie
        do {
            _ = try await weReadService.renewCookie()
        } catch {
            print("[WeReadSync] Cookie renewal error: \(error), trying anyway")
        }

        // 3. 拉取微信读书书架
        onProgress?(SyncProgress(current: 0, total: 0, phase: "拉取书架"))
        let remoteBooks: [WeReadImportItem]
        do {
            remoteBooks = try await weReadService.fetchAllBooks()
        } catch let wereadError as WeReadError {
            switch wereadError {
            case .cookieExpired, .authFailed:
                result.error = "登录已过期，请重新扫码登录"
            default:
                result.error = "同步失败：\(wereadError.localizedDescription)"
            }
            return result
        } catch {
            result.error = "同步失败：\(error.localizedDescription)"
            return result
        }

        result.totalRemote = remoteBooks.count

        // 4. 获取本地已有的微信读书书籍
        let localWeReadBooks: [Book]
        do {
            localWeReadBooks = try await MainActor.run {
                let descriptor = FetchDescriptor<Book>(
                    predicate: #Predicate { $0.wereadBookId != nil }
                )
                return try modelContext.fetch(descriptor)
            }
        } catch {
            result.error = "读取本地数据失败: \(error.localizedDescription)"
            return result
        }

        // 建立 bookId → 本地 Book 的映射
        var localBookMap: [String: Book] = [:]
        for book in localWeReadBooks {
            if let wid = book.wereadBookId {
                localBookMap[wid] = book
            }
        }

        // 5. 获取或创建"微信读书"标签和书架
        let wereadTag: Tag
        let wereadShelf: Bookshelf
        do {
            (wereadTag, wereadShelf) = try await MainActor.run {
                let tag = try findOrCreateTag(name: "微信读书", modelContext: modelContext)
                let shelf = try findOrCreateBookshelf(name: "微信读书", icon: "iphone", modelContext: modelContext)
                return (tag, shelf)
            }
        } catch {
            result.error = "创建标签/书架失败"
            return result
        }

        // 6. 逐本处理（每 20 本保存一次，避免内存压力和全量丢失）
        let totalRemoteCount = remoteBooks.count
        var processedCount = 0
        var processedSinceLastSave = 0
        for item in remoteBooks {
            processedCount += 1
            onProgress?(SyncProgress(current: processedCount, total: totalRemoteCount, phase: "处理书籍"))
            if let existingBook = localBookMap[item.id] {
                // 已存在 → 补充书架/标签（修复早期导入缺失）+ 更新进度和状态
                await MainActor.run {
                    if existingBook.bookshelf == nil {
                        existingBook.bookshelf = wereadShelf
                    }
                    if existingBook.tags?.contains(where: { $0.name == "微信读书" }) != true {
                        var tags = existingBook.tags ?? []
                        tags.append(wereadTag)
                        existingBook.tags = tags
                    }
                }
                let updated = await updateExistingBook(book: existingBook, item: item)
                if updated.progressChanged { result.progressUpdated += 1 }
                if updated.statusChanged { result.statusUpdated += 1 }
            } else {
                // 不存在 → 通过 ISBN+bookType 或 书名+作者+bookType 匹配
                let matched = await findExistingBook(item: item, modelContext: modelContext)
                if let existingBook = matched {
                    // 补充 wereadBookId、书架、标签
                    await MainActor.run {
                        existingBook.wereadBookId = item.id
                        if existingBook.bookshelf == nil {
                            existingBook.bookshelf = wereadShelf
                        }
                        if existingBook.tags?.contains(where: { $0.name == "微信读书" }) != true {
                            var tags = existingBook.tags ?? []
                            tags.append(wereadTag)
                            existingBook.tags = tags
                        }
                    }
                    let updated = await updateExistingBook(book: existingBook, item: item)
                    if updated.progressChanged { result.progressUpdated += 1 }
                    if updated.statusChanged { result.statusUpdated += 1 }
                } else {
                    // 全新书 → 导入
                    await importNewBook(item: item, tag: wereadTag, shelf: wereadShelf, modelContext: modelContext)
                    result.newBooksImported += 1
                }
            }

            // 增量保存：每处理 20 本保存一次
            processedSinceLastSave += 1
            if processedSinceLastSave >= 20 {
                do {
                    try await MainActor.run { try modelContext.save() }
                } catch {
                    print("[WeReadSync] 增量保存失败: \(error)")
                }
                processedSinceLastSave = 0
            }
        }

        // 7. 最终保存
        do {
            try await MainActor.run { try modelContext.save() }
        } catch {
            result.error = "保存数据失败: \(error.localizedDescription)"
        }

        // 8. 记录导入历史（仅当有新书导入时）
        if result.newBooksImported > 0 {
            await MainActor.run {
                let record = ImportRecord(
                    source: "微信读书导入",
                    totalCount: result.newBooksImported,
                    successCount: result.newBooksImported,
                    note: "自动同步"
                )
                modelContext.insert(record)
                try? modelContext.save()
            }
        }

        // 9. 后台串行执行：封面下载 → 详情补全 → 划线拉取
        // 避免并发请求过多导致手机卡顿
        do {
            let container = modelContext.container
            let hasNewBooks = result.newBooksImported > 0
            Task.detached(priority: .utility) {
                let bgContext = await MainActor.run { ModelContext(container) }

                // 9a. 封面下载（限制每次最多 20 本，每 3 本暂停 1 秒）
                if hasNewBooks {
                    var coverDescriptor = FetchDescriptor<Book>(
                        predicate: #Predicate { $0.coverImageData == nil && $0.coverImageURL != nil }
                    )
                    coverDescriptor.fetchLimit = 20
                    let booksNeedCover = (try? await MainActor.run { try bgContext.fetch(coverDescriptor) }) ?? []
                    for (index, book) in booksNeedCover.enumerated() {
                        guard let urlStr = book.coverImageURL, !urlStr.isEmpty else { continue }
                        if index > 0 && index % 3 == 0 {
                            try? await Task.sleep(for: .seconds(1))
                        }
                        if let data = await self.downloadImage(from: urlStr) {
                            await MainActor.run { book.coverImageData = data }
                        }
                    }
                    await MainActor.run { try? bgContext.save() }
                }

                // 9b. 详情补全（每次最多 15 本，每 3 个请求暂停 1 秒）
                var infoDescriptor = FetchDescriptor<Book>(
                    predicate: #Predicate { $0.wereadBookId != nil && $0.publisher == nil }
                )
                infoDescriptor.fetchLimit = 15
                let booksNeedInfo = (try? await MainActor.run { try bgContext.fetch(infoDescriptor) }) ?? []
                for (index, book) in booksNeedInfo.enumerated() {
                    guard let bookId = book.wereadBookId else { continue }
                    if index > 0 && index % 3 == 0 {
                        try? await Task.sleep(for: .seconds(1))
                    }
                    do {
                        let info = try await self.weReadService.fetchBookInfo(bookId: bookId)
                        await MainActor.run {
                            if let publisher = info.publisher, !publisher.isEmpty {
                                book.publisher = publisher
                            }
                            if let isbn = info.isbn, !isbn.isEmpty {
                                book.isbn = isbn
                            }
                            if let intro = info.intro, !intro.isEmpty, book.bookDescription == nil {
                                book.bookDescription = intro
                            }
                            if let price = info.price, price > 0 {
                                book.price = "¥\(String(format: "%.2f", price))"
                            }
                            if let publishTime = info.publishTime, !publishTime.isEmpty {
                                book.publishDate = self.parsePublishDate(publishTime)
                            }
                            // 修正书籍类型：type==2 或 type==3 为有声书
                            if let type = info.type, (type == 2 || type == 3), book.bookType != .audiobook {
                                book.bookType = .audiobook
                            }
                        }
                    } catch {
                        print("[WeReadSync] 拉取书籍详情失败 (\(book.title)): \(error)")
                    }
                }
                await MainActor.run { try? bgContext.save() }

                // 9c. 划线拉取（每次最多 10 本，每 3 个请求暂停 1 秒）
                var bookmarkDescriptor = FetchDescriptor<Book>(
                    predicate: #Predicate { $0.wereadBookId != nil && $0.notes == nil }
                )
                bookmarkDescriptor.fetchLimit = 10
                let booksNeedBookmarks = (try? await MainActor.run { try bgContext.fetch(bookmarkDescriptor) }) ?? []
                for (index, book) in booksNeedBookmarks.enumerated() {
                    guard let bookId = book.wereadBookId else { continue }
                    if index > 0 && index % 3 == 0 {
                        try? await Task.sleep(for: .seconds(1))
                    }
                    do {
                        let bookmarks = try await self.weReadService.fetchBookmarks(bookId: bookId)
                        if !bookmarks.isEmpty {
                            let notesText = self.formatBookmarks(bookmarks)
                            await MainActor.run { book.notes = notesText }
                        }
                    } catch {
                        print("[WeReadSync] 拉取划线失败 (\(book.title)): \(error)")
                    }
                }
                await MainActor.run { try? bgContext.save() }
            }
        }

        // 12. 记录同步时间
        Self.lastSyncDate = Date()

        return result
    }

    // MARK: - Update Existing Book

    private struct UpdateResult {
        var progressChanged = false
        var statusChanged = false
    }

    private func updateExistingBook(book: Book, item: WeReadImportItem) async -> UpdateResult {
        var result = UpdateResult()

        await MainActor.run {
            // 更新进度（只往前推进，不后退）
            if item.progress > book.wereadProgress {
                book.wereadProgress = item.progress
                result.progressChanged = true
            }

            // 补充加入时间（如果本地是默认的当前时间、远端有真实时间）
            if let addedTime = item.addedTime, book.addedDate > addedTime {
                book.addedDate = addedTime
            }

            // 状态更新逻辑：
            // - 微信读书标记"已读完" → 本地也标记已读（除非用户已手动设为弃读）
            // - 微信读书有进度但本地还是"闲置/想读" → 更新为"正在读"
            if item.isFinished && book.status != .finished && book.status != .dropped {
                book.status = .finished
                book.statusChangedDate = Date()
                if book.finishedDate == nil {
                    book.finishedDate = item.finishedTime ?? Date()
                }
                result.statusChanged = true
            } else if !item.isFinished && item.progress > 0 &&
                      (book.status == .idle || book.status == .wishlist) {
                book.status = .reading
                book.statusChangedDate = Date()
                result.statusChanged = true
            }
        }

        return result
    }

    // MARK: - Import New Book

    private func importNewBook(
        item: WeReadImportItem,
        tag: Tag,
        shelf: Bookshelf,
        modelContext: ModelContext
    ) async {
        // 不下载封面，先插入数据（封面在 sync 完成后统一后台下载）
        await MainActor.run {
            let book = Book(
                title: item.title,
                author: item.author,
                translator: item.translator,
                isbn: item.isbn,
                publisher: item.publisher,
                bookType: item.bookType,
                bookDescription: item.intro,
                coverImageURL: item.cover
            )

            book.wereadBookId = item.id
            book.wereadProgress = item.progress
            book.addSource = .wereadImported

            // 加入时间：优先微信读书的加入书架时间
            if let addedTime = item.addedTime {
                book.addedDate = addedTime
            }

            // 阅读状态
            if item.isFinished {
                book.status = .finished
                book.finishedDate = item.finishedTime ?? Date()
            } else if item.progress > 0 || item.readingTime > 0 || item.ttsTime > 0 {
                book.status = .reading
            } else {
                book.status = .idle
            }
            book.statusChangedDate = Date()

            // 书架
            book.bookshelf = shelf

            // 标签
            var bookTags: [Tag] = [tag]
            if let category = item.category, !category.isEmpty {
                if let categoryTag = try? findOrCreateTag(name: category, modelContext: modelContext) {
                    bookTags.append(categoryTag)
                }
            }
            book.tags = bookTags

            modelContext.insert(book)
        }
    }

    // MARK: - Helpers

    /// 查找已有书籍（防止电子书和纸质书混淆）
    /// 优先 ISBN+bookType（电子书/有声书），其次 书名+作者+bookType（只匹配电子书/有声书）
    /// 使用内存过滤避免 SwiftData #Predicate 对 enum 比较的已知问题
    private func findExistingBook(
        item: WeReadImportItem,
        modelContext: ModelContext
    ) async -> Book? {
        return try? await MainActor.run {
            // 1. 优先 ISBN + bookType（电子书/有声书）匹配
            if let isbn = item.isbn, !isbn.isEmpty {
                let isbnStr = isbn
                var isbnDescriptor = FetchDescriptor<Book>(
                    predicate: #Predicate { $0.isbn == isbnStr }
                )
                let isbnMatches = try modelContext.fetch(isbnDescriptor)
                if let match = isbnMatches.first(where: {
                    $0.bookType == .ebook || $0.bookType == .audiobook
                }) {
                    return match
                }
            }

            // 2. 书名 + 作者 + bookType（只匹配电子书/有声书，不匹配纸质书）
            let title = item.title
            let author = item.author
            var titleDescriptor = FetchDescriptor<Book>(
                predicate: #Predicate { $0.title == title && $0.author == author }
            )
            let titleMatches = try modelContext.fetch(titleDescriptor)
            return titleMatches.first(where: {
                $0.bookType == .ebook || $0.bookType == .audiobook
            })
        }
    }

    /// 解析出版日期字符串（微信读书格式如 "2020-01" 或 "2020-01-15" 或 "2020"）
    nonisolated private func parsePublishDate(_ dateString: String) -> Date? {
        let formatters: [String] = ["yyyy-MM-dd", "yyyy-MM", "yyyy"]
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        return nil
    }

    /// 将划线列表格式化为可读文本
    nonisolated private func formatBookmarks(_ bookmarks: [WeReadBookmark]) -> String {
        var sections: [String: [String]] = [:]  // chapterName → [markText]
        var noChapter: [String] = []

        for bm in bookmarks {
            guard let text = bm.markText, !text.isEmpty else { continue }
            if let chapter = bm.chapterName, !chapter.isEmpty {
                sections[chapter, default: []].append(text)
            } else {
                noChapter.append(text)
            }
        }

        var lines: [String] = []
        lines.append("【微信读书划线】")
        lines.append("")

        // 按章节分组输出
        for (chapter, texts) in sections.sorted(by: { $0.key < $1.key }) {
            lines.append("## \(chapter)")
            for text in texts {
                lines.append("· \(text)")
            }
            lines.append("")
        }

        // 无章节的划线
        if !noChapter.isEmpty {
            for text in noChapter {
                lines.append("· \(text)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func downloadImage(from urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10  // 10 秒超时
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            return data
        } catch {
            return nil
        }
    }

    /// 查找或创建标签
    nonisolated private func findOrCreateTag(name: String, modelContext: ModelContext) throws -> Tag {
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

    /// 查找或创建书架
    nonisolated private func findOrCreateBookshelf(name: String, icon: String, modelContext: ModelContext) throws -> Bookshelf {
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
}
