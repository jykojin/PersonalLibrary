import Foundation

struct AIModelOption: Equatable, Identifiable, Sendable {
    let id: String
}

struct AIChatMessage: Equatable, Sendable {
    let role: String
    let content: String
}

struct AICompletionRequest: Equatable, Sendable {
    let messages: [AIChatMessage]
    var requiresJSON: Bool = true
    var temperature: Double = 0.1
    var maximumOutputTokens: Int?
    var maximumCompletionTokens: Int?
    var enableThinking: Bool?
    var thinkingBudget: Int?
    var timeoutInterval: TimeInterval?
    var requiresSearchReferences: Bool = false
}

struct AITokenUsage: Equatable, Sendable {
    var input: Int?
    var output: Int?
    var total: Int?
    private(set) var hasSamples: Bool

    static let unknown = AITokenUsage(input: nil, output: nil, total: nil)
    static let accumulator = AITokenUsage(
        input: nil,
        output: nil,
        total: nil,
        hasSamples: false
    )

    init(input: Int?, output: Int?, total: Int?) {
        self.init(input: input, output: output, total: total, hasSamples: true)
    }

    private init(input: Int?, output: Int?, total: Int?, hasSamples: Bool) {
        self.input = input
        self.output = output
        self.total = total
        self.hasSamples = hasSamples
    }

    mutating func add(_ other: AITokenUsage) {
        guard hasSamples else {
            self = other
            return
        }
        input = Self.sum(input, other.input)
        output = Self.sum(output, other.output)
        total = Self.sum(total, other.total)
    }

    private static func sum(_ lhs: Int?, _ rhs: Int?) -> Int? {
        let lhs = lhs.flatMap { $0 >= 0 ? $0 : nil }
        let rhs = rhs.flatMap { $0 >= 0 ? $0 : nil }
        guard let lhs, let rhs else { return nil }
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }

    static func == (lhs: AITokenUsage, rhs: AITokenUsage) -> Bool {
        lhs.input == rhs.input
            && lhs.output == rhs.output
            && lhs.total == rhs.total
            && lhs.hasSamples == rhs.hasSamples
    }
}

enum AICompletionFinishReason: Equatable, Sendable {
    case stop
    case length
    case other(String)
    case unspecified

    init(rawValue: String?) {
        switch rawValue {
        case "stop": self = .stop
        case "length": self = .length
        case .some(let value): self = .other(value)
        case nil: self = .unspecified
        }
    }
}

struct AICompletionResponse: Equatable, Sendable {
    let content: String
    let usage: AITokenUsage
    let finishReason: AICompletionFinishReason
    let searchReferences: [String: String]?

    init(
        content: String,
        usage: AITokenUsage,
        finishReason: AICompletionFinishReason = .unspecified,
        searchReferences: [String: String]? = nil
    ) {
        self.content = content
        self.usage = usage
        self.finishReason = finishReason
        self.searchReferences = searchReferences
    }

    var reachedOutputLimit: Bool {
        finishReason == .length
    }
}

enum AIClientError: Error, Equatable, LocalizedError {
    case searchUnsupported
    case credentialDestinationMismatch
    case endpointUnavailable
    case modelUnavailable
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case server(statusCode: Int)
    case invalidResponse
    case requestTooLarge
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .searchUnsupported: return "当前配置不支持联网检索"
        case .credentialDestinationMismatch: return "API Key 不属于当前平台或接口地址，请重新输入"
        case .endpointUnavailable: return "AI 接口地址不可用"
        case .modelUnavailable: return "所选模型不存在或当前账号不可用"
        case .unauthorized: return "API Key 或权限无效"
        case .rateLimited: return "请求过于频繁，请稍后重试"
        case .server(let code): return "AI 服务错误（HTTP \(code)）"
        case .invalidResponse: return "AI 服务返回了无效数据"
        case .requestTooLarge: return "发送给 AI 的内容过长，请精简图书信息后重试"
        case .responseTooLarge: return "AI 服务响应过大"
        }
    }
}

protocol AICompletionClient: Sendable {
    func listModels(config: AIConfig) async throws -> [AIModelOption]
    func complete(request: AICompletionRequest, config: AIConfig) async throws -> AICompletionResponse
}

