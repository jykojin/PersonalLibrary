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

    /// 执行增量同步
    func sync(modelContext: ModelContext) async -> SyncResult {
        var result = SyncResult()

        // 1. 检查登录状态
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

        // 5. 获取或创建"微信读书"标签
        let wereadTag: Tag
        do {
            wereadTag = try await MainActor.run {
                try findOrCreateTag(name: "微信读书", modelContext: modelContext)
            }
        } catch {
            result.error = "创建标签失败"
            return result
        }

        // 6. 逐本处理（每 20 本保存一次，避免内存压力和全量丢失）
        var processedSinceLastSave = 0
        for item in remoteBooks {
            if let existingBook = localBookMap[item.id] {
                // 已存在 → 更新进度和状态
                let updated = await updateExistingBook(book: existingBook, item: item)
                if updated.progressChanged { result.progressUpdated += 1 }
                if updated.statusChanged { result.statusUpdated += 1 }
            } else {
                // 不存在 → 通过书名+作者匹配（兼容首次导入时没有 wereadBookId 的老数据）
                let matchedByTitle = await findBookByTitleAuthor(
                    title: item.title,
                    author: item.author,
                    modelContext: modelContext
                )
                if let existingBook = matchedByTitle {
                    // 补充 wereadBookId 并更新
                    await MainActor.run { existingBook.wereadBookId = item.id }
                    let updated = await updateExistingBook(book: existingBook, item: item)
                    if updated.progressChanged { result.progressUpdated += 1 }
                    if updated.statusChanged { result.statusUpdated += 1 }
                } else {
                    // 全新书 → 导入
                    await importNewBook(item: item, tag: wereadTag, modelContext: modelContext)
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

        // 8. 记录同步时间
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

            // 状态更新逻辑：
            // - 微信读书标记"已读完" → 本地也标记已读（除非用户已手动设为弃读）
            // - 微信读书有进度但本地还是"闲置/想读" → 更新为"正在读"
            if item.isFinished && book.status != .finished && book.status != .dropped {
                book.status = .finished
                book.statusChangedDate = Date()
                if book.finishedDate == nil {
                    book.finishedDate = Date()
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
        modelContext: ModelContext
    ) async {
        // 下载封面
        var coverData: Data?
        if let coverURL = item.cover {
            coverData = await downloadImage(from: coverURL)
        }

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
            book.coverImageData = coverData
            book.addSource = .imported

            // 阅读状态
            if item.isFinished {
                book.status = .finished
                book.finishedDate = Date()
            } else if item.progress > 0 || item.readingTime > 0 || item.ttsTime > 0 {
                book.status = .reading
            } else {
                book.status = .wishlist
            }
            book.statusChangedDate = Date()

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

    private func findBookByTitleAuthor(
        title: String,
        author: String,
        modelContext: ModelContext
    ) async -> Book? {
        return try? await MainActor.run {
            var descriptor = FetchDescriptor<Book>(
                predicate: #Predicate { $0.title == title && $0.author == author }
            )
            descriptor.fetchLimit = 1
            return try modelContext.fetch(descriptor).first
        }
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
}
