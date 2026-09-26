import Foundation
import SwiftData

enum EnrichmentEntryPolicy {
    static func canStart(title: String, isbn: String?) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(isbn ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum EnrichmentTaskLifecyclePolicy {
    /// SwiftUI does not guarantee whether `scenePhase` or `onDisappear` changes first.
    /// A disappearance is therefore never sufficient evidence of an explicit user cancellation.
    static func shouldCancelOnDisappear(isSceneActive _: Bool) -> Bool {
        false
    }
}

enum EnrichmentBatchPolicy {
    static func isCandidate(_ book: Book, mode: EnrichmentMode) -> Bool {
        guard !book.isArchived else { return false }
        switch mode {
        case .full:
            return book.bookType == .paper
                && book.needsEnrichment
                && book.lastEnrichmentDate == nil
        case .aiOnly:
            return book.lastAIEnrichmentDate == nil
                && !BookDraft(book: book).missingFields.isEmpty
        case .aiIntroductionOnly:
            return book.lastAIEnrichmentDate == nil
                && BookDraft(book: book).missingFields.contains(.aiIntroduction)
        }
    }

    static func interBookDelaySeconds(for mode: EnrichmentMode) -> UInt64 {
        mode == .full ? 2 : 0
    }

    static func shouldShowAISettingsLink(isAIAvailable: Bool) -> Bool {
        !isAIAvailable
    }
}

enum AIEnrichmentAttemptPolicy {
    static func shouldRecordCompletion(for status: LookupSourceStatus) -> Bool {
        switch status {
        case .found, .noNewFields, .notFound, .validationRejected:
            return true
        case .notAttempted, .retryableFailure, .fatalFailure, .cancelled, .error:
            return false
        }
    }

    static func shouldStopBatch(for status: LookupSourceStatus) -> Bool {
        if case .fatalFailure = status { return true }
        return false
    }
}

enum MetadataEnrichmentAttemptPolicy {
    static func shouldRecordCompletion(for outcome: EnrichmentOutcome) -> Bool {
        let attemptedStatuses = outcome.sourceReports.map(\.status).filter { status in
            status != .notAttempted
        }
        guard !attemptedStatuses.isEmpty else { return false }
        if attemptedStatuses.contains(.found) { return true }
        return attemptedStatuses.allSatisfy { $0 == .notFound }
    }
}

/// 表单入口先把补全结果写进临时状态，用户点“保存”后才写 Book。
/// 这里累计本次编辑会话中已经到达终态的阶段，避免后一次补全覆盖前一次的完成标记。
struct EnrichmentManualCommitMarkers: Equatable, Sendable {
    private(set) var shouldRecordMetadataCompletion = false
    private(set) var shouldRecordAICompletion = false

    mutating func record(_ outcome: EnrichmentOutcome, mode: EnrichmentMode) {
        guard outcome.termination == .completed else { return }
        if mode == .full,
           MetadataEnrichmentAttemptPolicy.shouldRecordCompletion(for: outcome) {
            shouldRecordMetadataCompletion = true
        }
        if AIEnrichmentAttemptPolicy.shouldRecordCompletion(for: outcome.aiStatus) {
            shouldRecordAICompletion = true
        }
    }
}

enum EnrichmentBatchCommit {
    static func apply(
        _ outcome: EnrichmentOutcome,
        to book: Book,
        mode: EnrichmentMode,
        completedAt: Date = Date()
    ) {
        outcome.apply(to: book)

        guard outcome.termination == .completed else { return }
        if mode == .full,
           MetadataEnrichmentAttemptPolicy.shouldRecordCompletion(for: outcome) {
            book.lastEnrichmentDate = completedAt
        }
        if AIEnrichmentAttemptPolicy.shouldRecordCompletion(for: outcome.aiStatus) {
            book.lastAIEnrichmentDate = completedAt
        }
    }
}

struct EnrichmentBookSnapshot: Equatable, Sendable {
    let draft: BookDraft
    let isWereadUserImported: Bool
}

enum EnrichmentBookPersistence {
    static func eligibleBatchSnapshot(
        for id: PersistentIdentifier,
        mode: EnrichmentMode,
        in container: ModelContainer
    ) -> EnrichmentBookSnapshot? {
        guard let book = activeBook(for: id, in: container),
              EnrichmentBatchPolicy.isCandidate(book, mode: mode) else {
            return nil
        }
        return snapshot(of: book)
    }

    static func activeSnapshot(
        for id: PersistentIdentifier,
        in container: ModelContainer
    ) -> EnrichmentBookSnapshot? {
        guard let book = activeBook(for: id, in: container) else { return nil }
        return snapshot(of: book)
    }

    static func commitBatch(
        _ outcome: EnrichmentOutcome,
        to id: PersistentIdentifier,
        mode: EnrichmentMode,
        in container: ModelContainer,
        completedAt: Date = Date()
    ) throws -> EnrichmentOutcome? {
        let context = ModelContext(container)
        guard let book = fetchBook(for: id, in: context),
              !book.isArchived else {
            return nil
        }

        let rebased = outcome.rebased(on: BookDraft(book: book))
        EnrichmentBatchCommit.apply(rebased, to: book, mode: mode, completedAt: completedAt)
        try context.save()
        return rebased
    }

    static func commitWeRead(
        _ outcome: EnrichmentOutcome,
        to id: PersistentIdentifier,
        in container: ModelContainer,
        completedAt: Date = Date()
    ) throws -> EnrichmentOutcome? {
        let context = ModelContext(container)
        guard let book = fetchBook(for: id, in: context),
              !book.isArchived else {
            return nil
        }

        let rebased = outcome.rebased(on: BookDraft(book: book))
        rebased.apply(to: book)
        if rebased.termination == .completed,
           AIEnrichmentAttemptPolicy.shouldRecordCompletion(for: rebased.aiStatus) {
            book.lastAIEnrichmentDate = completedAt
        }
        try context.save()
        return rebased
    }

    private static func activeBook(
        for id: PersistentIdentifier,
        in container: ModelContainer
    ) -> Book? {
        let context = ModelContext(container)
        guard let book = fetchBook(for: id, in: context),
              !book.isArchived else {
            return nil
        }
        return book
    }

    private static func snapshot(of book: Book) -> EnrichmentBookSnapshot {
        EnrichmentBookSnapshot(
            draft: BookDraft(book: book),
            isWereadUserImported: book.isWereadUserImported
        )
    }

    private static func fetchBook(
        for id: PersistentIdentifier,
        in context: ModelContext
    ) -> Book? {
        var descriptor = FetchDescriptor<Book>(
            predicate: #Predicate { $0.persistentModelID == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

struct EnrichmentBatchSummary: Equatable, Sendable {
    let totalCount: Int
    private(set) var completedCount = 0
    private(set) var successCount = 0
    private(set) var noDataCount = 0
    private(set) var failureCount = 0
    private(set) var validationRejectedCount = 0
    private(set) var lastIssue: String?
    private var tokenUsage = AITokenUsage.accumulator

    var inputTokens: Int? { tokenUsage.input }
    var outputTokens: Int? { tokenUsage.output }
    var totalTokens: Int? { tokenUsage.total }

    var progressMessage: String {
        "已处理 \(completedCount)/\(totalCount)，成功 \(successCount)，无资料 \(noDataCount)，失败 \(failureCount)，验证拒绝 \(validationRejectedCount)\n"
            + "累计 Token：输入 \(tokenText(tokenUsage.input))，输出 \(tokenText(tokenUsage.output))，总计 \(tokenText(tokenUsage.total))"
    }

    mutating func record(_ outcome: EnrichmentOutcome) {
        completedCount += 1
        if outcome.aiStatus != .notAttempted {
            tokenUsage.add(outcome.tokenUsage)
        }
        let statuses = [outcome.aiStatus] + outcome.sourceReports.map(\.status)

        if let failure = statuses.first(where: Self.isFailure) {
            failureCount += 1
            lastIssue = failure.displayText
        } else if let rejection = statuses.first(where: Self.isValidationRejected) {
            validationRejectedCount += 1
            lastIssue = rejection.displayText
        } else if !outcome.changedFields.isEmpty {
            successCount += 1
        } else {
            noDataCount += 1
        }
    }

    var message: String {
        var parts = [
            "成功 \(successCount)/\(totalCount)",
            "无资料 \(noDataCount)",
            "失败 \(failureCount)",
            "验证拒绝 \(validationRejectedCount)"
        ]
        if let lastIssue {
            parts.append("原因：\(lastIssue)")
        }
        if tokenUsage.hasSamples {
            parts.append(
                "输入 \(tokenText(tokenUsage.input))，输出 \(tokenText(tokenUsage.output))，总计 \(tokenText(tokenUsage.total)) Token"
            )
        }
        return parts.joined(separator: "，")
    }

    private func tokenText(_ value: Int?) -> String {
        value.map(String.init) ?? (tokenUsage.hasSamples ? "未知" : "0")
    }

    private static func isValidationRejected(_ status: LookupSourceStatus) -> Bool {
        if case .validationRejected = status { return true }
        return false
    }

    private static func isFailure(_ status: LookupSourceStatus) -> Bool {
        switch status {
        case .retryableFailure, .fatalFailure, .cancelled, .error:
            return true
        case .notAttempted, .found, .noNewFields, .notFound, .validationRejected:
            return false
        }
    }
}

enum WeReadEnrichmentPolicy {
    static func shouldDelayBeforeBook(
        hasPreviousWeReadNetworkCall: Bool,
        needsWeReadEnrichment: Bool,
        needsBookmarkFetch: Bool
    ) -> Bool {
        hasPreviousWeReadNetworkCall && (needsWeReadEnrichment || needsBookmarkFetch)
    }

    static func shouldDisplayTokenUsage(_ usage: AITokenUsage) -> Bool {
        usage.hasSamples
    }

    static func shouldProcess(
        isArchived: Bool = false,
        hasCompletedWeReadEnrichment: Bool,
        hasCompletedAIEnrichment: Bool,
        aiIntroductionMissing: Bool,
        notebookChanged: Bool
    ) -> Bool {
        !isArchived && (
            !hasCompletedWeReadEnrichment
            || (!hasCompletedAIEnrichment && aiIntroductionMissing)
            || notebookChanged
        )
    }

    static func mode(
        isUserImported: Bool,
        needsWeReadEnrichment: Bool,
        aiIntroductionMissing: Bool
    ) -> EnrichmentMode? {
        if isUserImported && (needsWeReadEnrichment || aiIntroductionMissing) {
            return .full
        }
        if aiIntroductionMissing {
            return .aiIntroductionOnly
        }
        return nil
    }
}