struct OpenAICompatibleAIClient: AICompletionClient, Sendable {
    private let httpClient: any HTTPDataClient
    private let completionTimeoutInterval: TimeInterval
    private let maximumRequestAttempts: Int
    private let maximumResponseBytes = 2_000_000

    init(
        httpClient: any HTTPDataClient = SecureAIHTTPDataClient(),
        completionTimeoutInterval: TimeInterval = 90,
        maximumRequestAttempts: Int = 2
    ) {
        self.httpClient = httpClient
        self.completionTimeoutInterval = completionTimeoutInterval
        self.maximumRequestAttempts = max(1, maximumRequestAttempts)
    }

    func listModels(config: AIConfig) async throws -> [AIModelOption] {
        guard config.apiKeyDestinationID == config.credentialDestinationID else {
            throw AIClientError.credentialDestinationMismatch
        }
        let url = try AIEndpointPolicy.appending("models", to: config.endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let data = try await send(request)
        struct ModelsResponse: Decodable { let data: [Model] }
        struct Model: Decodable { let id: String }
        guard let response = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
            throw AIClientError.invalidResponse
        }
        let recommendedModel = config.platform.recommendedModel
        return Set(response.data.map(\.id))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                if lhs == recommendedModel { return true }
                if rhs == recommendedModel { return false }
                return lhs < rhs
            }
            .map(AIModelOption.init(id:))
    }

    func complete(request completion: AICompletionRequest, config: AIConfig) async throws -> AICompletionResponse {
        guard config.searchStrategy != .none else { throw AIClientError.searchUnsupported }
        guard config.apiKeyDestinationID == config.credentialDestinationID else {
            throw AIClientError.credentialDestinationMismatch
        }
        guard !completion.requiresSearchReferences || config.supportsBailianSearchReferences else {
            throw AIClientError.searchUnsupported
        }
        let url = try AIEndpointPolicy.appending("chat/completions", to: config.endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = completion.timeoutInterval ?? completionTimeoutInterval
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var model = config.model
        var body: [String: Any] = [
            "model": model,
            "messages": completion.messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": completion.temperature
        ]
        if completion.requiresJSON {
            body["response_format"] = ["type": "json_object"]
        }
        if let maximumCompletionTokens = completion.maximumCompletionTokens {
            body["max_completion_tokens"] = maximumCompletionTokens
        } else if let maximumOutputTokens = completion.maximumOutputTokens {
            body["max_tokens"] = maximumOutputTokens
        }
        if config.platform == .bailian,
           let enableThinking = completion.enableThinking {
            body["enable_thinking"] = enableThinking
            if enableThinking, let thinkingBudget = completion.thinkingBudget {
                body["thinking_budget"] = thinkingBudget
            }
        }
        switch config.searchStrategy {
        case .enableSearch:
            body["enable_search"] = true
            if config.platform == .bailian {
                body["search_options"] = ["forced_search": true]
            }
        case .onlineSuffix:
            if !model.hasSuffix(":online") { model += ":online" }
            body["model"] = model
        case .openAIWebSearch:
            body["web_search_options"] = [String: Any]()
        case .none:
            break
        }
        if completion.requiresSearchReferences {
            var parameters = body
            parameters.removeValue(forKey: "model")
            parameters.removeValue(forKey: "messages")
            parameters["result_format"] = "message"
            parameters["search_options"] = [
                "forced_search": true, "enable_source": true,
                "enable_citation": true, "citation_format": "[ref_<number>]"
            ]
            body = [
                "model": model,
                "input": ["messages": completion.messages.map { ["role": $0.role, "content": $0.content] }],
                "parameters": parameters
            ]
            // The exact endpoint gate above prevents moving a custom/other-region credential.
            request.url = URL(string: "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation")!
        }
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        guard bodyData.count <= AITextBudget.maximumRequestBytes else {
            throw AIClientError.requestTooLarge
        }
        request.httpBody = bodyData

        let data = try await send(request)
        struct CompletionEnvelope: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String?
                }
                let message: Message
                let finishReason: String?

                enum CodingKeys: String, CodingKey {
                    case message
                    case finishReason = "finish_reason"
                }
            }
            struct Usage: Decodable {
                let promptTokens: Int?
                let completionTokens: Int?
                let totalTokens: Int?
                let inputTokens: Int?
                let outputTokens: Int?

                enum CodingKeys: String, CodingKey {
                    case promptTokens = "prompt_tokens"
                    case completionTokens = "completion_tokens"
                    case totalTokens = "total_tokens"
                    case inputTokens = "input_tokens"
                    case outputTokens = "output_tokens"
                }
            }
            struct NativeOutput: Decodable {
                struct SearchInfo: Decodable {
                    struct Result: Decodable {
                        let index: Int
                        let url: String
                    }
                    let searchResults: [Result]?
                    enum CodingKeys: String, CodingKey { case searchResults = "search_results" }
                }
                let choices: [Choice]
                let searchInfo: SearchInfo?
                enum CodingKeys: String, CodingKey {
                    case choices
                    case searchInfo = "search_info"
                }
            }
            let choices: [Choice]?
            let output: NativeOutput?
            let usage: Usage?
        }
        guard let response = try? JSONDecoder().decode(CompletionEnvelope.self, from: data),
              let choice = (completion.requiresSearchReferences ? response.output?.choices : response.choices)?.first else {
            throw AIClientError.invalidResponse
        }
        var searchReferences: [String: String]?
        if completion.requiresSearchReferences {
            var references: [String: String] = [:]
            for source in response.output?.searchInfo?.searchResults ?? [] {
                let key = "[ref_\(source.index)]"
                guard source.index > 0, references[key] == nil else {
                    throw AIClientError.invalidResponse
                }
                references[key] = source.url
            }
            searchReferences = references
        }
        let finishReason = AICompletionFinishReason(rawValue: choice.finishReason)
        let content = choice.message.content ?? ""
        guard !content.isEmpty || finishReason == .length else {
            throw AIClientError.invalidResponse
        }
        return AICompletionResponse(
            content: content,
            usage: AITokenUsage(
                input: completion.requiresSearchReferences ? response.usage?.inputTokens : response.usage?.promptTokens,
                output: completion.requiresSearchReferences ? response.usage?.outputTokens : response.usage?.completionTokens,
                total: response.usage?.totalTokens
            ),
            finishReason: finishReason,
            searchReferences: searchReferences
        )
    }

    private func send(_ request: URLRequest) async throws -> Data {
        for attempt in 0..<maximumRequestAttempts {
            let dataAndResponse: (Data, URLResponse)
            do {
                dataAndResponse = try await httpClient.data(for: request)
            } catch HTTPDataClientError.responseTooLarge {
                throw AIClientError.responseTooLarge
            } catch let error as URLError where error.code == .networkConnectionLost {
                guard attempt + 1 < maximumRequestAttempts else { throw error }
                try Task.checkCancellation()
                continue
            }
            let (data, response) = dataAndResponse
            guard data.count <= maximumResponseBytes else { throw AIClientError.responseTooLarge }
            guard let response = response as? HTTPURLResponse else { throw AIClientError.invalidResponse }
            if let originalURL = request.url, let finalURL = response.url,
               !AIEndpointPolicy.allowsRedirect(from: originalURL, to: finalURL) {
                throw AIEndpointPolicyError.privateOrReservedHost
            }
            switch response.statusCode {
            case 200..<300:
                return data
            case 401, 403:
                throw AIClientError.unauthorized
            case 429:
                let delay = AIRetryDelayPolicy.parse(
                    response.value(forHTTPHeaderField: "Retry-After")
                )
                if attempt + 1 < maximumRequestAttempts {
                    try await Task.sleep(for: .seconds(AIRetryDelayPolicy.bounded(delay)))
                    continue
                }
                throw AIClientError.rateLimited(retryAfter: delay)
            case 500...599:
                throw AIClientError.server(statusCode: response.statusCode)
            case 400, 422:
                if Self.isModelUnavailableResponse(data) {
                    throw AIClientError.modelUnavailable
                }
                throw AIClientError.invalidResponse
            case 404:
                if Self.isModelUnavailableResponse(data) {
                    throw AIClientError.modelUnavailable
                }
                throw AIClientError.endpointUnavailable
            default:
                throw AIClientError.invalidResponse
            }
        }
        throw AIClientError.invalidResponse
    }

    private static func isModelUnavailableResponse(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        let nestedError = object["error"] as? [String: Any]
        let code = (nestedError?["code"] as? String) ?? (object["code"] as? String) ?? ""
        let message = (nestedError?["message"] as? String)
            ?? (object["message"] as? String)
            ?? ""
        let normalizedCode = code.lowercased()
            .replacingOccurrences(of: "-", with: "_")
        let normalizedMessage = message.lowercased()
        let knownCodes = [
            "model_not_found", "model_not_exist", "invalid_model",
            "unsupported_model", "model_not_available"
        ]
        if knownCodes.contains(where: normalizedCode.contains) {
            return true
        }
        let unavailableTerms = [
            "not found", "does not exist", "not exist", "not available",
            "not support", "unsupported", "invalid", "不存在", "不可用", "不支持"
        ]
        return (normalizedMessage.contains("model") || normalizedMessage.contains("模型"))
            && unavailableTerms.contains(where: normalizedMessage.contains)
    }
}

