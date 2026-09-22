import Foundation
import Testing
@testable import PersonalLibrary

@Suite("AI Enrichment Service Tests")
struct AIEnrichmentServiceTests {
    @Test("事实检索返回错误状态时不伪装成未找到")
    func modelReportedFactErrorIsNotNotFound() async {
        let unavailable = #"{"status":"error","identity":{"matched_title":"人生问答","matched_author":"成庆","matched_isbn":"9787547330135"},"fields":{}}"#
        let client = SequencedAICompletionClient(responses: [
            AICompletionResponse(content: unavailable, usage: .unknown),
            AICompletionResponse(content: unavailable, usage: .unknown)
        ])
        let service = AIEnrichmentService(
            client: client,
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )

        let outcome = await service.enrich(
            draft: BookDraft(
                title: "人生问答",
                author: "成庆",
                isbn: "9787547330135"
            ),
            targets: [.translator]
        )

        #expect(outcome.status == .validationRejected("AI 未按约定返回可验证结果"))
        #expect(outcome.rejections.isEmpty)
        #expect(await client.requests.count == 2)
    }

    @Test("AI简介达到独立时间预算后取消请求并返回可重试超时")
    func stopsAtIntroductionDeadline() async {
        let client = DelayedAICompletionClient(
            delay: .milliseconds(250),
            response: AICompletionResponse(content: validIntroductionJSON(), usage: .unknown)
        )
        let service = AIEnrichmentService(
            client: client,
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key"),
            introductionTimeout: .milliseconds(30)
        )
        let outcome = await service.enrich(
            draft: BookDraft(title: "示例图书", author: "示例作者"),
            targets: [.aiIntroduction]
        )

        guard case .retryableFailure(let message) = outcome.status else {
            Issue.record("超时应保持可重试，实际为 \(outcome.status)")
            return
        }
        #expect(message.contains("超时"))
        #expect(await client.wasCancelled)
    }

    @Test("AI简介硬截止不等待忽略取消的底层客户端")
    func introductionDeadlineDoesNotWaitForNonCooperativeClient() async {
        let client = NonCooperativeDelayedAICompletionClient(
            delay: .seconds(2),
            response: AICompletionResponse(content: validIntroductionJSON(), usage: .unknown)
        )
        let service = AIEnrichmentService(
            client: client,
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key"),
            introductionTimeout: .milliseconds(30)
        )
        let clock = ContinuousClock()
        let start = clock.now

        let outcome = await service.enrich(
            draft: BookDraft(title: "示例图书", author: "示例作者"),
            targets: [.aiIntroduction]
        )

        let elapsed = start.duration(to: clock.now)
        guard case .retryableFailure(let message) = outcome.status else {
            Issue.record("硬截止应返回可重试超时，实际为 \(outcome.status)")
            return
        }
        #expect(message.contains("超时"))
        #expect(elapsed < .seconds(1), "30ms 硬截止实际等待了 \(elapsed)")
    }

    @Test("AI简介阶段超时时保留此前已验证的事实字段")
    func preservesVerifiedFactsWhenIntroductionTimesOut() async {
        let factResponse = #"{"status":"ok","identity":{"matched_title":"示例图书","matched_author":"示例作者"},"fields":{"publisher":{"value":"示例出版社","sources":["https://research.example/books/1"]}}}"#
        let client = FactThenDelayedIntroductionClient(factResponse: factResponse)
        let service = AIEnrichmentService(
            client: client,
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key"),
            introductionTimeout: .milliseconds(30)
        )

        let outcome = await service.enrich(
            draft: BookDraft(title: "示例图书", author: "示例作者"),
            targets: [.publisher, .aiIntroduction]
        )

        #expect(outcome.draft.publisher == "示例出版社")
        #expect(outcome.draft.aiIntroduction == nil)
        guard case .retryableFailure(let message) = outcome.status else {
            Issue.record("AI简介超时应保持可重试")
            return
        }
        #expect(message.contains("超时"))
        #expect(await client.requestCount == 2)
    }

