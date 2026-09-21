import Foundation
import SwiftData
import Testing
@testable import PersonalLibrary

@Suite("WeRead AI Enrichment Tests")
struct WeReadAIEnrichmentTests {
    @Test("取消入口能终止由同步服务自身启动的核心任务")
    func cancellationStopsRegisteredCoreTaskWithoutGlobalState() async throws {
        let container = try makeContainer()
        let provider = CancellationProbeWeReadDataSource()
        let runControl = WeReadSyncService.RunControl()
        let service = WeReadSyncService(
            provider: provider,
            enrichmentCoordinator: StatusBookEnricher(status: .notAttempted),
            runControl: runControl
        )

        let syncTask = Task { await service.sync(container: container) }
        await provider.waitUntilFetchStarts()
        await service.cancelCurrentSync()
        _ = await syncTask.value

        #expect(await provider.fetchWasCancelled)
        #expect(!runControl.isSyncing)
    }

    @Test("微信平台书只生成 AI简介，用户导入书走完整补全")
    func choosesModeByBookOrigin() {
        #expect(WeReadEnrichmentPolicy.mode(
            isUserImported: false,
            needsWeReadEnrichment: false,
            aiIntroductionMissing: true
        ) == .aiIntroductionOnly)
        #expect(WeReadEnrichmentPolicy.mode(
            isUserImported: true,
            needsWeReadEnrichment: false,
            aiIntroductionMissing: true
        ) == .full)
        #expect(WeReadEnrichmentPolicy.mode(
            isUserImported: false,
            needsWeReadEnrichment: false,
            aiIntroductionMissing: false
        ) == nil)
    }

    @Test("历史微信书普通补全已完成但 AI简介为空时仍进入处理队列")
    func historicalBookStillQueuesMissingAIIntroduction() {
        #expect(WeReadEnrichmentPolicy.shouldProcess(
            hasCompletedWeReadEnrichment: true,
            hasCompletedAIEnrichment: false,
            aiIntroductionMissing: true,
            notebookChanged: false
        ))

        #expect(!WeReadEnrichmentPolicy.shouldProcess(
            hasCompletedWeReadEnrichment: true,
            hasCompletedAIEnrichment: true,
            aiIntroductionMissing: false,
            notebookChanged: false
        ))
    }

    @Test("微信同步只在相邻的微信网络请求之间限速")
    func throttlesOnlyWeReadNetworkCalls() {
        #expect(WeReadEnrichmentPolicy.shouldDelayBeforeBook(
            hasPreviousWeReadNetworkCall: true,
            needsWeReadEnrichment: true,
            needsBookmarkFetch: false
        ))
        #expect(WeReadEnrichmentPolicy.shouldDelayBeforeBook(
            hasPreviousWeReadNetworkCall: true,
            needsWeReadEnrichment: false,
            needsBookmarkFetch: true
        ))
        #expect(!WeReadEnrichmentPolicy.shouldDelayBeforeBook(
            hasPreviousWeReadNetworkCall: true,
            needsWeReadEnrichment: false,
            needsBookmarkFetch: false
        ))
        #expect(!WeReadEnrichmentPolicy.shouldDelayBeforeBook(
            hasPreviousWeReadNetworkCall: false,
            needsWeReadEnrichment: true,
            needsBookmarkFetch: true
        ))
    }

    @Test("AI 已调用但平台未返回 usage 时仍显示 Token 为未知")
    func displaysUnknownTokenUsageOnlyAfterAnAIAttempt() {
        #expect(WeReadEnrichmentPolicy.shouldDisplayTokenUsage(.unknown))
        #expect(!WeReadEnrichmentPolicy.shouldDisplayTokenUsage(.accumulator))
    }

    @Test("尚未调用 AI 的微信同步进度不显示 Token")
    func initialSyncProgressHasNoTokenSample() {
        let progress = WeReadSyncService.SyncProgress(
            current: 0,
            total: 1,
            phase: "检查登录"
        )

        #expect(!WeReadEnrichmentPolicy.shouldDisplayTokenUsage(progress.tokenUsage))
    }

    @Test("AI 致命失败不阻断当前图书的划线同步")
    func fatalAIFailureDoesNotStopBookmarkSync() async throws {
        let schema = Schema([
            Book.self,
            Bookshelf.self,
            PersonalLibrary.Tag.self,
            ReadingRecord.self,
            ImportRecord.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let book = Book(title: "需要划线的书", author: "作者", bookType: .ebook)
        book.wereadBookId = "wr_bookmark_after_ai_failure"
        book.wereadEnrichedDate = Date()
        context.insert(book)
        try context.save()

        let provider = MockWeReadDataSource()
        await provider.setBooks([
            WeReadImportItem(
                id: "wr_bookmark_after_ai_failure",
                title: book.title,
                author: book.author,
                bookType: .ebook
            )
        ])
        await provider.setNotebookCounts(["wr_bookmark_after_ai_failure": 1])
        await provider.setBookmarks([
            "wr_bookmark_after_ai_failure": [
                WeReadBookmark(
                    bookmarkId: "bookmark-1",
                    markText: "AI 失败后仍应保存的划线",
                    chapterName: "第一章",
                    createTime: nil
                )
            ]
        ])

        let service = WeReadSyncService(
            provider: provider,
            enrichmentCoordinator: FatalBookEnricher()
        )
        _ = await service.sync(container: container, skipLockCheck: true)

        #expect(await provider.bookmarkCallCount == 1)
        let verified = try #require(
            try ModelContext(container).fetch(FetchDescriptor<Book>()).first
        )
        #expect(verified.notes?.contains("AI 失败后仍应保存的划线") == true)
        #expect(verified.lastAIEnrichmentDate == nil)
    }

    @Test("AI 致命失败完成当前书划线后中止后续微信同步并报告原因")
    func fatalAIFailureStopsFollowingBooksAndReportsReason() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        for index in 1...2 {
            let book = Book(title: "待同步书 \(index)", author: "作者", bookType: .ebook)
            book.wereadBookId = "wr_fatal_\(index)"
            book.wereadEnrichedDate = Date()
            context.insert(book)
        }
        try context.save()

        let provider = MockWeReadDataSource()
        await provider.setBooks((1...2).map {
            WeReadImportItem(id: "wr_fatal_\($0)", title: "待同步书 \($0)", author: "作者")
        })
        await provider.setNotebookCounts(["wr_fatal_1": 1, "wr_fatal_2": 1])
        await provider.setBookmarks([
            "wr_fatal_1": [WeReadBookmark(bookmarkId: "bookmark-1", markText: "划线 1", chapterName: "第一章", createTime: nil)],
            "wr_fatal_2": [WeReadBookmark(bookmarkId: "bookmark-2", markText: "划线 2", chapterName: "第二章", createTime: nil)]
        ])

        let result = await WeReadSyncService(
            provider: provider,
            enrichmentCoordinator: FatalBookEnricher()
        ).sync(container: container, skipLockCheck: true)

        #expect(await provider.bookmarkCallCount == 1)
        #expect(result.error?.contains("认证失败") == true)
    }

    @Test("平台书自动生成 AI简介并累计 Token 到结果和进度")
    func platformBookGeneratesIntroductionAndReportsTokens() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let book = Book(title: "平台书", author: "作者", bookType: .ebook)
        book.wereadBookId = "wr_platform"
        book.wereadEnrichedDate = Date()
        context.insert(book)
        try context.save()

        let provider = MockWeReadDataSource()
        await provider.setBooks([
            WeReadImportItem(id: "wr_platform", title: book.title, author: book.author)
        ])
        await provider.setNotebookCounts(["wr_platform": 0])
        let enricher = SuccessfulBookEnricher()
        let progress = LockedProgressRecorder()

        let result = await WeReadSyncService(
            provider: provider,
            enrichmentCoordinator: enricher
        ).sync(container: container, skipLockCheck: true) { progress.record($0) }

        let verified = try #require(
            try ModelContext(container).fetch(FetchDescriptor<Book>()).first
        )
        #expect(await enricher.modes == [.aiIntroductionOnly])
        #expect(verified.bookIntroduction == "自动生成的 AI简介")
        #expect(verified.lastAIEnrichmentDate != nil)
        #expect(result.tokenUsage == AITokenUsage(input: 7, output: 5, total: 12))
        #expect(progress.values.contains { $0.tokenUsage.total == 12 })
    }

    @Test("AI 未尝试不会覆盖微信同步中已记录的 Token")
    func notAttemptedAIDoesNotEraseRecordedTokens() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        for title in ["有 Token", "AI 未尝试"] {
            let book = Book(title: title, author: "作者", bookType: .ebook)
            book.wereadBookId = "wr_\(title)"
            book.wereadEnrichedDate = Date()
            context.insert(book)
        }
        try context.save()

        let provider = MockWeReadDataSource()
        await provider.setBooks(["有 Token", "AI 未尝试"].map {
            WeReadImportItem(id: "wr_\($0)", title: $0, author: "作者")
        })
        await provider.setNotebookCounts(["wr_有 Token": 0, "wr_AI 未尝试": 0])

        let result = await WeReadSyncService(
            provider: provider,
            enrichmentCoordinator: MixedTokenBookEnricher()
        ).sync(container: container, skipLockCheck: true)

        #expect(result.tokenUsage == AITokenUsage(input: 7, output: 5, total: 12))
    }

    @Test("用户导入书走完整补全且不覆盖已有字段")
    func userImportedBookUsesFullModeWithoutOverwrite() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let book = Book(
            title: "用户导入书",
            author: "作者",
            publisher: "用户出版社",
            bookType: .ebook
        )
        book.wereadBookId = "CB_imported"
        book.isWereadUserImported = true
        context.insert(book)
        try context.save()

        let provider = MockWeReadDataSource()
        await provider.setBooks([
            WeReadImportItem(
                id: "CB_imported",
                title: book.title,
                author: book.author,
                isUserImported: true
            )
        ])
        let enricher = SuccessfulBookEnricher()

        _ = await WeReadSyncService(
            provider: provider,
            enrichmentCoordinator: enricher
        ).sync(container: container, skipLockCheck: true)

        let verified = try #require(
            try ModelContext(container).fetch(FetchDescriptor<Book>()).first
        )
        #expect(await enricher.modes == [.full])
        #expect(verified.publisher == "用户出版社")
        #expect(verified.bookIntroduction == "自动生成的 AI简介")
    }

    @Test("已有 AI简介的微信书不再调用统一补全")
    func existingIntroductionSkipsEnrichment() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let book = Book(title: "已有简介", author: "作者", bookType: .ebook)
        book.wereadBookId = "wr_existing_intro"
        book.wereadEnrichedDate = Date()
        book.bookIntroduction = "用户已有 AI简介"
        context.insert(book)
        try context.save()

        let provider = MockWeReadDataSource()
        await provider.setBooks([
            WeReadImportItem(id: "wr_existing_intro", title: book.title, author: book.author)
        ])
        await provider.setNotebookCounts(["wr_existing_intro": 0])
        let enricher = SuccessfulBookEnricher()

        _ = await WeReadSyncService(
            provider: provider,
            enrichmentCoordinator: enricher
        ).sync(container: container, skipLockCheck: true)

        #expect(await enricher.modes.isEmpty)
        let verified = try #require(
            try ModelContext(container).fetch(FetchDescriptor<Book>()).first
        )
        #expect(verified.bookIntroduction == "用户已有 AI简介")
    }

    @Test("归档的微信书不会在自动同步中发送给 AI")
    func archivedBookSkipsAIEnrichment() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let book = Book(title: "已归档书", author: "作者", bookType: .ebook)
        book.wereadBookId = "wr_archived"
        book.wereadEnrichedDate = Date()
        book.isArchived = true
        context.insert(book)
        try context.save()

        let provider = MockWeReadDataSource()
        await provider.setBooks([])
        await provider.setNotebookCounts(["wr_archived": 1])
        let enricher = SuccessfulBookEnricher()

        _ = await WeReadSyncService(
            provider: provider,
            enrichmentCoordinator: enricher
        ).sync(container: container, skipLockCheck: true)

        #expect(await enricher.modes.isEmpty)
        #expect(await provider.bookmarkCallCount == 0)
    }

    @Test("拉取书架期间归档的已有书不再接受远端更新")
    func archiveDuringShelfFetchRejectsRemoteUpdates() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let book = Book(title: "书架等待归档", author: "作者", bookType: .ebook)
        book.wereadBookId = "wr_archive_during_shelf"
        book.wereadProgress = 10
        book.wereadEnrichedDate = Date()
        book.lastAIEnrichmentDate = Date()
        book.bookIntroduction = "已有 AI简介"
        context.insert(book)
        try context.save()

        let provider = PausingShelfWeReadDataSource(item: WeReadImportItem(
            id: "wr_archive_during_shelf",
            title: book.title,
            author: book.author,
            progress: 80,
            bookType: .ebook
        ))
        let service = WeReadSyncService(
            provider: provider,
            enrichmentCoordinator: StatusBookEnricher(status: .notAttempted)
        )

        let syncTask = Task {
            await service.sync(container: container, skipLockCheck: true)
        }
        await provider.waitUntilStarted()

        let archiveContext = ModelContext(container)
        let archived = try #require(
            archiveContext.model(for: book.persistentModelID) as? Book
        )
        archived.isArchived = true
        try archiveContext.save()
        await provider.resume()
        _ = await syncTask.value

        let verified = try #require(
            ModelContext(container).model(for: book.persistentModelID) as? Book
        )
        #expect(verified.isArchived)
        #expect(verified.wereadProgress == 10)
    }

    @Test("拉取书架期间删除的已有书不会被重新导入")
    func deletionDuringShelfFetchDoesNotReimportBook() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let book = Book(title: "书架等待删除", author: "作者", bookType: .ebook)
        book.wereadBookId = "wr_delete_during_shelf"
        context.insert(book)
        try context.save()

        let provider = PausingShelfWeReadDataSource(item: WeReadImportItem(
            id: "wr_delete_during_shelf",
            title: book.title,
            author: book.author,
            bookType: .ebook
        ))
        let service = WeReadSyncService(
            provider: provider,
            enrichmentCoordinator: StatusBookEnricher(status: .notAttempted)
        )

        let syncTask = Task {
            await service.sync(container: container, skipLockCheck: true)
        }
        await provider.waitUntilStarted()

        let deleteContext = ModelContext(container)
        let deleted = try #require(
            deleteContext.model(for: book.persistentModelID) as? Book
        )
        deleteContext.delete(deleted)
        try deleteContext.save()
        await provider.resume()

        let result = await syncTask.value
        let remaining = try ModelContext(container).fetch(FetchDescriptor<Book>())
        #expect(remaining.allSatisfy { $0.wereadBookId != "wr_delete_during_shelf" })
        #expect(result.newBooksImported == 0)
    }

    @Test("进入处理队列后被归档的微信书不再发送给 AI 或划线接口")
    func bookArchivedDuringSyncSkipsSubsequentExternalCalls() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let book = Book(title: "同步中归档", author: "作者", bookType: .ebook)
        book.wereadBookId = "wr_archived_during_sync"
        book.wereadEnrichedDate = nil
        book.wereadBookmarkCount = 0
        context.insert(book)
        try context.save()

        let provider = MockWeReadDataSource()
        await provider.setBooks([
            WeReadImportItem(id: "wr_archived_during_sync", title: book.title, author: book.author)
        ])
        var returnedMetadata = WeReadEnrichResult()
        returnedMetadata.publisher = "不应写入的出版社"
        await provider.setEnrichResults(["wr_archived_during_sync": returnedMetadata])
        await provider.setNotebookCounts(["wr_archived_during_sync": 1])
        await provider.setEnrichHook { bookID in
            let archiveContext = ModelContext(container)
            let archived = try? archiveContext.fetch(FetchDescriptor<Book>(
                predicate: #Predicate { $0.wereadBookId == bookID }
            )).first
            archived?.isArchived = true
            try? archiveContext.save()
        }
        let enricher = SuccessfulBookEnricher()

        _ = await WeReadSyncService(
            provider: provider,
            enrichmentCoordinator: enricher
        ).sync(container: container, skipLockCheck: true)

        #expect(await enricher.modes.isEmpty)
        #expect(await provider.bookmarkCallCount == 0)
        let verified = try #require(
            ModelContext(container).model(for: book.persistentModelID) as? Book
        )
        #expect(verified.isArchived)
        #expect(verified.publisher == nil)
        #expect(verified.wereadEnrichedDate == nil)
    }

    @Test("划线请求期间归档的微信书不写回在途结果")
    func archiveDuringBookmarkFetchRejectsCommit() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let book = Book(title: "划线等待归档", author: "作者", bookType: .ebook)
        book.wereadBookId = "wr_archive_during_bookmarks"
        book.wereadEnrichedDate = Date()
        book.lastAIEnrichmentDate = Date()
        book.bookIntroduction = "已有 AI简介"
        context.insert(book)
        try context.save()
        let persistentID = book.persistentModelID

        let provider = ArchiveDuringBookmarkWeReadDataSource(
            bookID: "wr_archive_during_bookmarks"
        ) {
            let archiveContext = ModelContext(container)
            guard let archived = archiveContext.model(for: persistentID) as? Book else { return }
            archived.isArchived = true
            try? archiveContext.save()
        }

        _ = await WeReadSyncService(
            provider: provider,
            enrichmentCoordinator: StatusBookEnricher(status: .notAttempted)
        ).sync(container: container, skipLockCheck: true)

        let verified = try #require(
            ModelContext(container).model(for: persistentID) as? Book
        )
        #expect(verified.isArchived)
        #expect(verified.notes == nil)
        #expect(verified.wereadBookmarkCount == 0)
    }

    @Test("AI 验证拒绝是终态并写入同步时间戳")
    func validationRejectionRecordsCompletion() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let book = Book(title: "证据不足", author: "作者", bookType: .ebook)
        book.wereadBookId = "wr_rejected"
        book.wereadEnrichedDate = Date()
        context.insert(book)
        try context.save()

        let provider = MockWeReadDataSource()
        await provider.setBooks([
            WeReadImportItem(id: "wr_rejected", title: book.title, author: book.author)
        ])
        await provider.setNotebookCounts(["wr_rejected": 0])

        _ = await WeReadSyncService(
            provider: provider,
            enrichmentCoordinator: StatusBookEnricher(status: .validationRejected("来源不足"))
        ).sync(container: container, skipLockCheck: true)

        let verified = try #require(
            try ModelContext(container).fetch(FetchDescriptor<Book>()).first
        )
        #expect(verified.lastAIEnrichmentDate != nil)
    }

    @Test("微信 AI 等待期间的手工编辑不会被返回结果覆盖")
    func manualEditDuringAIWaitWinsWhileOtherFieldsCommit() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let book = Book(title: "等待 AI", author: "作者", bookType: .ebook)
        book.wereadBookId = "CB_concurrent_edit"
        book.isWereadUserImported = true
        book.wereadEnrichedDate = Date()
        context.insert(book)
        try context.save()

        let provider = MockWeReadDataSource()
        await provider.setBooks([
            WeReadImportItem(
                id: "CB_concurrent_edit",
                title: book.title,
                author: book.author,
                isUserImported: true
            )
        ])
        await provider.setNotebookCounts(["CB_concurrent_edit": 0])
        let enricher = PausingBookEnricher()
        let service = WeReadSyncService(provider: provider, enrichmentCoordinator: enricher)

        let syncTask = Task {
            await service.sync(container: container, skipLockCheck: true)
        }
        await enricher.waitUntilStarted()

        let editingContext = ModelContext(container)
        let edited = try #require(
            editingContext.model(for: book.persistentModelID) as? Book
        )
        edited.publisher = "用户出版社"
        try editingContext.save()
        await enricher.resume()
        _ = await syncTask.value

        let verified = try #require(
            ModelContext(container).model(for: book.persistentModelID) as? Book
        )
        #expect(verified.publisher == "用户出版社")
        #expect(verified.bookIntroduction == "AI 返回的简介")
    }

    @Test("微信 AI 等待期间归档后不再提交返回结果")
    func archiveDuringAIWaitRejectsCommit() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let book = Book(title: "等待归档", author: "作者", bookType: .ebook)
        book.wereadBookId = "wr_archive_during_ai"
        book.wereadEnrichedDate = Date()
        context.insert(book)
        try context.save()

        let provider = MockWeReadDataSource()
        await provider.setBooks([
            WeReadImportItem(id: "wr_archive_during_ai", title: book.title, author: book.author)
        ])
        await provider.setNotebookCounts(["wr_archive_during_ai": 1])
        let enricher = PausingBookEnricher()
        let service = WeReadSyncService(provider: provider, enrichmentCoordinator: enricher)

        let syncTask = Task {
            await service.sync(container: container, skipLockCheck: true)
        }
        await enricher.waitUntilStarted()

        let archiveContext = ModelContext(container)
        let archived = try #require(
            archiveContext.model(for: book.persistentModelID) as? Book
        )
        archived.isArchived = true
        try archiveContext.save()
        await enricher.resume()
        _ = await syncTask.value

        let verified = try #require(
            ModelContext(container).model(for: book.persistentModelID) as? Book
        )
        #expect(verified.isArchived)
        #expect(verified.bookIntroduction == nil)
        #expect(verified.lastAIEnrichmentDate == nil)
        #expect(await provider.bookmarkCallCount == 0)
    }

    @Test("AI 致命失败期间归档当前书仍会中止后续书")
    func archiveDuringFatalAIStillStopsFollowingBooks() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        for index in 1...2 {
            let book = Book(title: "致命失败书 \(index)", author: "作者", bookType: .ebook)
            book.wereadBookId = "wr_archive_fatal_\(index)"
            book.wereadEnrichedDate = Date()
            context.insert(book)
        }
        try context.save()

        let provider = MockWeReadDataSource()
        await provider.setBooks((1...2).map {
            WeReadImportItem(
                id: "wr_archive_fatal_\($0)",
                title: "致命失败书 \($0)",
                author: "作者"
            )
        })
        await provider.setNotebookCounts([
            "wr_archive_fatal_1": 0,
            "wr_archive_fatal_2": 0
        ])
        let enricher = PausingFatalBookEnricher()
        let service = WeReadSyncService(provider: provider, enrichmentCoordinator: enricher)

        let syncTask = Task {
            await service.sync(container: container, skipLockCheck: true)
        }
        let startedTitle = await enricher.waitUntilStarted()

        let archiveContext = ModelContext(container)
        let archived = try #require(
            try archiveContext.fetch(FetchDescriptor<Book>(
                predicate: #Predicate { $0.title == startedTitle }
            )).first
        )
        archived.isArchived = true
        try archiveContext.save()
        await enricher.resume()

        let result = await syncTask.value
        #expect(await enricher.callCount == 1)
        #expect(result.error?.contains("认证失败") == true)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Book.self,
            Bookshelf.self,
            PersonalLibrary.Tag.self,
            ReadingRecord.self,
            ImportRecord.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}