enum AIConnectionTestError: Error, Equatable, LocalizedError {
    case timedOut
    case saveFailed
    case configurationChanged

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "连接测试超时，请检查网络或更换响应更快的模型"
        case .saveFailed:
            return "联网验证已通过，但保存设置失败，请检查 Keychain 权限"
        case .configurationChanged:
            return "连接测试期间配置已变更，旧测试结果未保存，请重新测试"
        }
    }
}

/// 将“验证联网能力”与“保存已验证配置”合并为一个用例，
/// 避免用户测试成功后因未再点一次保存而无法使用 AI 补全。
struct AIConnectionTestService {
    typealias Probe = @Sendable (AIConfig) async throws -> Void
    typealias RetrySleep = @Sendable (TimeInterval) async throws -> Void

    private let store: AIConfigStore
    private let probe: Probe
    private let retrySleep: RetrySleep
    private let maximumAttempts: Int
    private let attemptTimeout: Duration

    init(store: AIConfigStore = .shared, completionTimeoutInterval: TimeInterval = 12) {
        self.store = store
        self.maximumAttempts = 2
        self.attemptTimeout = .seconds(completionTimeoutInterval)
        self.retrySleep = { delay in
            try await Task.sleep(for: .seconds(delay))
        }
        self.probe = { config in
            let client = OpenAICompatibleAIClient(
                completionTimeoutInterval: completionTimeoutInterval,
                maximumRequestAttempts: 1
            )
            if AISearchCapabilityProbe.usesBailianEvidence(for: config) {
                let response = try await client.complete(
                    request: AISearchCapabilityProbe.bailianRequest(),
                    config: config
                )
                _ = try AISearchCapabilityProbe.validateBailian(
                    response,
                    endpoint: config.endpoint
                )
            } else {
                let challenge = try await AISearchCapabilityProbe.fetchChallenge()
                let response = try await client.complete(
                    request: AISearchCapabilityProbe.request(for: challenge),
                    config: config
                )
                _ = try AISearchCapabilityProbe.validate(
                    response.content,
                    challenge: challenge,
                    endpoint: config.endpoint
                )
            }
        }
    }