    @Test("正式 AI 事实检索关闭深度思考并限制输出长度")
    func factRetrievalUsesLowLatencyGenerationOptions() async {
        let response = #"{"status":"ok","identity":{"matched_title":"示例图书","matched_author":"示例作者"},"fields":{"publisher":{"value":"示例出版社","sources":["https://research.example/books/1"]}}}"#
        let client = SequencedAICompletionClient(responses: [
            AICompletionResponse(content: response, usage: .unknown)
        ])
        let service = AIEnrichmentService(
            client: client,
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )

        _ = await service.enrich(
            draft: BookDraft(title: "示例图书", author: "示例作者"),
            targets: [.publisher]
        )

        let request = await client.requests.first
        #expect(request?.enableThinking == false)
        #expect(request?.maximumOutputTokens == 4_096)
    }

    @Test("事实检索重试共享同一个阶段硬截止")
    func factRetriesShareOneStageDeadline() async {
        let client = SlowInvalidFactThenValidClient(
            firstDelay: .milliseconds(100)
        )
        let service = AIEnrichmentService(
            client: client,
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key"),
            factTimeout: .seconds(2)
        )

        let outcome = await service.enrich(
            draft: BookDraft(title: "示例图书", author: "示例作者"),
            targets: [.publisher]
        )

        #expect(outcome.status == .found)
        let requests = await client.requests
        guard requests.count == 2,
              let firstTimeout = requests[0].timeoutInterval,
              let retryTimeout = requests[1].timeoutInterval else {
            Issue.record("两次事实请求都应携带同一阶段 deadline 的剩余预算")
            return
        }
        #expect(firstTimeout <= 2)
        #expect(retryTimeout < firstTimeout)
    }

    @Test("事实检索达到输出上限形成不完整 JSON 时扩大预算重试")
    func retriesIncompleteFactJSONWithLargerBudget() async {
        let completeResponse = #"{"status":"ok","identity":{"matched_title":"示例图书","matched_author":"示例作者"},"fields":{"publisher":{"value":"示例出版社","sources":["https://research.example/books/1"]}}}"#
        let client = SequencedAICompletionClient(responses: [
            AICompletionResponse(
                content: #"{"status":"ok","identity":{"matched_title":"示例图书""#,
                usage: AITokenUsage(input: 100, output: 2_048, total: 2_148)
            ),
            AICompletionResponse(
                content: completeResponse,
                usage: AITokenUsage(input: 120, output: 300, total: 420)
            )
        ])
        let service = AIEnrichmentService(
            client: client,
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )

        let outcome = await service.enrich(
            draft: BookDraft(title: "示例图书", author: "示例作者"),
            targets: [.publisher]
        )

        #expect(outcome.draft.publisher == "示例出版社")
        #expect(outcome.status == .found)
        #expect(outcome.tokenUsage == AITokenUsage(input: 220, output: 2_348, total: 2_568))
        let requests = await client.requests
        #expect(requests.count == 2)
        if requests.count == 2 {
            #expect((requests[1].maximumOutputTokens ?? 0) > (requests[0].maximumOutputTokens ?? 0))
        }
    }