private actor CancellationProbeWeReadDataSource: WeReadDataSource {
    private var fetchStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var fetchWasCancelled = false

    func waitUntilFetchStarts() async {
        guard !fetchStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func isConnected() -> Bool { true }
    func disconnect() {}

    func fetchAllBooks() async throws -> [WeReadImportItem] {
        fetchStarted = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        do {
            try await Task.sleep(for: .seconds(1))
            return []
        } catch {
            fetchWasCancelled = true
            throw error
        }
    }

    func enrichBook(bookId: String) async throws -> WeReadEnrichResult {
        WeReadEnrichResult()
    }

    func fetchBookmarks(bookId: String) async throws -> [WeReadBookmark] { [] }

    func fetchBookInfo(bookId: String) async throws -> WeReadShelfBook {
        WeReadShelfBook(
            bookId: bookId,
            title: nil,
            author: nil,
            cover: nil,
            translator: nil,
            category: nil,
            publisher: nil,
            publishTime: nil,
            intro: nil,
            isbn: nil,
            price: nil,
            finished: nil,
            format: nil,
            type: nil,
            readUpdateTime: nil,
            finishReadingTime: nil
        )
    }
}

private actor ArchiveDuringBookmarkWeReadDataSource: WeReadDataSource {
    private let bookID: String
    private let archive: @Sendable () async -> Void

    init(bookID: String, archive: @escaping @Sendable () async -> Void) {
        self.bookID = bookID
        self.archive = archive
    }

    func isConnected() -> Bool { true }
    func disconnect() {}

    func fetchAllBooks() async throws -> [WeReadImportItem] {
        [WeReadImportItem(id: bookID, title: "划线等待归档", author: "作者")]
    }

    func fetchNotebookCounts() async throws -> [String: Int]? { [bookID: 1] }

    func enrichBook(bookId: String) async throws -> WeReadEnrichResult {
        WeReadEnrichResult()
    }

    func fetchBookmarks(bookId: String) async throws -> [WeReadBookmark] {
        await archive()
        return [
            WeReadBookmark(
                bookmarkId: "bookmark-after-archive",
                markText: "不应写入的划线",
                chapterName: "第一章",
                createTime: nil
            )
        ]
    }

    func fetchBookInfo(bookId: String) async throws -> WeReadShelfBook {
        WeReadShelfBook(
            bookId: bookId,
            title: nil,
            author: nil,
            cover: nil,
            translator: nil,
            category: nil,
            publisher: nil,
            publishTime: nil,
            intro: nil,
            isbn: nil,
            price: nil,
            finished: nil,
            format: nil,
            type: nil,
            readUpdateTime: nil,
            finishReadingTime: nil
        )
    }
}

private actor PausingShelfWeReadDataSource: WeReadDataSource {
    private let item: WeReadImportItem
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    init(item: WeReadImportItem) {
        self.item = item
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }

    func isConnected() -> Bool { true }
    func disconnect() {}

    func fetchAllBooks() async throws -> [WeReadImportItem] {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { resumeContinuation = $0 }
        return [item]
    }

    func fetchNotebookCounts() async throws -> [String: Int]? { [:] }
    func enrichBook(bookId: String) async throws -> WeReadEnrichResult { WeReadEnrichResult() }
    func fetchBookmarks(bookId: String) async throws -> [WeReadBookmark] { [] }
    func fetchBookInfo(bookId: String) async throws -> WeReadShelfBook {
        WeReadShelfBook(
            bookId: bookId,
            title: nil,
            author: nil,
            cover: nil,
            translator: nil,
            category: nil,
            publisher: nil,
            publishTime: nil,
            intro: nil,
            isbn: nil,
            price: nil,
            finished: nil,
            format: nil,
            type: nil,
            readUpdateTime: nil,
            finishReadingTime: nil
        )
    }
}

private struct FatalBookEnricher: BookEnriching {
    func enrich(
        _ draft: BookDraft,
        mode: EnrichmentMode,
        localAuthorDescription: String?
    ) async -> EnrichmentOutcome {
        EnrichmentOutcome(
            originalDraft: draft,
            draft: draft,
            aiStatus: .fatalFailure("认证失败")
        )
    }
}

private actor SuccessfulBookEnricher: BookEnriching {
    private(set) var modes: [EnrichmentMode] = []

    func enrich(
        _ draft: BookDraft,
        mode: EnrichmentMode,
        localAuthorDescription: String?
    ) async -> EnrichmentOutcome {
        modes.append(mode)
        let candidate = BookDraft(
            title: "",
            author: "",
            publisher: "AI 出版社",
            aiIntroduction: "自动生成的 AI简介"
        )
        return EnrichmentOutcome(
            originalDraft: draft,
            draft: draft.fillingMissingFields(from: candidate, limitedTo: draft.missingFields),
            aiStatus: .found,
            tokenUsage: AITokenUsage(input: 7, output: 5, total: 12)
        )
    }
}

private actor PausingBookEnricher: BookEnriching {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }

    func enrich(
        _ draft: BookDraft,
        mode: EnrichmentMode,
        localAuthorDescription: String?
    ) async -> EnrichmentOutcome {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { resumeContinuation = $0 }

        var enriched = draft
        enriched.publisher = "AI 出版社"
        enriched.aiIntroduction = "AI 返回的简介"
        return EnrichmentOutcome(
            originalDraft: draft,
            draft: enriched,
            aiStatus: .found
        )
    }
}