    init(
        store: AIConfigStore,
        maximumAttempts: Int = 1,
        attemptTimeout: Duration = .seconds(12),
        retrySleep: @escaping RetrySleep = { delay in
            try await Task.sleep(for: .seconds(delay))
        },
        probe: @escaping Probe
    ) {
        self.store = store
        self.maximumAttempts = max(1, maximumAttempts)
        self.attemptTimeout = attemptTimeout
        self.retrySleep = retrySleep
        self.probe = probe
    }

    func testAndSave(
        _ config: AIConfig,
        expectedStoreRevision: Int
    ) async throws -> AIConfig {
        guard config.isConnectionTestable else { throw AIClientError.searchUnsupported }
        try await AIConnectionTestDeadline.run {
            for attempt in 1...maximumAttempts {
                do {
                    try await AIConnectionTestDeadline.run(timeout: attemptTimeout) {
                        try await probe(config)
                    }
                    return
                } catch {
                    guard attempt < maximumAttempts,
                          Self.shouldRetry(after: error) else {
                        if Self.isTimeout(error) {
                            throw AIConnectionTestError.timedOut
                        }
                        throw error
                    }
                    if case .rateLimited(let retryAfter) = error as? AIClientError {
                        try await retrySleep(AIRetryDelayPolicy.bounded(retryAfter))
                    }
                }
            }
        }
        try Task.checkCancellation()

        var verified = config
        verified.verifiedSearchConfigurationID = verified.searchConfigurationID
        switch store.save(
            verified,
            ifRevisionMatches: expectedStoreRevision
        ) {
        case .saved:
            break
        case .configurationChanged:
            throw AIConnectionTestError.configurationChanged
        case .failed:
            throw AIConnectionTestError.saveFailed
        }
        return verified
    }