    @Test("正式 AI 简介及其验证重试开启深度思考并预留充足输出长度")
    func introductionUsesDeepThinkingGenerationOptionsForEveryAttempt() async {
        let client = SequencedAICompletionClient(responses: [
            AICompletionResponse(content: #"{"status":"ok"}"#, usage: .unknown),
            AICompletionResponse(content: validIntroductionJSON(), usage: .unknown)
        ])
        let service = AIEnrichmentService(
            client: client,
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )

        _ = await service.enrich(
            draft: BookDraft(title: "示例图书", author: "示例作者"),
            targets: [.aiIntroduction]
        )

        let requests = await client.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.enableThinking == true })
        #expect(requests.map(\.maximumCompletionTokens) == [12_288, 16_384])
        #expect(requests.allSatisfy { $0.maximumOutputTokens == nil })
        #expect(requests.allSatisfy { $0.thinkingBudget == 4_096 })
        #expect(requests.allSatisfy { $0.timeoutInterval == 600 })
    }

    @Test("AI简介达到模型输出上限时不采用残缺结果并扩大预算重试")
    func retriesIntroductionThatReachedOutputLimit() async {
        let client = SequencedAICompletionClient(responses: [
            AICompletionResponse(
                content: validIntroductionJSON(),
                usage: AITokenUsage(input: 100, output: 12_288, total: 12_388),
                finishReason: .length
            ),
            AICompletionResponse(
                content: validIntroductionJSON(),
                usage: AITokenUsage(input: 120, output: 2_000, total: 2_120),
                finishReason: .stop
            )
        ])
        let service = AIEnrichmentService(
            client: client,
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )

        let outcome = await service.enrich(
            draft: BookDraft(title: "示例图书", author: "示例作者"),
            targets: [.aiIntroduction]
        )

        #expect(outcome.status == .found)
        #expect(outcome.draft.aiIntroduction != nil)
        #expect(await client.requests.count == 2)
    }

    @Test("AI简介阶段预算与 HTTP 请求超时保持一致")
    func introductionTimeoutUsesSingleSourceOfTruth() async {
        let client = SequencedAICompletionClient(responses: [
            AICompletionResponse(content: validIntroductionJSON(), usage: .unknown)
        ])
        let service = AIEnrichmentService(
            client: client,
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key"),
            introductionTimeout: .milliseconds(125)
        )

        _ = await service.enrich(
            draft: BookDraft(title: "示例图书", author: "示例作者"),
            targets: [.aiIntroduction]
        )

        let request = await client.requests.first
        #expect(request?.timeoutInterval == 0.125)
    }

    @Test("第一次 AI 调用失败时 Token 用量保持未知")
    func reportsUnknownTokenUsageWhenFirstCallFails() async {
        let client = FailingAICompletionClient(error: AIClientError.server(statusCode: 503))
        let service = AIEnrichmentService(
            client: client,
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )

        let outcome = await service.enrich(
            draft: BookDraft(title: "示例图书", author: "示例作者"),
            targets: [.aiIntroduction]
        )

        #expect(outcome.tokenUsage.hasSamples)
        #expect(outcome.tokenUsage == .unknown)
    }

    @Test("未调用累加器与已调用但用量未知不相等")
    func distinguishesUntouchedAccumulatorFromUnknownUsage() {
        #expect(AITokenUsage.accumulator != .unknown)
    }

    @Test("第二次 AI 调用失败时不保留第一次的部分 Token")
    func discardsPartialTokenUsageWhenSecondCallFails() async {
        let client = ValidationFailureThenRequestFailureClient()
        let service = AIEnrichmentService(
            client: client,
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )

        let outcome = await service.enrich(
            draft: BookDraft(title: "示例图书", author: "示例作者"),
            targets: [.aiIntroduction]
        )

        #expect(outcome.tokenUsage == .unknown)
        #expect(await client.requestCount == 2)
    }

    @Test("AI简介第一次验证失败后携带原因重试一次")
    func retriesIntroductionOnceWithValidationFeedback() async {
        let client = SequencedAICompletionClient(responses: [
            AICompletionResponse(content: #"{"status":"ok"}"#, usage: AITokenUsage(input: 10, output: 5, total: 15)),
            AICompletionResponse(content: validIntroductionJSON(), usage: AITokenUsage(input: 20, output: 30, total: 50))
        ])
        let service = AIEnrichmentService(
            client: client,
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )
        let draft = BookDraft(title: "示例图书", author: "示例作者")

        let outcome = await service.enrich(draft: draft, targets: [.aiIntroduction])

        #expect(outcome.draft.aiIntroduction != nil)
        #expect(outcome.rejections[.aiIntroduction] == nil)
        #expect(outcome.tokenUsage == AITokenUsage(input: 30, output: 35, total: 65))
        #expect(await client.requests.count == 2)
        #expect(await client.requests[1].messages.last?.content.contains("上一次未通过验证") == true)
    }

    @Test("事实检索认证失败后不再请求 AI简介")
    func stopsAfterFatalFactLookupFailure() async {
        let client = FailingAICompletionClient(error: AIClientError.unauthorized)
        let service = AIEnrichmentService(
            client: client,
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )
        let draft = BookDraft(title: "示例图书", author: "示例作者")

        let outcome = await service.enrich(
            draft: draft,
            targets: [.publisher, .aiIntroduction]
        )

        #expect(outcome.status == .fatalFailure("API Key 或权限无效"))
        #expect(outcome.draft == draft)
        #expect(await client.requestCount == 1)
    }

    @Test("事实字段全部被证据闸门拒绝时返回验证拒绝")
    func reportsValidationRejectionWhenNoFactCanBeAccepted() async {
        let response = #"{"status":"ok","identity":{"matched_title":"示例图书","matched_author":"示例作者"},"fields":{"publisher":{"value":"候选出版社","sources":[]}}}"#
        let client = SequencedAICompletionClient(responses: [
            AICompletionResponse(content: response, usage: .unknown)
        ])
        let service = AIEnrichmentService(
            client: client,
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )
        let draft = BookDraft(title: "示例图书", author: "示例作者")

        let outcome = await service.enrich(draft: draft, targets: [.publisher])

        guard case .validationRejected = outcome.status else {
            Issue.record("全部字段被拒绝时应返回验证拒绝，实际为 \(outcome.status)")
            return
        }
        #expect(outcome.rejections[.publisher] == "缺少有效来源")
    }

    @Test("AI 没有查到译者时保持为空且不显示字段错误")
    func ignoresBlankTranslatorWithoutRejectingIt() async {
        let response = #"{"status":"ok","identity":{"matched_title":"示例图书","matched_author":"示例作者"},"fields":{"translator":{"value":"","sources":["https://book.douban.com/subject/1234567/"]}}}"#
        let client = SequencedAICompletionClient(responses: [
            AICompletionResponse(content: response, usage: .unknown)
        ])
        let service = AIEnrichmentService(
            client: client,
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )

        let outcome = await service.enrich(
            draft: BookDraft(title: "示例图书", author: "示例作者"),
            targets: [.translator]
        )

        #expect(outcome.draft.translator == nil)
        #expect(outcome.rejections[.translator] == nil)
        #expect(outcome.status == .notFound)
    }

    @Test("客户端重试后仍限流会返回批量应立即中止的失败")
    func classifiesFinalRateLimitAsBatchStoppingFailure() async {
        let client = FailingAICompletionClient(error: AIClientError.rateLimited(retryAfter: 1))
        let service = AIEnrichmentService(
            client: client,
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )

        let outcome = await service.enrich(
            draft: BookDraft(title: "示例图书", author: "示例作者"),
            targets: [.aiIntroduction]
        )

        #expect(outcome.status == .fatalFailure("请求过于频繁，请稍后重试"))
        #expect(await client.requestCount == 1)
    }

    @Test("DNS 暂时解析失败保留重试机会")
    func classifiesDNSResolutionFailureAsRetryable() async {
        let client = FailingAICompletionClient(error: AIEndpointPolicyError.dnsResolutionFailed)
        let service = AIEnrichmentService(
            client: client,
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )

        let outcome = await service.enrich(
            draft: BookDraft(title: "示例图书", author: "示例作者"),
            targets: [.aiIntroduction]
        )

        #expect(outcome.status == .retryableFailure("无法解析接口地址的主机名"))
        #expect(await client.requestCount == 1)
    }

    @Test("单本多次 AI 调用的 Token 累计溢出时饱和")
    func saturatesTokenUsageOverflow() async {
        let client = SequencedAICompletionClient(responses: [
            AICompletionResponse(
                content: #"{"status":"ok"}"#,
                usage: AITokenUsage(input: Int.max, output: Int.max, total: Int.max)
            ),
            AICompletionResponse(
                content: validIntroductionJSON(),
                usage: AITokenUsage(input: 1, output: 1, total: 1)
            )
        ])
        let service = AIEnrichmentService(
            client: client,
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )

        let outcome = await service.enrich(
            draft: BookDraft(title: "示例图书", author: "示例作者"),
            targets: [.aiIntroduction]
        )

        #expect(outcome.tokenUsage == AITokenUsage(input: Int.max, output: Int.max, total: Int.max))
    }

    private func validIntroductionJSON() -> String {
        let headings = ["《示例图书》的创作坐标", "核心主题与叙事笔法", "阅读节奏及思想回响", "同类作品比较与延伸阅读"]
        let prefixes = [
            "《示例图书》由示例作者创作，置于特定时代背景，采用小说体裁，聚焦核心内容并确立作品定位。",
            "作品围绕主题展开，以鲜明特点塑造人物，并通过叙事结构、语言风格和多重视角形成具体写法。",
            "阅读节奏张弛有度，读者会形成情绪感受与认知体验，并理解作品的现实意义和思想启发。",
            "这本书值得推荐，读后思考可与《真实对比书》作主题比较，并据此安排延伸阅读与相关阅读。"
        ]
        let fillers = [
            "作品从社会环境与个人选择的交叉处展开，叙述先交代时代条件，再说明主人公所处的位置；章节之间逐步补充事件因果，使核心内容、体裁特征和创作意图能够彼此印证，也让这部作品在同类写作中的定位更加清楚。",
            "作者没有把主题停留在结论层面，而是借人物关系、关键场景和视角变化逐层推进；叙事结构在快慢转换中形成张力，语言既保留细节也控制议论，因此人物选择与作品特点能够通过具体写法被读者辨认。",
            "阅读过程先要求耐心进入人物处境，随后因节奏变化产生紧张、迟疑与共鸣；这些感受不仅来自情节，也来自观点被重新排列的认知体验，最终把个人选择连接到现实问题，并留下可以继续思考的意义。",
            "如果读者关注相近主题，可以把本书与《真实对比书》并置：前者着重人物处境，后者从另一种结构展开，两者差异能形成明确的比较理由；这样的读后思考既说明推荐对象，也为后续延伸阅读提供方向。"
        ]
        let contentCount = 900 - headings.reduce(0) { $0 + $1.count }
        let base = contentCount / 4
        let sections = headings.enumerated().map { index, heading in
            let targetCount = base + (index < contentCount % 4 ? 1 : 0)
            let remaining = targetCount - prefixes[index].count
            let padding = String(
                String(repeating: fillers[index], count: remaining / fillers[index].count + 1)
                    .prefix(remaining)
            )
            return [
                "kind": ["overview", "analysis", "experience", "recommendations"][index],
                "heading": heading,
                "content": prefixes[index] + padding
            ]
        }
        let object: [String: Any] = [
            "status": "ok",
            "identity": [
                "matched_title": "示例图书",
                "matched_author": "示例作者",
                "matched_isbn": ""
            ],
            "sections": sections,
            "sources": ["https://research.example/books/1"],
            "comparison_books": [[
                "title": "真实对比书",
                "reason": "两本书都讨论个体选择与时代环境的关系",
                "sources": ["https://research.example/books/2"]
            ]]
        ]
        return String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }
}

