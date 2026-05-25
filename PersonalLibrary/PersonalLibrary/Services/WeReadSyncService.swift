import Foundation
import SwiftData

/// 批量补全配置
struct BatchEnrichmentConfig {
    /// 每批处理书籍数
    var batchSize: Int = 5
    /// 批间暂停（秒）
    var batchDelaySeconds: Double = 2.0
    /// 每次同步最多补全书籍数
    var maxBooksPerSync: Int = 30
}

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
        var booksArchived: Int = 0
        var totalRemote: Int = 0
        var error: String?

        var hasChanges: Bool {
            newBooksImported > 0 || progressUpdated > 0 || statusUpdated > 0 || booksArchived > 0
        }

        var summary: String {
            if let error { return error }
            if !hasChanges { return "已是最新，无需更新" }
            var parts: [String] = []
            if newBooksImported > 0 { parts.append("新增 \(newBooksImported) 本") }
            if progressUpdated > 0 { parts.append("进度更新 \(progressUpdated) 本") }
            if statusUpdated > 0 { parts.append("状态更新 \(statusUpdated) 本") }
            if booksArchived > 0 { parts.append("移除 \(booksArchived) 本") }
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
            AppLogger.warning("Cookie renewal error: \(error), trying anyway", category: "WeReadSync")
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

        // 6. 批量处理（减少 MainActor 切换次数，避免卡顿）
        let totalRemoteCount = remoteBooks.count
        onProgress?(SyncProgress(current: 0, total: totalRemoteCount, phase: "处理书籍"))

        // 分离已存在和需要匹配的书
        var existingItems: [(Book, WeReadImportItem)] = []
        var unmatchedItems: [WeReadImportItem] = []
        for item in remoteBooks {
            if let existingBook = localBookMap[item.id] {
                existingItems.append((existingBook, item))
            } else {
                unmatchedItems.append(item)
            }
        }

        // 6a. 批量更新已存在的书（一次 MainActor.run 处理全部）
        let existingResults = await MainActor.run {
            var progressCount = 0
            var statusCount = 0
            for (book, item) in existingItems {
                // 补充书架/标签（仅缺失时）
                if book.bookshelf == nil {
                    book.bookshelf = wereadShelf
                }
                if book.tags?.contains(where: { $0.name == "微信读书" }) != true {
                    var tags = book.tags ?? []
                    tags.append(wereadTag)
                    book.tags = tags
                }
                // 更新进度
                if item.progress > book.wereadProgress {
                    book.wereadProgress = item.progress
                    progressCount += 1
                }
                // 更新阅读时长
                let newHours = Double(item.readingTime + item.ttsTime) / 3600.0
                if newHours > book.wereadReadingHours {
                    book.wereadReadingHours = newHours
                }
                // 补充加入时间
                if let addedTime = item.addedTime, book.addedDate > addedTime {
                    book.addedDate = addedTime
                }
                // 状态更新
                if item.isFinished && book.status != .finished && book.status != .dropped {
                    book.status = .finished
                    book.statusChangedDate = Date()
                    if book.finishedDate == nil {
                        book.finishedDate = item.finishedTime ?? Date()
                    }
                    statusCount += 1
                } else if !item.isFinished && item.progress > 0 &&
                          (book.status == .idle || book.status == .wishlist) {
                    book.status = .reading
                    book.statusChangedDate = Date()
                    statusCount += 1
                }
            }
            return (progressCount, statusCount)
        }
        result.progressUpdated = existingResults.0
        result.statusUpdated = existingResults.1

        onProgress?(SyncProgress(current: existingItems.count, total: totalRemoteCount, phase: "处理书籍"))

        // 6b. 处理未匹配的书（需要逐本查数据库，但数量通常很少）
        for (index, item) in unmatchedItems.enumerated() {
            if index % 20 == 0 {
                onProgress?(SyncProgress(current: existingItems.count + index, total: totalRemoteCount, phase: "处理书籍"))
            }
            let matched = await findExistingBook(item: item, modelContext: modelContext)
            if let existingBook = matched {
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
                await importNewBook(item: item, tag: wereadTag, shelf: wereadShelf, modelContext: modelContext)
                result.newBooksImported += 1
            }

            // 增量保存：每 50 本新书保存一次
            if index > 0 && index % 50 == 0 {
                do {
                    try await MainActor.run { try modelContext.save() }
                } catch {
                    AppLogger.error("增量保存失败: \(error)", category: "WeReadSync")
                }
            }
        }

        // 6c. 删除检测：本地有 wereadBookId 但远程书架中不存在 → 逻辑删除
        let remoteBookIds = Set(remoteBooks.map(\.id))
        let archivedCount = await MainActor.run {
            var count = 0
            for book in localWeReadBooks {
                guard let wid = book.wereadBookId else { continue }
                if !remoteBookIds.contains(wid) && !book.isArchived {
                    book.isArchived = true
                    count += 1
                }
            }
            return count
        }
        result.booksArchived = archivedCount

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

                // 9b. 详情补全（每次最多 10 本，每 3 个请求暂停 1 秒）
                var infoDescriptor = FetchDescriptor<Book>(
                    predicate: #Predicate<Book> { $0.wereadBookId != nil && $0.publisher == nil }
                )
                infoDescriptor.fetchLimit = 10
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
                        AppLogger.warning("拉取书籍详情失败 (\(book.title)): \(error)", category: "WeReadSync")
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
                        AppLogger.warning("拉取划线失败 (\(book.title)): \(error)", category: "WeReadSync")
                    }
                }
                await MainActor.run { try? bgContext.save() }
            }
        }

        // 12. 记录同步时间
        Self.lastSyncDate = Date()

        return result
    }

    // MARK: - Batch Enrichment (9d)

    /// 批量从外部源补全缺失数据
    /// 分批处理，每批 5 本，批间暂停 2 秒，每批结束统一保存
    private func batchEnrichBooks(
        context: ModelContext,
        config: BatchEnrichmentConfig = BatchEnrichmentConfig()
    ) async {
        // 查找需要补全的微信读书书籍
        let booksNeedEnrich: [Book] = await MainActor.run {
            var descriptor = FetchDescriptor<Book>(
                predicate: #Predicate<Book> { $0.wereadBookId != nil }
            )
            descriptor.fetchLimit = config.maxBooksPerSync
            let allWereadBooks = (try? context.fetch(descriptor)) ?? []
            return allWereadBooks.filter { $0.needsEnrichment }
        }

        guard !booksNeedEnrich.isEmpty else {
            AppLogger.debug("无需补全的书籍", category: "WeReadSync")
            return
        }

        AppLogger.info("开始批量补全 \(booksNeedEnrich.count) 本书", category: "WeReadSync")

        let lookupService = ISBNLookupService()
        let doubanFetcher = DoubanDescriptionFetcher()

        // 分批处理
        for batchStart in stride(from: 0, to: booksNeedEnrich.count, by: config.batchSize) {
            let batchEnd = min(batchStart + config.batchSize, booksNeedEnrich.count)
            let batch = Array(booksNeedEnrich[batchStart..<batchEnd])

            // 批间暂停（第一批不需要）
            if batchStart > 0 {
                try? await Task.sleep(for: .seconds(config.batchDelaySeconds))
            }

            for book in batch {
                await enrichSingleBook(book, lookupService: lookupService, doubanFetcher: doubanFetcher, context: context)
            }

            // 每批结束统一保存
            await MainActor.run { try? context.save() }
            AppLogger.debug("补全进度: \(batchEnd)/\(booksNeedEnrich.count)", category: "WeReadSync")
        }

        AppLogger.info("批量补全完成", category: "WeReadSync")
    }

    /// 补全单本书的缺失信息
    private func enrichSingleBook(
        _ book: Book,
        lookupService: ISBNLookupService,
        doubanFetcher: DoubanDescriptionFetcher,
        context: ModelContext
    ) async {
        let needsPublisher = book.publisher == nil || book.publisher?.isEmpty == true
        let needsPages = book.totalPages == 0
        let needsBookDesc = book.bookDescription == nil || book.bookDescription?.isEmpty == true
        let needsAuthorDesc = book.authorDescription == nil || book.authorDescription?.isEmpty == true

        // 先查本地数据库是否有同作者的作者简介
        if needsAuthorDesc {
            let localAuthorDesc = await findLocalAuthorDescription(for: book.author, excludingBook: book, context: context)
            if let localAuthorDesc {
                await MainActor.run { book.authorDescription = localAuthorDesc }
            }
        }

        // 重新检查是否还需要补全
        let stillNeedsPublisher = needsPublisher
        let stillNeedsPages = needsPages
        let stillNeedsBookDesc = needsBookDesc
        let stillNeedsAuthorDesc = (book.authorDescription == nil || book.authorDescription?.isEmpty == true)

        guard stillNeedsPublisher || stillNeedsPages || stillNeedsBookDesc || stillNeedsAuthorDesc else {
            return
        }

        // 判断走 ISBN 还是书名搜索
        let isbn = book.isbn ?? ""
        let cleanISBN = isbn.replacingOccurrences(of: "[^0-9Xx]", with: "", options: .regularExpression).uppercased()
        let validISBN = !cleanISBN.isEmpty && (cleanISBN.count == 10 || cleanISBN.count == 13)

        if validISBN {
            // 有 ISBN：走 smartFill 逻辑（豆瓣ISBN → OL ISBN → Google ISBN → Goodreads）
            let result = await lookupService.smartFill(
                isbn: isbn, title: book.title, author: book.author,
                needsPublisher: stillNeedsPublisher, needsPages: stillNeedsPages,
                needsAuthor: false, needsBookDesc: stillNeedsBookDesc,
                needsAuthorDesc: stillNeedsAuthorDesc
            )
            await applySmartFillResult(result, to: book)
        } else {
            // 无 ISBN：豆瓣书名搜索 → Open Library 书名搜索 → Google Books 书名搜索
            await enrichByTitleSearch(
                book: book,
                lookupService: lookupService,
                doubanFetcher: doubanFetcher,
                needsPublisher: stillNeedsPublisher,
                needsPages: stillNeedsPages,
                needsBookDesc: stillNeedsBookDesc,
                needsAuthorDesc: stillNeedsAuthorDesc
            )
        }
    }

    /// 通过书名搜索外部源补全
    private func enrichByTitleSearch(
        book: Book,
        lookupService: ISBNLookupService,
        doubanFetcher: DoubanDescriptionFetcher,
        needsPublisher: Bool,
        needsPages: Bool,
        needsBookDesc: Bool,
        needsAuthorDesc: Bool
    ) async {
        var filledPublisher: String?
        var filledPages: Int?
        var filledBookDesc: String?
        var filledAuthorDesc: String?

        // 1. 豆瓣书名搜索（简介 + 作者简介）
        if needsBookDesc && filledBookDesc == nil {
            let desc = await doubanFetcher.fetchBookDescriptionByTitle(title: book.title, author: book.author)
            if let desc, !desc.isEmpty { filledBookDesc = desc }
        }
        if needsAuthorDesc && filledAuthorDesc == nil {
            let desc = await doubanFetcher.fetchAuthorDescriptionByTitle(title: book.title, author: book.author)
            if let desc, !desc.isEmpty { filledAuthorDesc = desc }
        }

        // 检查是否还需要继续
        let stillNeeds = (needsPublisher && filledPublisher == nil)
            || (needsPages && filledPages == nil)
            || (needsBookDesc && filledBookDesc == nil)
            || (needsAuthorDesc && filledAuthorDesc == nil)

        // 2. Open Library 书名搜索
        if stillNeeds {
            if let olResult = await lookupService.searchOpenLibraryByTitle(title: book.title, author: book.author) {
                if needsPublisher && filledPublisher == nil, let p = olResult.publisher, !p.isEmpty {
                    filledPublisher = p
                }
                if needsPages && filledPages == nil, let p = olResult.totalPages, p > 0 {
                    filledPages = p
                }
                if needsBookDesc && filledBookDesc == nil, let d = olResult.bookDescription, !d.isEmpty {
                    filledBookDesc = d
                }
            }
        }

        // 再检查
        let stillNeeds2 = (needsPublisher && filledPublisher == nil)
            || (needsPages && filledPages == nil)
            || (needsBookDesc && filledBookDesc == nil)
            || (needsAuthorDesc && filledAuthorDesc == nil)

        // 3. Google Books 书名搜索
        if stillNeeds2 {
            if let gbResult = await lookupService.searchGoogleBooksByTitle(title: book.title, author: book.author) {
                if needsPublisher && filledPublisher == nil, let p = gbResult.publisher, !p.isEmpty {
                    filledPublisher = p
                }
                if needsPages && filledPages == nil, let p = gbResult.totalPages, p > 0 {
                    filledPages = p
                }
                if needsBookDesc && filledBookDesc == nil, let d = gbResult.bookDescription, !d.isEmpty {
                    filledBookDesc = d
                }
            }
        }

        // 写入结果
        await MainActor.run {
            if let p = filledPublisher { book.publisher = p }
            if let p = filledPages { book.totalPages = p }
            if let d = filledBookDesc { book.bookDescription = d }
            if let d = filledAuthorDesc { book.authorDescription = d }
        }
    }

    /// 将 smartFill 结果写入 book
    private func applySmartFillResult(_ result: SmartFillResult, to book: Book) async {
        await MainActor.run {
            if let p = result.publisher { book.publisher = p }
            if let p = result.totalPages { book.totalPages = p }
            if let d = result.bookDescription { book.bookDescription = d }
            if let d = result.authorDescription { book.authorDescription = d }
        }
    }

    /// 从本地数据库查找同作者的作者简介
    private func findLocalAuthorDescription(for author: String, excludingBook: Book, context: ModelContext) async -> String? {
        return await MainActor.run {
            let authorName = author
            var descriptor = FetchDescriptor<Book>(
                predicate: #Predicate { $0.author == authorName && $0.authorDescription != nil }
            )
            let matches = (try? context.fetch(descriptor)) ?? []
            // 排除当前书，取最详细的简介
            return matches
                .filter { $0.persistentModelID != excludingBook.persistentModelID }
                .compactMap { $0.authorDescription }
                .filter { !$0.isEmpty }
                .max(by: { $0.count < $1.count })
        }
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
            // 更新阅读时长
            let newHours = Double(item.readingTime + item.ttsTime) / 3600.0
            if newHours > book.wereadReadingHours {
                book.wereadReadingHours = newHours
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
            book.wereadReadingHours = Double(item.readingTime + item.ttsTime) / 3600.0
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
        await BookService.downloadImage(from: urlString)
    }

    /// 查找或创建标签（委托给 BookService）
    nonisolated private func findOrCreateTag(name: String, modelContext: ModelContext) throws -> Tag {
        try BookService.findOrCreateTag(name: name, modelContext: modelContext)
    }

    /// 查找或创建书架（委托给 BookService）
    nonisolated private func findOrCreateBookshelf(name: String, icon: String, modelContext: ModelContext) throws -> Bookshelf {
        try BookService.findOrCreateBookshelf(name: name, icon: icon, modelContext: modelContext)
    }
}
