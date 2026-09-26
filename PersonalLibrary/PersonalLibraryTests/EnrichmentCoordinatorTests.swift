import Foundation
import Testing
@testable import PersonalLibrary

@Suite("Enrichment Coordinator Tests")
struct EnrichmentCoordinatorTests {
    @Test("full 模式按本地作者简介、普通来源、AI 的顺序完成单本补全")
    func fullModeUsesUnifiedSequence() async {
        let recorder = CoordinatorRecorder()
        let metadata = StubBookMetadataLookup(recorder: recorder)
        let ai = StubAIEnricher(recorder: recorder)
        let coordinator = EnrichmentCoordinator(metadataLookup: metadata, aiEnricher: ai)
        let original = BookDraft(title: "示例图书", author: "示例作者")

        let outcome = await coordinator.enrich(
            original,
            mode: .full,
            localAuthorDescription: "本地作者简介"
        )

        #expect(await recorder.values == ["metadata", "ai"])
        #expect(outcome.draft.publisher == "普通来源出版社")
        #expect(outcome.draft.authorDescription == "本地作者简介")
        #expect(outcome.draft.aiIntroduction == "AI简介")
    }

    @Test("aiOnly 跳过普通来源且只把仍为空的字段交给 AI")
    func aiOnlySkipsMetadata() async {
        let recorder = CoordinatorRecorder()
        let ai = CapturingAIEnricher(recorder: recorder)
        let coordinator = EnrichmentCoordinator(
            metadataLookup: StubBookMetadataLookup(recorder: recorder),
            aiEnricher: ai
        )
        let draft = BookDraft(
            title: "示例图书",
            author: "示例作者",
            publisher: "已有出版社"
        )

        _ = await coordinator.enrich(draft, mode: .aiOnly, localAuthorDescription: nil)

        #expect(await recorder.values == ["ai"])
        let targets = await ai.lastTargets
        #expect(targets?.contains(.aiIntroduction) == true)
        #expect(targets?.contains(.publisher) == false)
    }

    @Test("aiIntroductionOnly 只请求 AI简介")
    func introductionOnlyScopesAITarget() async {
        let recorder = CoordinatorRecorder()
        let ai = CapturingAIEnricher(recorder: recorder)
        let coordinator = EnrichmentCoordinator(
            metadataLookup: StubBookMetadataLookup(recorder: recorder),
            aiEnricher: ai
        )

        _ = await coordinator.enrich(
            BookDraft(title: "示例图书", author: "示例作者"),
            mode: .aiIntroductionOnly,
            localAuthorDescription: nil
        )

        #expect(await recorder.values == ["ai"])
        #expect(await ai.lastTargets == [.aiIntroduction])
    }

    @Test("普通来源已补字段不会再次请求 AI，且 AI 不覆盖已有值")
    func metadataResultNarrowsAITargets() async {
        let recorder = CoordinatorRecorder()
        let ai = CapturingAIEnricher(recorder: recorder)
        let coordinator = EnrichmentCoordinator(
            metadataLookup: StubBookMetadataLookup(recorder: recorder),
            aiEnricher: ai
        )

        let outcome = await coordinator.enrich(
            BookDraft(title: "示例图书", author: "示例作者"),
            mode: .full,
            localAuthorDescription: nil
        )

        #expect(outcome.draft.publisher == "普通来源出版社")
        #expect(await ai.lastTargets?.contains(.publisher) == false)
    }

    @Test("普通来源取消后不再调用 AI")
    func cancellationStopsLaterStages() async {
        let recorder = CoordinatorRecorder()
        let coordinator = EnrichmentCoordinator(
            metadataLookup: CancelledBookMetadataLookup(recorder: recorder),
            aiEnricher: CapturingAIEnricher(recorder: recorder)
        )

        let outcome = await coordinator.enrich(
            BookDraft(title: "示例图书", author: "示例作者"),
            mode: .full,
            localAuthorDescription: nil
        )

        #expect(await recorder.values == ["metadata"])
        #expect(outcome.termination == .cancelled)
        #expect(outcome.aiStatus == .notAttempted)
    }