private actor FailingAICompletionClient: AICompletionClient {
    private let error: Error
    private(set) var requestCount = 0

    init(error: Error) {
        self.error = error
    }

    func listModels(config: AIConfig) async throws -> [AIModelOption] { [] }

    func complete(request: AICompletionRequest, config: AIConfig) async throws -> AICompletionResponse {
        requestCount += 1
        throw error
    }
}

private actor SequencedAICompletionClient: AICompletionClient {
    private var responses: [AICompletionResponse]
    private(set) var requests: [AICompletionRequest] = []

    init(responses: [AICompletionResponse]) {
        self.responses = responses
    }

    func listModels(config: AIConfig) async throws -> [AIModelOption] { [] }

    func complete(request: AICompletionRequest, config: AIConfig) async throws -> AICompletionResponse {
        requests.append(request)
        return responses.removeFirst()
    }
}

private actor ValidationFailureThenRequestFailureClient: AICompletionClient {
    private(set) var requestCount = 0

    func listModels(config: AIConfig) async throws -> [AIModelOption] { [] }

    func complete(request: AICompletionRequest, config: AIConfig) async throws -> AICompletionResponse {
        requestCount += 1
        if requestCount == 1 {
            return AICompletionResponse(
                content: #"{"status":"ok"}"#,
                usage: AITokenUsage(input: 10, output: 5, total: 15)
            )
        }
        throw AIClientError.server(statusCode: 503)
    }
}