    private static func shouldRetry(after error: Error) -> Bool {
        guard !(error is CancellationError) else { return false }
        if let urlError = error as? URLError {
            return [
                .timedOut,
                .cannotFindHost,
                .cannotConnectToHost,
                .dnsLookupFailed,
                .networkConnectionLost,
                .notConnectedToInternet
            ].contains(urlError.code)
        }
        if isTimeout(error) { return true }
        if error is AISearchCapabilityProbeError { return true }
        if let clientError = error as? AIClientError {
            switch clientError {
            case .rateLimited, .server:
                return true
            default:
                return false
            }
        }
        return false
    }

    private static func isTimeout(_ error: Error) -> Bool {
        (error as? URLError)?.code == .timedOut
            || (error as? AIConnectionTestError) == .timedOut
    }
}

enum AIConnectionTestDeadline {
    static func run(
        timeout: Duration = .seconds(30),
        operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await AsyncHardDeadline.run(
            timeout: timeout,
            timeoutError: AIConnectionTestError.timedOut,
            operation: operation
        )
    }
}

enum AsyncHardDeadline {
    static func run<Value: Sendable, TimeoutError: Error & Sendable>(
        timeout: Duration,
        timeoutError: TimeoutError,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let race = AsyncHardDeadlineRace<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.install(continuation)
                let operationTask = Task {
                    do {
                        race.resolve(.success(try await operation()))
                    } catch {
                        race.resolve(.failure(error))
                    }
                }
                let timeoutTask = Task {
                    do {
                        try await Task.sleep(for: timeout)
                        race.resolve(.failure(timeoutError))
                    } catch {
                        // The operation completed first, so cancellation is expected.
                    }
                }
                race.storeTasks([operationTask, timeoutTask])
            }
        } onCancel: {
            race.resolve(.failure(CancellationError()))
        }
    }
}

private final class AsyncHardDeadlineRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var isResolved = false
    private var continuation: CheckedContinuation<Value, Error>?
    private var pendingResult: Result<Value, Error>?
    private var tasks: [Task<Void, Never>] = []

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        let pending: Result<Value, Error>? = lock.withLock {
            if let pendingResult {
                self.pendingResult = nil
                return pendingResult
            }
            self.continuation = continuation
            return nil
        }
        if let pending {
            continuation.resume(with: pending)
        }
    }

    func storeTasks(_ tasks: [Task<Void, Never>]) {
        let shouldCancel = lock.withLock {
            if isResolved { return true }
            self.tasks = tasks
            return false
        }
        if shouldCancel {
            tasks.forEach { $0.cancel() }
        }
    }

    func resolve(_ result: Result<Value, Error>) {
        let resolved = lock.withLock {
            guard !isResolved else {
                return nil as (CheckedContinuation<Value, Error>?, [Task<Void, Never>])?
            }
            isResolved = true
            let continuation = continuation
            self.continuation = nil
            if continuation == nil {
                pendingResult = result
            }
            let tasks = tasks
            self.tasks = []
            return (continuation, tasks)
        }
        guard let (continuation, tasks) = resolved else { return }
        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}

private enum AIRetryDelayPolicy {
    private static let fallback: TimeInterval = 1
    private static let maximum: TimeInterval = 10

    static func parse(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        guard let parsed = TimeInterval(value), parsed.isFinite else { return fallback }
        return bounded(parsed)
    }

    static func bounded(_ value: TimeInterval?) -> TimeInterval {
        guard let value, value.isFinite else { return fallback }
        return min(max(value, 0), maximum)
    }
}

struct AISearchCapabilityChallenge: Equatable, Sendable {
    let round: Int
    let randomness: String
}

enum AISearchCapabilityProbeError: Error, LocalizedError {
    case challengeUnavailable
    case invalidEvidence

    var errorDescription: String? {
        switch self {
        case .challengeUnavailable: return "无法取得联网验证随机信标"
        case .invalidEvidence: return "模型未返回可验证的联网检索证据"
        }
    }
}

enum AISearchCapabilityProbe {
    private static let beaconBaseURL = URL(string: "https://api.drand.sh/public")!
    private static let minimumBailianSearchInputTokens = 200