    @Test("未配置 AI 时 full 仍保留普通来源结果")
    func fullModeWorksWithoutAIConfiguration() async {
        let recorder = CoordinatorRecorder()
        let coordinator = EnrichmentCoordinator(
            metadataLookup: StubBookMetadataLookup(recorder: recorder),
            aiEnricher: nil
        )

        let outcome = await coordinator.enrich(
            BookDraft(title: "示例图书", author: "示例作者"),
            mode: .full,
            localAuthorDescription: nil
        )

        #expect(outcome.draft.publisher == "普通来源出版社")
        #expect(outcome.aiStatus == .notAttempted)
        #expect(await recorder.values == ["metadata"])
    }

    @Test("普通来源声称命中但没有可合入字段时不记录批量完成")
    func emptyMetadataHitDoesNotCompleteBatchAttempt() async {
        let original = BookDraft(title: "示例图书", author: "示例作者", publisher: "已有出版社")
        let metadata = SequentialBookMetadataLookup(sources: [EmptyFoundMetadataSource()])
        let coordinator = EnrichmentCoordinator(metadataLookup: metadata, aiEnricher: nil)

        let outcome = await coordinator.enrich(
            original,
            mode: .full,
            localAuthorDescription: nil
        )

        #expect(outcome.draft == original)
        #expect(outcome.sourceReports.map(\.status.displayText) == ["已匹配，暂无可补全字段"])
        #expect(!MetadataEnrichmentAttemptPolicy.shouldRecordCompletion(for: outcome))
        var summary = EnrichmentBatchSummary(totalCount: 1)
        summary.record(outcome)
        #expect(summary.noDataCount == 1)
        #expect(summary.validationRejectedCount == 0)
        #expect(summary.successCount == 0)
    }
}

private actor CoordinatorRecorder {
    private(set) var values: [String] = []
    func record(_ value: String) { values.append(value) }
}

private struct StubBookMetadataLookup: BookMetadataLookup {
    let recorder: CoordinatorRecorder

    func lookup(draft: BookDraft, missingFields: Set<EnrichmentField>) async -> MetadataLookupOutcome {
        await recorder.record("metadata")
        let candidate = BookDraft(title: "", author: "", publisher: "普通来源出版社")
        return MetadataLookupOutcome(
            draft: draft.fillingMissingFields(from: candidate, limitedTo: missingFields),
            sourceReports: [MetadataSourceReport(source: .douban, status: .found)]
        )
    }
}

private struct CancelledBookMetadataLookup: BookMetadataLookup {
    let recorder: CoordinatorRecorder

    func lookup(draft: BookDraft, missingFields: Set<EnrichmentField>) async -> MetadataLookupOutcome {
        await recorder.record("metadata")
        return MetadataLookupOutcome(
            draft: draft,
            sourceReports: [MetadataSourceReport(source: .douban, status: .cancelled)]
        )
    }
}

private struct EmptyFoundMetadataSource: MetadataSourceLookup {
    let source = BookMetadataSource.douban

    func lookup(draft: BookDraft, missingFields: Set<EnrichmentField>) async -> MetadataSourceLookupResult {
        MetadataSourceLookupResult(
            candidate: BookDraft(title: "", author: "", publisher: draft.publisher),
            status: .found
        )
    }
}

private struct StubAIEnricher: AIEnriching {
    let recorder: CoordinatorRecorder

    func enrich(draft: BookDraft, targets: Set<EnrichmentField>) async -> AIEnrichmentOutcome {
        await recorder.record("ai")
        let candidate = BookDraft(title: "", author: "", aiIntroduction: "AI简介")
        return AIEnrichmentOutcome(
            draft: draft.fillingMissingFields(from: candidate, limitedTo: targets),
            status: .found,
            evidence: [.aiIntroduction: [URL(string: "https://research.example/book")!]],
            rejections: [:],
            tokenUsage: AITokenUsage(input: 1, output: 2, total: 3)
        )
    }
}

private actor CapturingAIEnricher: AIEnriching {
    let recorder: CoordinatorRecorder
    private(set) var lastTargets: Set<EnrichmentField>?

    init(recorder: CoordinatorRecorder) {
        self.recorder = recorder
    }

    func enrich(draft: BookDraft, targets: Set<EnrichmentField>) async -> AIEnrichmentOutcome {
        lastTargets = targets
        await recorder.record("ai")
        let candidate = BookDraft(
            title: "",
            author: "",
            publisher: "AI 不应覆盖的出版社",
            aiIntroduction: "AI简介"
        )
        return AIEnrichmentOutcome(
            draft: draft.fillingMissingFields(from: candidate, limitedTo: targets),
            status: .found,
            evidence: [:],
            rejections: [:],
            tokenUsage: .unknown
        )
    }
}
