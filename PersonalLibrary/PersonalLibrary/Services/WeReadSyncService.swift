import Foundation
import SwiftData

/// 微信读书同步服务
/// 负责增量同步：新书导入 + 已有书进度更新
actor WeReadSyncService {

    private let weReadService: any WeReadDataSource

    /// 全局同步锁：防止多个 sync 实例同时运行（自动同步 + 手动触发）
    private static let syncLock = NSLock()
    private static var _isSyncing = false
    static var isSyncing: Bool {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _isSyncing
    }
    private static func setSyncing(_ value: Bool) {
        syncLock.lock()
        _isSyncing = value
        syncLock.unlock()
    }

    /// 当前同步进度（供 UI 轮询读取，无论是否传了 onProgress 回调）
    private static var _currentProgress: SyncProgress?
    private static let progressLock = NSLock()

    static var currentProgress: SyncProgress? {
        progressLock.lock()
        defer { progressLock.unlock() }
        return _currentProgress
    }

    private static func setProgress(_ progress: SyncProgress?) {
        progressLock.lock()
        _currentProgress = progress
        progressLock.unlock()
    }

    /// 仅供测试使用：重置同步锁状态
    static func resetSyncLockForTesting() {
        setSyncing(false)
        setProgress(nil)
        clearSyncTask()
    }

    // MARK: - Global Sync Task (for external cancellation)

    private static var _syncTask: Task<Void, Never>?
    private static let taskLock = NSLock()

    /// Register the current sync task so external code can cancel it
    static func registerSyncTask(_ task: Task<Void, Never>) {
        taskLock.lock()
        _syncTask = task
        taskLock.unlock()
    }

    /// Clear the registered sync task reference
    static func clearSyncTask() {
        taskLock.lock()
        _syncTask = nil
        taskLock.unlock()
    }

    /// Cancel the currently running sync task (if any)
    static func cancelCurrentSync() {
        taskLock.lock()
        _syncTask?.cancel()
        taskLock.unlock()
    }

    init(provider: any WeReadDataSource = WeReadService()) {
        self.weReadService = provider
    }

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

    /// 重置同步状态：清除所有微信读书的 wereadEnrichedDate，使下次同步重新补全
    static func resetEnrichmentState(container: ModelContainer) throws -> Int {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let descriptor = FetchDescriptor<Book>(
            predicate: #Predicate { $0.wereadBookId != nil }
        )
        let books = try context.fetch(descriptor)
        var count = 0
        for book in books {
            if book.wereadEnrichedDate != nil {
                book.wereadEnrichedDate = nil
                count += 1
            }
        }
        if count > 0 { try context.save() }
        return count
    }

    /// 同步间隔（秒），默认 12 小时
    static let syncInterval: TimeInterval = 43200

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
        let phase: String  // "检查登录" / "拉取书架" / "处理书籍" / "下载封面" / "补全信息" / "拉取划线"
        let detail: String?  // 当前正在处理的书名

        init(current: Int, total: Int, phase: String, detail: String? = nil) {
            self.current = current
            self.total = total
            self.phase = phase
            self.detail = detail
        }
    }

    /// 执行增量同步（带进度回调）
    /// 使用 background ModelContext 避免频繁 save 触发主线程 @Query 刷新
    func sync(modelContext: ModelContext, skipLockCheck: Bool = false, onProgress: (@Sendable (SyncProgress) -> Void)? = nil) async -> SyncResult {
        return await sync(container: modelContext.container, skipLockCheck: skipLockCheck, onProgress: onProgress)
    }

    /// 执行增量同步（container 版本，内部创建 background context）
    func sync(container: ModelContainer, skipLockCheck: Bool = false, onProgress: (@Sendable (SyncProgress) -> Void)? = nil) async -> SyncResult {
        var result = SyncResult()

        // 0. 防止重复触发：如果已有同步在运行，直接返回
        if !skipLockCheck {
            guard !Self.isSyncing else {
                AppLogger.warning("[SYNC-LOCK] 被锁拦住，当前已有 sync 在运行", category: "WeReadSync")
                result.error = "同步正在进行中，请稍候"
                return result
            }
            Self.setSyncing(true)
            AppLogger.warning("[SYNC-LOCK] 获得锁，开始同步", category: "WeReadSync")
        }
        defer {
            if !skipLockCheck {
                Self.setProgress(nil)
                Self.setSyncing(false)
                AppLogger.warning("[SYNC-LOCK] 释放锁，同步结束", category: "WeReadSync")
            }
        }

        // 使用 background context，减少对主线程 UI 的影响
        let modelContext = ModelContext(container)
        modelContext.autosaveEnabled = false

        // 1. 检查连接状态
        let p1 = SyncProgress(current: 0, total: 0, phase: "检查登录")
        onProgress?(p1)
        Self.setProgress(p1)
        guard await weReadService.isConnected() else {
            result.error = "未连接微信读书"
            return result
        }

        // 2. 尝试续期（仅 Web 模式需要，Skill 模式无需此步骤）
        if let webProvider = weReadService as? WeReadService {
            do {
                _ = try await webProvider.renewCookie()
            } catch {
                AppLogger.warning("Cookie renewal error: \(error), trying anyway", category: "WeReadSync")
            }
        }

        // 3. 拉取微信读书书架
        let p3 = SyncProgress(current: 0, total: 0, phase: "拉取书架")
        onProgress?(p3)
        Self.setProgress(p3)
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
            let descriptor = FetchDescriptor<Book>(
                predicate: #Predicate { $0.wereadBookId != nil }
            )
            localWeReadBooks = try modelContext.fetch(descriptor)
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
            wereadTag = try findOrCreateTag(name: "微信读书", modelContext: modelContext)
            wereadShelf = try findOrCreateBookshelf(name: "微信读书", icon: "iphone", modelContext: modelContext)
        } catch {
            result.error = "创建标签/书架失败"
            return result
        }

        // 6. 批量处理（减少 MainActor 切换次数，避免卡顿）
        let totalRemoteCount = remoteBooks.count
        let p6 = SyncProgress(current: 0, total: totalRemoteCount, phase: "处理书籍")
        onProgress?(p6)
        Self.setProgress(p6)

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

        // 6a. 批量更新已存在的书
        var progressCount = 0
        var statusCount = 0
        for (book, item) in existingItems {
            // 同步用户导入标识（老数据补全）
            // 优先用 type 字段，兜底用 CB_ 前缀
            if !book.isWereadUserImported {
                if item.isUserImported || item.id.hasPrefix("CB_") {
                    book.isWereadUserImported = true
                }
            }
            // 补充书架/标签（仅缺失时）
            if book.bookshelf == nil {
                book.bookshelf = wereadShelf
            }
            if book.tags?.contains(where: { $0.name == "微信读书" }) != true {
                var tags = book.tags ?? []
                tags.append(wereadTag)
                book.tags = tags
            }
            // 更新进度（有不同就更新，防止0值覆盖）
            if item.progress != book.wereadProgress && item.progress > 0 {
                book.wereadProgress = item.progress
                progressCount += 1
            }
            // 更新阅读时长（有不同就更新，防止0值覆盖，使用容差避免浮点精度问题）
            let newHours = Double(item.readingTime + item.ttsTime) / 3600.0
            if abs(newHours - book.wereadReadingHours) > 0.001 && newHours > 0 {
                book.wereadReadingHours = newHours
            }
            // 补充价格（仅空时填充）
            if (book.price == nil || book.price!.isEmpty), let p = item.price, p > 0, p.isFinite {
                book.price = "¥\(String(format: "%.2f", p))"
            }
            // 补充出版时间（仅空时填充）
            if book.publishDate == nil, let pt = item.publishTime, !pt.isEmpty {
                book.publishDate = Self.parsePublishDate(pt)
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
        let existingResults = (progressCount, statusCount)
        result.progressUpdated = existingResults.0
        result.statusUpdated = existingResults.1

        let p6a = SyncProgress(current: existingItems.count, total: totalRemoteCount, phase: "处理书籍")
        onProgress?(p6a)
        Self.setProgress(p6a)

        // 6b. 处理未匹配的书（需要逐本查数据库，但数量通常很少）
        for (index, item) in unmatchedItems.enumerated() {
            guard !Task.isCancelled else { break }
            if index % 20 == 0 {
                let p6b = SyncProgress(current: existingItems.count + index, total: totalRemoteCount, phase: "处理书籍")
                onProgress?(p6b)
                Self.setProgress(p6b)
            }
            let matched = findExistingBook(item: item, modelContext: modelContext)
            if let existingBook = matched {
                existingBook.wereadBookId = item.id
                if existingBook.bookshelf == nil {
                    existingBook.bookshelf = wereadShelf
                }
                if existingBook.tags?.contains(where: { $0.name == "微信读书" }) != true {
                    var tags = existingBook.tags ?? []
                    tags.append(wereadTag)
                    existingBook.tags = tags
                }
                let updated = updateExistingBook(book: existingBook, item: item)
                if updated.progressChanged { result.progressUpdated += 1 }
                if updated.statusChanged { result.statusUpdated += 1 }
            } else {
                importNewBook(item: item, tag: wereadTag, shelf: wereadShelf, modelContext: modelContext)
                result.newBooksImported += 1
            }
        }

        // 6c. 删除检测：本地有 wereadBookId 但远程书架中不存在 → 逻辑删除
        let remoteBookIds = Set(remoteBooks.map(\.id))
        var archivedCount = 0
        for book in localWeReadBooks {
            guard let wid = book.wereadBookId else { continue }
            if !remoteBookIds.contains(wid) && !book.isArchived {
                book.isArchived = true
                archivedCount += 1
            }
        }
        result.booksArchived = archivedCount

        // 7. 最终保存
        do {
            try modelContext.save()
        } catch {
            result.error = "保存数据失败: \(error.localizedDescription)"
        }

        // 8. 记录导入历史（仅当有新书导入时）
        if result.newBooksImported > 0 {
            let record = ImportRecord(
                source: "微信读书导入",
                totalCount: result.newBooksImported,
                successCount: result.newBooksImported,
                note: "自动同步"
            )
            modelContext.insert(record)
            try? modelContext.save()
        }

        // 9. 串行执行：封面下载 → 信息补全 → 划线拉取（带进度回调，支持取消）

        // 9a. 封面下载（每 3 本暂停 1 秒）
        if result.newBooksImported > 0 && !Task.isCancelled {
            let coverDescriptor = FetchDescriptor<Book>(
                predicate: #Predicate { $0.coverImageData == nil && $0.coverImageURL != nil }
            )
            let booksNeedCover = (try? modelContext.fetch(coverDescriptor)) ?? []
            for (index, book) in booksNeedCover.enumerated() {
                guard !Task.isCancelled else { break }
                let p9a = SyncProgress(current: index + 1, total: booksNeedCover.count, phase: "下载封面", detail: book.title)
                onProgress?(p9a)
                Self.setProgress(p9a)
                guard let urlStr = book.coverImageURL, !urlStr.isEmpty else { continue }
                if index > 0 && index % 3 == 0 {
                    try? await Task.sleep(for: .seconds(1))
                }
                if let data = await self.downloadImage(from: urlStr) {
                    book.coverImageData = data
                }
            }
            try? modelContext.save()
        }

        // 9b. 逐本处理：补全 + 划线（在当前 Task 上下文执行，支持取消传播）
        if !Task.isCancelled {
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false

            let enrichDescriptor = FetchDescriptor<Book>(
                predicate: #Predicate<Book> { $0.wereadBookId != nil && $0.wereadEnrichedDate == nil }
            )
            let booksNeedEnrich = (try? bgContext.fetch(enrichDescriptor)) ?? []

            if !booksNeedEnrich.isEmpty {
                // 一次性拉取书架进度数据（缓存，仅 Web 模式需要）
                var progressMap: [String: WeReadBookProgress]?
                if let webService = weReadService as? WeReadService {
                    do {
                        let shelfData = try await webService.fetchShelf()
                        var map: [String: WeReadBookProgress] = [:]
                        if let progressList = shelfData.bookProgress {
                            for p in progressList { map[p.bookId] = p }
                        }
                        progressMap = map
                    } catch {
                        AppLogger.warning("预拉取书架进度失败: \(error)", category: "WeReadSync")
                    }
                }

                for (index, book) in booksNeedEnrich.enumerated() {
                    guard !Task.isCancelled else { break }
                    let p9b = SyncProgress(current: index + 1, total: booksNeedEnrich.count, phase: "补全同步", detail: book.title)
                    onProgress?(p9b)
                    Self.setProgress(p9b)
                    guard let bookId = book.wereadBookId else { continue }

                    // 防止与智能补全并发冲突：用独立 context 检查是否已被其他 context 补全
                    // bgContext 已缓存 book 对象，re-fetch 可能返回旧快照；新 context 无缓存，必定读 store
                    let checkContext = ModelContext(container)
                    if let freshBook = try? checkContext.fetch(FetchDescriptor<Book>(
                        predicate: #Predicate { $0.wereadBookId == bookId }
                    )).first, freshBook.wereadEnrichedDate != nil {
                        continue
                    }

                    // 限速：每本间隔 2 秒（避免密集网络请求导致手机发烫）
                    if index > 0 {
                        try? await Task.sleep(for: .seconds(2))
                    }

                    // (1) 补全书籍信息
                    var enrichSucceeded = false
                    do {
                        let enrichResult: WeReadEnrichResult
                        if let webService = weReadService as? WeReadService, let map = progressMap {
                            enrichResult = try await webService.enrichBook(bookId: bookId, cachedProgress: map)
                        } else {
                            enrichResult = try await weReadService.enrichBook(bookId: bookId)
                        }
                        enrichResult.applyToBook(book)
                        enrichSucceeded = true
                    } catch {
                        AppLogger.warning("微信读书补全失败 (\(book.title)): \(error)", category: "WeReadSync")
                    }

                    // (1b) CB_ 用户导入书：WeRead 补全后若简介仍为空，查询外部源（豆瓣/Goodreads）
                    if bookId.hasPrefix("CB_") {
                        let needsBookDesc = (book.bookDescription ?? "").isEmpty
                        let needsAuthorDesc = (book.authorDescription ?? "").isEmpty
                        if needsBookDesc || needsAuthorDesc {
                            let lookupService = ISBNLookupService()
                            let extResult = await lookupService.smartFill(
                                isbn: book.isbn ?? "",
                                title: book.title,
                                author: book.author,
                                needsTitle: false,
                                needsPublisher: false,
                                needsPages: false,
                                needsPrice: false,
                                needsPublishDate: false,
                                needsTranslator: false,
                                needsAuthor: false,
                                needsBookDesc: needsBookDesc,
                                needsAuthorDesc: needsAuthorDesc
                            )
                            if let desc = extResult.bookDescription {
                                book.bookDescription = desc
                            }
                            if let desc = extResult.authorDescription {
                                book.authorDescription = desc
                            }
                        }
                    }

                    // (2) 拉取划线（有不同就覆盖）
                    do {
                        let bookmarks = try await weReadService.fetchBookmarks(bookId: bookId)
                        if !bookmarks.isEmpty {
                            let formatted = WeReadSyncService.formatBookmarksStatic(bookmarks)
                            if book.notes != formatted {
                                book.notes = formatted
                            }
                        }
                    } catch {
                        AppLogger.warning("拉取划线失败 (\(book.title)): \(error)", category: "WeReadSync")
                    }

                    // (3) 仅当补全成功时标记已完成（失败的书下次 sync 会重试）
                    if enrichSucceeded {
                        book.wereadEnrichedDate = Date()
                    }

                    // 每 10 本保存一次，减少 UI 刷新频率
                    if (index + 1) % 10 == 0 {
                        try? bgContext.save()
                    }
                }
                // 最终保存剩余
                try? bgContext.save()
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

    private func updateExistingBook(book: Book, item: WeReadImportItem) -> UpdateResult {
        var result = UpdateResult()

        // 同步用户导入标识（老数据补全）— 用 type 字段或 CB_ 前缀
        if !book.isWereadUserImported {
            if item.isUserImported || item.id.hasPrefix("CB_") {
                book.isWereadUserImported = true
            }
        }

        // 更新进度（有不同就更新，防止0值覆盖）
        if item.progress != book.wereadProgress && item.progress > 0 {
            book.wereadProgress = item.progress
            result.progressChanged = true
        }
        // 更新阅读时长（有不同就更新，防止0值覆盖，使用容差避免浮点精度问题）
        let newHours = Double(item.readingTime + item.ttsTime) / 3600.0
        if abs(newHours - book.wereadReadingHours) > 0.001 && newHours > 0 {
            book.wereadReadingHours = newHours
        }

        // 补充价格（仅空时填充）
        if (book.price == nil || book.price!.isEmpty), let p = item.price, p > 0, p.isFinite {
            book.price = "¥\(String(format: "%.2f", p))"
        }
        // 补充出版时间（仅空时填充）
        if book.publishDate == nil, let pt = item.publishTime, !pt.isEmpty {
            book.publishDate = Self.parsePublishDate(pt)
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

        return result
    }

    // MARK: - Import New Book

    private func importNewBook(
        item: WeReadImportItem,
        tag: Tag,
        shelf: Bookshelf,
        modelContext: ModelContext
    ) {
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
        book.isWereadUserImported = item.isUserImported || item.id.hasPrefix("CB_")

        // 价格
        if let p = item.price, p > 0, p.isFinite {
            book.price = "¥\(String(format: "%.2f", p))"
        }
        // 出版时间
        if let pt = item.publishTime, !pt.isEmpty {
            book.publishDate = Self.parsePublishDate(pt)
        }

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

    // MARK: - Helpers

    /// 查找已有书籍（防止电子书和纸质书混淆）
    /// 优先 ISBN+bookType（电子书/有声书），其次 书名+作者+bookType（只匹配电子书/有声书）
    /// 使用内存过滤避免 SwiftData #Predicate 对 enum 比较的已知问题
    private func findExistingBook(
        item: WeReadImportItem,
        modelContext: ModelContext
    ) -> Book? {
        // 1. 优先 ISBN + bookType（电子书/有声书）匹配
        if let isbn = item.isbn, !isbn.isEmpty {
            let isbnStr = isbn
            let isbnDescriptor = FetchDescriptor<Book>(
                predicate: #Predicate { $0.isbn == isbnStr }
            )
            if let isbnMatches = try? modelContext.fetch(isbnDescriptor),
               let match = isbnMatches.first(where: { $0.bookType == .ebook || $0.bookType == .audiobook }) {
                return match
            }
        }

        // 2. 书名 + 作者 + bookType（只匹配电子书/有声书，不匹配纸质书）
        let title = item.title
        let author = item.author
        let titleDescriptor = FetchDescriptor<Book>(
            predicate: #Predicate { $0.title == title && $0.author == author }
        )
        if let titleMatches = try? modelContext.fetch(titleDescriptor) {
            return titleMatches.first(where: { $0.bookType == .ebook || $0.bookType == .audiobook })
        }
        return nil
    }

    /// 解析出版日期字符串（微信读书格式如 "2020-01" 或 "2020-01-15" 或 "2020"）
    static func parsePublishDate(_ dateString: String) -> Date? {
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

    /// 将划线列表格式化为可读文本（static 版本，供 Task.detached 调用）
    static func formatBookmarksStatic(_ bookmarks: [WeReadBookmark]) -> String {
        var sections: [String: [String]] = [:]
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

        for (chapter, texts) in sections.sorted(by: { $0.key < $1.key }) {
            lines.append("## \(chapter)")
            for text in texts {
                lines.append("· \(text)")
            }
            lines.append("")
        }

        if !noChapter.isEmpty {
            for text in noChapter {
                lines.append("· \(text)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 将划线列表格式化为可读文本（实例方法，委托给 static 版本）
    nonisolated private func formatBookmarks(_ bookmarks: [WeReadBookmark]) -> String {
        Self.formatBookmarksStatic(bookmarks)
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