private actor DelayedAICompletionClient: AICompletionClient {
    private let delay: Duration
    private let response: AICompletionResponse
    private(set) var wasCancelled = false

    init(delay: Duration, response: AICompletionResponse) {
        self.delay = delay
        self.response = response
    }

    func listModels(config: AIConfig) async throws -> [AIModelOption] { [] }

    func complete(request: AICompletionRequest, config: AIConfig) async throws -> AICompletionResponse {
        do {
            try await Task.sleep(for: delay)
            return response
        } catch is CancellationError {
            wasCancelled = true
            throw CancellationError()
        }
    }
}

private actor NonCooperativeDelayedAICompletionClient: AICompletionClient {
    private let delay: Duration
    private let response: AICompletionResponse

    init(delay: Duration, response: AICompletionResponse) {
        self.delay = delay
        self.response = response
    }

    func listModels(config: AIConfig) async throws -> [AIModelOption] { [] }

    func complete(request: AICompletionRequest, config: AIConfig) async throws -> AICompletionResponse {
        let delay = delay
        let response = response
        let nonCooperativeWork = Task.detached {
            try? await Task.sleep(for: delay)
        }
        await nonCooperativeWork.value
        return response
    }
}

private actor FactThenDelayedIntroductionClient: AICompletionClient {
    private let factResponse: String
    private(set) var requestCount = 0

    init(factResponse: String) {
        self.factResponse = factResponse
    }

    func listModels(config: AIConfig) async throws -> [AIModelOption] { [] }

    func complete(request: AICompletionRequest, config: AIConfig) async throws -> AICompletionResponse {
        requestCount += 1
        if requestCount == 1 {
            return AICompletionResponse(content: factResponse, usage: .unknown)
        }
        try await Task.sleep(for: .milliseconds(250))
        return AICompletionResponse(content: "{}", usage: .unknown)
    }
}

private actor SlowInvalidFactThenValidClient: AICompletionClient {
    private let firstDelay: Duration
    private(set) var requests: [AICompletionRequest] = []

    init(firstDelay: Duration) {
        self.firstDelay = firstDelay
    }

    func listModels(config: AIConfig) async throws -> [AIModelOption] { [] }

    func complete(request: AICompletionRequest, config: AIConfig) async throws -> AICompletionResponse {
        requests.append(request)
        if requests.count == 1 {
            try await Task.sleep(for: firstDelay)
            return AICompletionResponse(content: #"{"status":"ok""#, usage: .unknown)
        }
        return AICompletionResponse(
            content: #"{"status":"ok","identity":{"matched_title":"示例图书","matched_author":"示例作者"},"fields":{"publisher":{"value":"示例出版社","sources":["https://research.example/books/1"]}}}"#,
            usage: .unknown
        )
    }
}