private actor PausingFatalBookEnricher: BookEnriching {
    private var startedTitle: String?
    private var startWaiters: [CheckedContinuation<String, Never>] = []
    private var resumeContinuation: CheckedContinuation<Void, Never>?
    private(set) var callCount = 0

    func waitUntilStarted() async -> String {
        if let startedTitle { return startedTitle }
        return await withCheckedContinuation { startWaiters.append($0) }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }

    func enrich(
        _ draft: BookDraft,
        mode: EnrichmentMode,
        localAuthorDescription: String?
    ) async -> EnrichmentOutcome {
        callCount += 1
        if callCount == 1 {
            startedTitle = draft.title
            startWaiters.forEach { $0.resume(returning: draft.title) }
            startWaiters.removeAll()
            await withCheckedContinuation { resumeContinuation = $0 }
        }
        return EnrichmentOutcome(
            originalDraft: draft,
            draft: draft,
            aiStatus: .fatalFailure("认证失败")
        )
    }
}

private struct StatusBookEnricher: BookEnriching {
    let status: LookupSourceStatus

    func enrich(
        _ draft: BookDraft,
        mode: EnrichmentMode,
        localAuthorDescription: String?
    ) async -> EnrichmentOutcome {
        EnrichmentOutcome(originalDraft: draft, draft: draft, aiStatus: status)
    }
}

private struct MixedTokenBookEnricher: BookEnriching {
    func enrich(
        _ draft: BookDraft,
        mode: EnrichmentMode,
        localAuthorDescription: String?
    ) async -> EnrichmentOutcome {
        if draft.title == "有 Token" {
            return EnrichmentOutcome(
                originalDraft: draft,
                draft: draft,
                aiStatus: .found,
                tokenUsage: AITokenUsage(input: 7, output: 5, total: 12)
            )
        }
        return EnrichmentOutcome(
            originalDraft: draft,
            draft: draft,
            aiStatus: .notAttempted,
            tokenUsage: .unknown
        )
    }
}

private final class LockedProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [WeReadSyncService.SyncProgress] = []

    var values: [WeReadSyncService.SyncProgress] {
        lock.withLock { storage }
    }

    func record(_ progress: WeReadSyncService.SyncProgress) {
        lock.withLock { storage.append(progress) }
    }
}
