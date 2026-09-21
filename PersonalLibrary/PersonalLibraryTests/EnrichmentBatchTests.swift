import Foundation
import SwiftData
import Testing
@testable import PersonalLibrary

@Suite("Enrichment Batch Tests")
struct EnrichmentBatchTests {
    @Test("批量补全提交时保留并发手工编辑并写入无冲突字段")
    func batchCommitRebasesOnLatestBookValues() throws {
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
        let book = Book(title: "并发编辑", author: "作者", bookType: .paper)
        context.insert(book)
        try context.save()

        let snapshot = try #require(EnrichmentBookPersistence.eligibleBatchSnapshot(
            for: book.persistentModelID,
            mode: .full,
            in: container
        ))
        var enriched = snapshot.draft
        enriched.publisher = "AI 出版社"
        enriched.authorDescription = "AI 作者简介"
        let outcome = EnrichmentOutcome(originalDraft: snapshot.draft, draft: enriched)

        let editingContext = ModelContext(container)
        let edited = try #require(
            editingContext.model(for: book.persistentModelID) as? Book
        )
        edited.publisher = "用户出版社"
        try editingContext.save()

        let committed = try #require(try EnrichmentBookPersistence.commitBatch(
            outcome,
            to: book.persistentModelID,
            mode: .full,
            in: container
        ))

        #expect(committed.draft.publisher == "用户出版社")
        #expect(committed.draft.authorDescription == "AI 作者简介")
        let verified = try #require(
            ModelContext(container).model(for: book.persistentModelID) as? Book
        )
        #expect(verified.publisher == "用户出版社")
        #expect(verified.authorDescription == "AI 作者简介")
    }

    @Test("批量补全在外发和提交前都重新检查归档状态")
    func archivedBookIsRejectedAtBothPersistenceBoundaries() throws {
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
        let book = Book(title: "等待批量补全", author: "作者", bookType: .paper)
        context.insert(book)
        try context.save()

        let snapshot = try #require(EnrichmentBookPersistence.eligibleBatchSnapshot(
            for: book.persistentModelID,
            mode: .full,
            in: container
        ))
        var enriched = snapshot.draft
        enriched.publisher = "外部出版社"
        let outcome = EnrichmentOutcome(originalDraft: snapshot.draft, draft: enriched)

        let archiveContext = ModelContext(container)
        let archived = try #require(
            archiveContext.model(for: book.persistentModelID) as? Book
        )
        archived.isArchived = true
        try archiveContext.save()

        #expect(EnrichmentBookPersistence.eligibleBatchSnapshot(
            for: book.persistentModelID,
            mode: .full,
            in: container
        ) == nil)
        #expect(try EnrichmentBookPersistence.commitBatch(
            outcome,
            to: book.persistentModelID,
            mode: .full,
            in: container
        ) == nil)

        let verified = try #require(
            ModelContext(container).model(for: book.persistentModelID) as? Book
        )
        #expect(verified.publisher == nil)
    }

    @Test("批量补全遇到已删除图书时安全拒绝读取和提交")
    func deletedBookIsRejectedAtBothPersistenceBoundaries() throws {
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
        let book = Book(title: "等待删除", author: "作者", bookType: .paper)
        context.insert(book)
        try context.save()
        let id = book.persistentModelID
        let original = BookDraft(book: book)
        var enriched = original
        enriched.publisher = "不应写入"
        let outcome = EnrichmentOutcome(originalDraft: original, draft: enriched)

        context.delete(book)
        try context.save()

        #expect(EnrichmentBookPersistence.activeSnapshot(for: id, in: container) == nil)
        #expect(try EnrichmentBookPersistence.commitBatch(
            outcome,
            to: id,
            mode: .full,
            in: container
        ) == nil)
    }

    @Test("普通批量仅选纸质书，AI 批量覆盖所有载体")
    func candidateScopesDifferByMode() {
        let paper = Book(title: "纸书", author: "作者", bookType: .paper)
        let ebook = Book(title: "电子书", author: "作者", bookType: .ebook)

        #expect(EnrichmentBatchPolicy.isCandidate(paper, mode: .full))
        #expect(!EnrichmentBatchPolicy.isCandidate(ebook, mode: .full))
        #expect(EnrichmentBatchPolicy.isCandidate(ebook, mode: .aiOnly))

        ebook.isArchived = true
        #expect(!EnrichmentBatchPolicy.isCandidate(ebook, mode: .aiOnly))
    }

    @Test("普通批量保留两秒节奏，AI 批量不额外等待")
    func choosesInterBookDelayByMode() {
        #expect(EnrichmentBatchPolicy.interBookDelaySeconds(for: .full) == 2)
        #expect(EnrichmentBatchPolicy.interBookDelaySeconds(for: .aiOnly) == 0)
        #expect(EnrichmentBatchPolicy.interBookDelaySeconds(for: .aiIntroductionOnly) == 0)
    }

    @Test("AI 不可用时批量页显示设置引导")
    func showsAISettingsGuidanceOnlyWhenUnavailable() {
        #expect(EnrichmentBatchPolicy.shouldShowAISettingsLink(isAIAvailable: false))
        #expect(!EnrichmentBatchPolicy.shouldShowAISettingsLink(isAIAvailable: true))
    }

    @Test("只有 AI 终态结果才记录完成时间，认证和网络失败保留重试机会")
    func recordsOnlyTerminalAIAttempts() {
        #expect(AIEnrichmentAttemptPolicy.shouldRecordCompletion(for: .found))
        #expect(AIEnrichmentAttemptPolicy.shouldRecordCompletion(for: .notFound))
        #expect(AIEnrichmentAttemptPolicy.shouldRecordCompletion(for: .validationRejected("证据不足")))

        #expect(!AIEnrichmentAttemptPolicy.shouldRecordCompletion(for: .fatalFailure("认证失败")))
        #expect(!AIEnrichmentAttemptPolicy.shouldRecordCompletion(for: .retryableFailure("网络超时")))
        #expect(!AIEnrichmentAttemptPolicy.shouldRecordCompletion(for: .cancelled))
        #expect(!AIEnrichmentAttemptPolicy.shouldRecordCompletion(for: .notAttempted))

        #expect(AIEnrichmentAttemptPolicy.shouldStopBatch(for: .fatalFailure("认证失败")))
        #expect(!AIEnrichmentAttemptPolicy.shouldStopBatch(for: .retryableFailure("网络超时")))
        #expect(!AIEnrichmentAttemptPolicy.shouldStopBatch(for: .validationRejected("证据不足")))
    }

    @Test("普通批量只有全部已尝试来源形成终态时记录完成")
    func recordsOnlyTerminalMetadataAttempts() {
        let original = BookDraft(title: "书名", author: "作者")
        var filled = original
        filled.authorDescription = "本地作者简介"

        #expect(!MetadataEnrichmentAttemptPolicy.shouldRecordCompletion(for: EnrichmentOutcome(
            originalDraft: original,
            draft: filled,
            sourceReports: [MetadataSourceReport(source: .douban, status: .retryableFailure("超时"))]
        )))
        #expect(MetadataEnrichmentAttemptPolicy.shouldRecordCompletion(for: EnrichmentOutcome(
            originalDraft: original,
            draft: original,
            sourceReports: [MetadataSourceReport(source: .douban, status: .found)]
        )))
        #expect(MetadataEnrichmentAttemptPolicy.shouldRecordCompletion(for: EnrichmentOutcome(
            originalDraft: original,
            draft: original,
            sourceReports: [
                MetadataSourceReport(source: .douban, status: .notFound),
                MetadataSourceReport(source: .goodreads, status: .notFound),
                MetadataSourceReport(source: .openLibrary, status: .notFound)
            ]
        )))
        #expect(MetadataEnrichmentAttemptPolicy.shouldRecordCompletion(for: EnrichmentOutcome(
            originalDraft: original,
            draft: original,
            sourceReports: [
                MetadataSourceReport(source: .douban, status: .found),
                MetadataSourceReport(source: .goodreads, status: .retryableFailure("超时"))
            ]
        )))

        for status in [
            LookupSourceStatus.retryableFailure("超时"),
            .fatalFailure("失败"),
            .validationRejected("身份不符"),
            .cancelled
        ] {
            #expect(!MetadataEnrichmentAttemptPolicy.shouldRecordCompletion(for: EnrichmentOutcome(
                originalDraft: original,
                draft: original,
                sourceReports: [MetadataSourceReport(source: .douban, status: status)]
            )))
        }
    }

    @Test("批量取消保留当前书已返回字段但不记录未完成阶段")
    func cancellationCommitsReturnedFieldsWithoutCompletionDates() {
        let book = Book(title: "书名", author: "作者")
        let original = BookDraft(book: book)
        var filled = original
        filled.publisher = "出版社"
        let outcome = EnrichmentOutcome(
            originalDraft: original,
            draft: filled,
            sourceReports: [MetadataSourceReport(source: .douban, status: .found)],
            aiStatus: .cancelled,
            termination: .cancelled
        )

        EnrichmentBatchCommit.apply(outcome, to: book, mode: .full, completedAt: Date())

        #expect(book.publisher == "出版社")
        #expect(book.lastEnrichmentDate == nil)
        #expect(book.lastAIEnrichmentDate == nil)
    }

    @Test("批量汇总区分成功、无资料、失败、验证拒绝并累计 Token")
    func summarizesBatchOutcomes() {
        let original = BookDraft(title: "书名", author: "作者")
        var filled = original
        filled.publisher = "出版社"

        var summary = EnrichmentBatchSummary(totalCount: 4)
        summary.record(EnrichmentOutcome(
            originalDraft: original,
            draft: filled,
            aiStatus: .found,
            tokenUsage: AITokenUsage(input: 4, output: 6, total: 10)
        ))
        summary.record(EnrichmentOutcome(
            originalDraft: original,
            draft: original,
            aiStatus: .notFound,
            tokenUsage: AITokenUsage(input: 0, output: 0, total: 0)
        ))
        summary.record(EnrichmentOutcome(
            originalDraft: original,
            draft: original,
            aiStatus: .retryableFailure("超时"),
            tokenUsage: AITokenUsage(input: 0, output: 0, total: 0)
        ))
        summary.record(EnrichmentOutcome(
            originalDraft: original,
            draft: original,
            aiStatus: .validationRejected("证据不足"),
            tokenUsage: AITokenUsage(input: 3, output: 2, total: 5)
        ))

        #expect(summary.completedCount == 4)
        #expect(summary.successCount == 1)
        #expect(summary.noDataCount == 1)
        #expect(summary.failureCount == 1)
        #expect(summary.validationRejectedCount == 1)
        #expect(summary.inputTokens == 7)
        #expect(summary.outputTokens == 8)
        #expect(summary.totalTokens == 15)
        #expect(summary.message.hasSuffix("输入 7，输出 8，总计 15 Token"))
    }

    @Test("批量运行中实时展示已处理数量、分类统计和累计 Token")
    func presentsLiveBatchSummary() {
        let original = BookDraft(title: "书名", author: "作者")
        var filled = original
        filled.publisher = "出版社"
        var summary = EnrichmentBatchSummary(totalCount: 2)

        #expect(summary.progressMessage == "已处理 0/2，成功 0，无资料 0，失败 0，验证拒绝 0\n累计 Token：输入 0，输出 0，总计 0")

        summary.record(EnrichmentOutcome(
            originalDraft: original,
            draft: filled,
            aiStatus: .found,
            tokenUsage: AITokenUsage(input: 4, output: 6, total: 10)
        ))

        #expect(summary.progressMessage == "已处理 1/2，成功 1，无资料 0，失败 0，验证拒绝 0\n累计 Token：输入 4，输出 6，总计 10")
    }

    @Test("批量 Token 累计溢出时饱和而不崩溃")
    func saturatesBatchTokenOverflow() {
        let draft = BookDraft(title: "书名", author: "作者")
        var summary = EnrichmentBatchSummary(totalCount: 2)

        summary.record(EnrichmentOutcome(
            originalDraft: draft,
            draft: draft,
            aiStatus: .found,
            tokenUsage: AITokenUsage(input: Int.max, output: Int.max, total: Int.max)
        ))
        summary.record(EnrichmentOutcome(
            originalDraft: draft,
            draft: draft,
            aiStatus: .found,
            tokenUsage: AITokenUsage(input: 1, output: 1, total: 1)
        ))

        #expect(summary.inputTokens == Int.max)
        #expect(summary.outputTokens == Int.max)
        #expect(summary.totalTokens == Int.max)
    }

    @Test("任一次 AI 调用未返回 usage 时累计 Token 保持未知")
    func unknownTokenUsageDoesNotBecomeZeroOrPartialTotal() {
        let draft = BookDraft(title: "书名", author: "作者")
        var summary = EnrichmentBatchSummary(totalCount: 2)
        summary.record(EnrichmentOutcome(
            originalDraft: draft,
            draft: draft,
            aiStatus: .found,
            tokenUsage: AITokenUsage(input: 4, output: 6, total: 10)
        ))
        summary.record(EnrichmentOutcome(
            originalDraft: draft,
            draft: draft,
            aiStatus: .found,
            tokenUsage: .unknown
        ))

        let inputTokens: Int? = summary.inputTokens
        let outputTokens: Int? = summary.outputTokens
        let totalTokens: Int? = summary.totalTokens
        #expect(inputTokens == nil)
        #expect(outputTokens == nil)
        #expect(totalTokens == nil)
        #expect(summary.progressMessage.contains("输入 未知，输出 未知，总计 未知"))
        #expect(!summary.progressMessage.contains("总计 10"))
    }

    @Test("普通来源有结果但 AI 致命失败时按失败汇总并保留原因")
    func fatalAIStatusTakesPriorityOverPartialChanges() {
        let original = BookDraft(title: "书名", author: "作者")
        var partiallyFilled = original
        partiallyFilled.publisher = "普通来源出版社"
        var summary = EnrichmentBatchSummary(totalCount: 1)

        summary.record(EnrichmentOutcome(
            originalDraft: original,
            draft: partiallyFilled,
            sourceReports: [MetadataSourceReport(source: .douban, status: .found)],
            aiStatus: .fatalFailure("API Key 或权限无效")
        ))

        #expect(summary.successCount == 0)
        #expect(summary.failureCount == 1)
        #expect(summary.message.contains("API Key 或权限无效"))
    }
}
