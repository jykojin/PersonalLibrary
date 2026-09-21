import Foundation
import Testing
import UIKit
@testable import PersonalLibrary

@Suite("Enrichment Entry Integration Tests")
struct EnrichmentEntryIntegrationTests {
    @Test("页面消失不取消补全，取消必须来自明确用户操作")
    func viewDisappearanceDoesNotCancelEnrichment() {
        #expect(!EnrichmentTaskLifecyclePolicy.shouldCancelOnDisappear(isSceneActive: false))
        #expect(!EnrichmentTaskLifecyclePolicy.shouldCancelOnDisappear(isSceneActive: true))
    }

    @MainActor
    @Test("后台额度到期只释放系统租约，不取消正在等待的补全")
    func backgroundExpirationDoesNotCancelEnrichment() async {
        let host = RecordingBackgroundTaskManager()
        let gate = BackgroundOperationGate()
        let execution = EnrichmentBackgroundExecution(taskManager: host)

        let operation = Task {
            await execution.run(named: "test-enrichment") {
                await gate.waitForRelease()
                return 42
            }
        }

        await gate.waitUntilStarted()
        host.expireCurrentTask()

        #expect(host.endedTaskCount == 1)
        #expect(!operation.isCancelled)

        await gate.release()
        #expect(await operation.value == 42)
        #expect(host.endedTaskCount == 1)
    }

    @Test("补全返回时保留请求期间的用户编辑并写入其余新字段")
    func preservesConcurrentFormEdits() {
        let date = PublicationDateParser.parse("2024-03")
        let original = BookDraft(title: "示例图书", author: "示例作者")
        var enriched = original
        enriched.translator = "候选译者"
        enriched.publisher = "候选出版社"
        enriched.publishDate = date
        enriched.bookDescription = "候选图书简介"
        enriched.authorDescription = "候选作者简介"
        enriched.aiIntroduction = "候选 AI简介"
        let outcome = EnrichmentOutcome(originalDraft: original, draft: enriched)
        var formNow = original
        formNow.publisher = "用户刚刚输入的出版社"

        let rebased = outcome.rebased(on: formNow)

        #expect(rebased.originalDraft == formNow)
        #expect(rebased.draft.publisher == "用户刚刚输入的出版社")
        #expect(rebased.draft.translator == "候选译者")
        #expect(rebased.draft.publishDate == date)
        #expect(rebased.draft.bookDescription == "候选图书简介")
        #expect(rebased.draft.authorDescription == "候选作者简介")
        #expect(rebased.draft.aiIntroduction == "候选 AI简介")
        #expect(!rebased.changedFields.contains(.publisher))
    }

    @Test("添加页可用书名或 ISBN 任一锚点启动补全")
    func acceptsTitleOrISBNAsLookupAnchor() {
        #expect(EnrichmentEntryPolicy.canStart(title: "示例图书", isbn: ""))
        #expect(EnrichmentEntryPolicy.canStart(title: " ", isbn: "9787020002207"))
        #expect(!EnrichmentEntryPolicy.canStart(title: "\n", isbn: " "))
    }

    @Test("编辑页按字段顺序展示 AI 验证拒绝原因")
    func presentsValidationRejectionsInStableFieldOrder() {
        let draft = BookDraft(title: "示例图书", author: "示例作者")
        let outcome = EnrichmentOutcome(
            originalDraft: draft,
            draft: draft,
            rejections: [
                .aiIntroduction: "研究来源不足",
                .publisher: "来源 URL 无效",
                .translator: "缺少有效来源"
            ]
        )

        #expect(outcome.rejectionDetails.map { "\($0.fieldName)：\($0.reason)" } == [
            "译者：缺少有效来源",
            "出版社：来源 URL 无效",
            "AI简介：研究来源不足"
        ])
    }

    @Test("单本入口可区分 AI 网络、认证和验证拒绝错误")
    func exposesAIIssueForEntryPresentation() {
        let draft = BookDraft(title: "示例图书", author: "示例作者")
        let cases: [(LookupSourceStatus, String)] = [
            (.retryableFailure("网络超时"), "稍后可重试: 网络超时"),
            (.fatalFailure("API Key 或权限无效"), "失败: API Key 或权限无效"),
            (.validationRejected("来源不足"), "验证拒绝: 来源不足"),
            (.error("响应异常"), "出错: 响应异常")
        ]

        for (status, expected) in cases {
            let outcome = EnrichmentOutcome(
                originalDraft: draft,
                draft: draft,
                aiStatus: status
            )
            #expect(outcome.aiIssueDescription == expected)
        }

        #expect(EnrichmentOutcome(originalDraft: draft, draft: draft, aiStatus: .notFound).aiIssueDescription == nil)
        #expect(EnrichmentOutcome(originalDraft: draft, draft: draft, aiStatus: .found).aiIssueDescription == nil)
    }

    @Test("单本表单累计普通与 AI 终态并在保存时写完成标记")
    func accumulatesManualEntryCompletionMarkers() {
        let draft = BookDraft(title: "示例图书", author: "示例作者")
        var markers = EnrichmentManualCommitMarkers()

        markers.record(
            EnrichmentOutcome(
                originalDraft: draft,
                draft: draft,
                sourceReports: [.init(source: .douban, status: .found)],
                aiStatus: .retryableFailure("超时")
            ),
            mode: .full
        )
        markers.record(
            EnrichmentOutcome(
                originalDraft: draft,
                draft: draft,
                aiStatus: .found
            ),
            mode: .aiOnly
        )

        #expect(markers.shouldRecordMetadataCompletion)
        #expect(markers.shouldRecordAICompletion)
    }

    @Test("单本表单不记录取消或临时失败的完成标记")
    func doesNotRecordIncompleteManualEntryAttempts() {
        let draft = BookDraft(title: "示例图书", author: "示例作者")
        var markers = EnrichmentManualCommitMarkers()

        markers.record(
            EnrichmentOutcome(
                originalDraft: draft,
                draft: draft,
                sourceReports: [.init(source: .douban, status: .found)],
                aiStatus: .found,
                termination: .cancelled
            ),
            mode: .full
        )
        markers.record(
            EnrichmentOutcome(
                originalDraft: draft,
                draft: draft,
                aiStatus: .retryableFailure("网络中断")
            ),
            mode: .aiOnly
        )

        #expect(!markers.shouldRecordMetadataCompletion)
        #expect(!markers.shouldRecordAICompletion)
    }
}

@MainActor
private final class RecordingBackgroundTaskManager: EnrichmentBackgroundTaskManaging {
    private var expirationHandler: (@MainActor @Sendable () -> Void)?
    private(set) var endedTaskCount = 0

    func beginTask(
        named name: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier {
        self.expirationHandler = expirationHandler
        return UIBackgroundTaskIdentifier(rawValue: 1)
    }

    func endTask(_ identifier: UIBackgroundTaskIdentifier) {
        endedTaskCount += 1
    }

    func expireCurrentTask() {
        expirationHandler?()
    }
}

private actor BackgroundOperationGate {
    private var started = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func waitForRelease() async {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