    static func usesBailianEvidence(for config: AIConfig) -> Bool {
        guard config.platform == .bailian else { return false }
        let endpoint = config.endpoint
        let expected = AIPlatformPreset.bailian.defaultEndpoint
        return endpoint.scheme?.lowercased() == expected.scheme?.lowercased()
            && endpoint.host?.lowercased() == expected.host?.lowercased()
            && (endpoint.port ?? 443) == (expected.port ?? 443)
            && normalizedPath(endpoint) == normalizedPath(expected)
            && endpoint.query == nil
    }

    static func bailianRequest() -> AICompletionRequest {
        AICompletionRequest(
            messages: [AIChatMessage(
                role: "user",
                content: """
                请实际联网搜索关键词“International ISBN Agency ISBN”。
                只需使用搜索结果中的 URL，不要尝试打开网页正文。
                只返回一个 JSON object：
                {"status":"ok","sources":["至少一个本次搜索结果中的外部 http/https URL"]}
                status 必须精确为 "ok"，sources 必须是 URL 字符串数组。不得仅凭记忆，不得编造来源。
                """
            )],
            requiresJSON: true,
            temperature: 0,
            maximumOutputTokens: 256,
            enableThinking: false
        )
    }

    static func validateBailian(
        _ response: AICompletionResponse,
        endpoint: URL
    ) throws -> [URL] {
        guard let inputTokens = response.usage.input,
              inputTokens >= minimumBailianSearchInputTokens,
              let data = jsonData(from: response.content),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["status"] as? String == "ok",
              let sourceStrings = object["sources"] as? [String],
              let sources = AIResearchSourceValidator.validate(sourceStrings, endpoint: endpoint) else {
            throw AISearchCapabilityProbeError.invalidEvidence
        }
        return sources
    }

    static func fetchChallenge(
        httpClient: any HTTPDataClient = SecureAIHTTPDataClient()
    ) async throws -> AISearchCapabilityChallenge {
        let url = beaconBaseURL.appendingPathComponent("latest")
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await httpClient.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw AISearchCapabilityProbeError.challengeUnavailable
        }
        struct BeaconResponse: Decodable {
            let round: Int
            let randomness: String
        }
        guard let beacon = try? JSONDecoder().decode(BeaconResponse.self, from: data),
              beacon.round > 0,
              beacon.randomness.range(of: #"^[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil else {
            throw AISearchCapabilityProbeError.challengeUnavailable
        }
        return AISearchCapabilityChallenge(round: beacon.round, randomness: beacon.randomness.lowercased())
    }

    static func request(for challenge: AISearchCapabilityChallenge) -> AICompletionRequest {
        AICompletionRequest(
            messages: [AIChatMessage(
                role: "user",
                content: """
                请实际联网访问 https://api.drand.sh/public/\(challenge.round)，读取该轮 drand 随机信标，并只返回 JSON：
                {"status":"ok","round":\(challenge.round),"randomness":"页面中的 randomness 原值","sources":["实际访问的 URL"]}
                不得仅凭记忆，不得编造随机值或来源。
                """
            )],
            requiresJSON: true,
            temperature: 0
        )
    }

    static func validate(
        _ content: String,
        challenge: AISearchCapabilityChallenge,
        endpoint: URL
    ) throws -> [URL] {
        guard let data = jsonData(from: content),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["status"] as? String == "ok",
              object["round"] as? Int == challenge.round,
              let randomness = object["randomness"] as? String,
              randomness.lowercased() == challenge.randomness,
              let sourceStrings = object["sources"] as? [String],
              let sources = AIResearchSourceValidator.validate(sourceStrings, endpoint: endpoint),
              sources.contains(where: {
                  $0.scheme?.lowercased() == "https"
                      && $0.host?.lowercased() == "api.drand.sh"
                      && $0.path == "/public/\(challenge.round)"
              }) else {
            throw AISearchCapabilityProbeError.invalidEvidence
        }
        return sources
    }

    private static func jsonData(from content: String) -> Data? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = trimmed.components(separatedBy: .newlines)
        if lines.count >= 3,
           ["```", "```json"].contains(lines[0].lowercased()),
           lines[lines.count - 1] == "```" {
            lines.removeFirst()
            lines.removeLast()
            return lines.joined(separator: "\n").data(using: .utf8)
        }
        return trimmed.data(using: .utf8)
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
