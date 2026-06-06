import SwiftUI
import SwiftData

@main
struct PersonalLibraryApp: App {
    @Environment(\.scenePhase) private var scenePhase
    let modelContainer: ModelContainer
    /// 启动时主容器创建失败的错误（非 nil 表示已进入内存安全模式）
    private let startupError: Error?

    init() {
        // 失败不再 fatalError 闪退：降级为内存安全模式让 app 能起来，由 UI 提示用户
        let result = StorageManager.makeContainerOrFallback()
        modelContainer = result.container
        startupError = result.startupError
        // 仅在主容器正常时做封面迁移（安全模式下数据是临时内存，迁移无意义）
        if startupError == nil {
            StorageManager.shared.migrateOversizedCoversIfNeeded(modelContainer)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(startupError: startupError)
                .task { if startupError == nil { migrateOldAddSource(); migrateWeReadBookshelf() } }
                .task { if startupError == nil { await backgroundCoverRefresh() } }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                triggerAutoSyncIfNeeded()
            }
        }
    }

    /// 迁移旧数据：将 addSource="导入" 更新为 "文件导入"
    @MainActor
    private func migrateOldAddSource() {
        let migrationKey = "addSource_migration_v1_done"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let context = modelContainer.mainContext
        do {
            let allBooks = try context.fetch(FetchDescriptor<Book>())
            var migrated = 0
            for book in allBooks {
                // 强制触发 SwiftData 脏标记：先设为其他值再设回来
                // 确保旧的 rawValue "导入" 被写为新的 "文件导入"
                if book.addSource == .imported {
                    book.addSource = .manual
                    book.addSource = .imported
                    migrated += 1
                }
            }
            if migrated > 0 {
                try context.save()
                AppLogger.info("已将 \(migrated) 本书的 addSource 从 '导入' 迁移为 '文件导入'", category: "Migration")
            }
        } catch {
            AppLogger.error("addSource 迁移失败: \(error)", category: "Migration")
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    /// 迁移：给有 wereadBookId 但缺 bookshelf 的书补上"微信读书"书架和标签
    @MainActor
    private func migrateWeReadBookshelf() {
        let migrationKey = "weread_bookshelf_migration_v1_done"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let context = modelContainer.mainContext
        do {
            let allBooks = try context.fetch(FetchDescriptor<Book>())
            let wereadBooks = allBooks.filter { $0.wereadBookId != nil && $0.bookshelf == nil }
            guard !wereadBooks.isEmpty else {
                UserDefaults.standard.set(true, forKey: migrationKey)
                return
            }

            // 查找或创建"微信读书"书架和标签
            let shelfName = "微信读书"
            var shelfDescriptor = FetchDescriptor<Bookshelf>(
                predicate: #Predicate { $0.name == shelfName }
            )
            shelfDescriptor.fetchLimit = 1
            let shelf = try context.fetch(shelfDescriptor).first ?? {
                let s = Bookshelf(name: "微信读书", icon: "iphone")
                context.insert(s)
                return s
            }()

            let tagName = "微信读书"
            var tagDescriptor = FetchDescriptor<Tag>(
                predicate: #Predicate { $0.name == tagName }
            )
            tagDescriptor.fetchLimit = 1
            let tag = try context.fetch(tagDescriptor).first ?? {
                let t = Tag(name: "微信读书")
                context.insert(t)
                return t
            }()

            for book in wereadBooks {
                book.bookshelf = shelf
                if book.tags?.contains(where: { $0.name == "微信读书" }) != true {
                    var tags = book.tags ?? []
                    tags.append(tag)
                    book.tags = tags
                }
            }
            try context.save()
            AppLogger.info("已为 \(wereadBooks.count) 本微信读书书籍补上书架和标签", category: "Migration")
        } catch {
            AppLogger.error("微信读书书架迁移失败: \(error)", category: "Migration")
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    /// App 回到前台时检查是否需要自动同步微信读书
    @MainActor
    private func triggerAutoSyncIfNeeded() {
        guard WeReadSyncService.shouldAutoSync() else { return }

        let context = modelContainer.mainContext
        let provider: any WeReadDataSource = WeReadConnectionMode.current == .skill
            ? WeReadSkillProvider()
            : WeReadService()
        let syncService = WeReadSyncService(provider: provider)

        Task {
            let result = await syncService.sync(modelContext: context, triggeredBy: SyncHistoryRecord.Trigger.system)
            if result.hasChanges {
                AppLogger.info("自动同步完成: \(result.summary)", category: "WeReadSync")
            }
        }
    }

    /// 后台静默补全缺失封面
    /// 启动后延迟 5s 开始，低优先级逐本下载，每本间隔 2s，不阻塞 UI
    @MainActor
    private func backgroundCoverRefresh() async {
        // 延迟 5 秒，等 UI 加载完毕
        try? await Task.sleep(for: .seconds(5))

        let context = modelContainer.mainContext
        let allBooks: [Book]
        do {
            allBooks = try context.fetch(FetchDescriptor<Book>())
        } catch {
            return
        }

        // 在主线程收集需要补全的书的 ID 和元数据（只读标量，不触发 externalStorage）
        struct CoverTask: Sendable {
            let id: PersistentIdentifier
            let coverURL: String?
            let isbn: String?
            let doubanURL: String?
            let title: String
            let author: String
        }

        let tasks = allBooks.compactMap { book -> CoverTask? in
            guard !book.hasCoverData && !book.isArchived &&
                  (book.coverImageURL != nil || book.isbn != nil || book.doubanURL != nil) else {
                return nil
            }
            return CoverTask(id: book.persistentModelID, coverURL: book.coverImageURL,
                             isbn: book.isbn, doubanURL: book.doubanURL,
                             title: book.title, author: book.author)
        }

        guard !tasks.isEmpty else { return }
        AppLogger.info("开始补全 \(tasks.count) 本书的封面", category: "BackgroundCover")

        let container = modelContainer

        // 全部在后台线程执行：网络下载 + externalStorage 写入 + save
        await Task.detached(priority: .utility) {
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false
            var fetched = 0

            for task in tasks {
                // 批量补全进行中时退出，让出 CPU 和网络（下次启动会自动补全）
                if await BatchEnrichmentState.shared.current() {
                    AppLogger.info("批量补全进行中，BackgroundCover 退出", category: "BackgroundCover")
                    break
                }
                try? await Task.sleep(for: .seconds(2))

                let data = await CoverFetchService.shared.fetchCoverThrottled(
                    coverImageURL: task.coverURL,
                    isbn: task.isbn,
                    doubanURL: task.doubanURL,
                    title: task.title,
                    author: task.author
                )

                if let data, data.count > 100 {
                    if let book = bgContext.model(for: task.id) as? Book {
                        book.coverImageData = data
                        fetched += 1
                        // 每 20 本保存一次（降低 @Query 刷新频率）
                        if fetched % 20 == 0 {
                            try? bgContext.save()
                        }
                    }
                }
            }

            if fetched > 0 {
                try? bgContext.save()
                AppLogger.info("后台补全完成：\(fetched)/\(tasks.count) 本", category: "BackgroundCover")
            }
        }.value
    }
}
