import Foundation
import Network
import Testing
@testable import PersonalLibrary

@Suite("AI Completion Client Tests")
struct AICompletionClientTests {
    @Test("读取模型列表时去重并优先展示平台推荐模型")
    func listsModels() async throws {
        let data = #"{"data":[{"id":"qwen-plus"},{"id":"qwen-max"},{"id":"qwen-plus"}]}"#.data(using: .utf8)!
        let http = StubHTTPDataClient(data: data, statusCode: 200)
        let client = OpenAICompatibleAIClient(httpClient: http)
        let config = AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")

        let models = try await client.listModels(config: config)

        #expect(models.map(\.id) == ["qwen-plus", "qwen-max"])
        #expect(await http.lastRequest?.url?.absoluteString
                == "https://dashscope.aliyuncs.com/compatible-mode/v1/models")
        #expect(await http.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    }

    @Test("429 按 Retry-After 仅重试一次并解码 token")
    func retriesRateLimitOnce() async throws {
        let success = #"{"choices":[{"message":{"content":"{\"status\":\"ok\"}"}}],"usage":{"prompt_tokens":12,"completion_tokens":8,"total_tokens":20}}"#.data(using: .utf8)!
        let http = SequenceHTTPDataClient(responses: [
            (Data(), 429, ["Retry-After": "0"]),
            (success, 200, [:])
        ])
        let client = OpenAICompatibleAIClient(httpClient: http)

        let response = try await client.complete(
            request: AICompletionRequest(messages: [AIChatMessage(role: "user", content: "test")]),
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )

        #expect(response.usage == AITokenUsage(input: 12, output: 8, total: 20))
        #expect(await http.requestCount == 2)
    }

    @Test("瞬时网络连接中断时重试一次")
    func retriesNetworkConnectionLostOnce() async throws {
        let success = #"{"choices":[{"message":{"content":"{\"status\":\"ok\"}"},"finish_reason":"stop"}]}"#.data(using: .utf8)!
        let http = ConnectionLostThenSuccessHTTPDataClient(success: success)
        let client = OpenAICompatibleAIClient(httpClient: http)

        let response = try await client.complete(
            request: AICompletionRequest(messages: [AIChatMessage(role: "user", content: "test")]),
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )

        #expect(response.content == #"{"status":"ok"}"#)
        #expect(await http.requestCount == 2)
    }

    @Test("保留模型达到长度上限的结束原因")
    func decodesLengthFinishReason() async throws {
        let data = #"{"choices":[{"message":{"content":"{\"status\":\"ok\""},"finish_reason":"length"}],"usage":{"prompt_tokens":12,"completion_tokens":4096,"total_tokens":4108}}"#.data(using: .utf8)!
        let client = OpenAICompatibleAIClient(
            httpClient: StubHTTPDataClient(data: data, statusCode: 200)
        )

        let response = try await client.complete(
            request: AICompletionRequest(messages: [AIChatMessage(role: "user", content: "test")]),
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )

        #expect(response.finishReason == .length)
        #expect(response.reachedOutputLimit)
    }

    @Test("长度截断即使没有正文也保留结束原因供服务层扩容重试")
    func decodesLengthFinishReasonWithNullContent() async throws {
        let data = #"{"choices":[{"message":{"content":null},"finish_reason":"length"}],"usage":{"prompt_tokens":4096,"completion_tokens":4096,"total_tokens":8192}}"#.data(using: .utf8)!
        let client = OpenAICompatibleAIClient(
            httpClient: StubHTTPDataClient(data: data, statusCode: 200)
        )

        let response = try await client.complete(
            request: AICompletionRequest(messages: [AIChatMessage(role: "user", content: "test")]),
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )

        #expect(response.content.isEmpty)
        #expect(response.finishReason == .length)
        #expect(response.reachedOutputLimit)
    }

    @Test("非有限 Retry-After 使用安全默认值", arguments: ["NaN", "Infinity"])
    func nonFiniteRetryAfterUsesSafeDefault(header: String) async {
        let http = SequenceHTTPDataClient(responses: [
            (Data(), 429, ["Retry-After": header])
        ])
        let client = OpenAICompatibleAIClient(
            httpClient: http,
            maximumRequestAttempts: 1
        )

        await #expect(throws: AIClientError.rateLimited(retryAfter: 1)) {
            _ = try await client.complete(
                request: AICompletionRequest(messages: []),
                config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
            )
        }
    }

    @Test("不同平台只发送各自的联网检索参数")
    func encodesSearchStrategyWithoutCrossPlatformParameters() async throws {
        let success = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
        let cases: [(AIPlatformPreset, String, AISearchStrategy)] = [
            (.bailian, "qwen-plus", .enableSearch),
            (.openRouter, "openai/gpt-5-mini", .onlineSuffix),
            (.openAI, "gpt-5-search-api", .openAIWebSearch)
        ]

        for (preset, model, strategy) in cases {
            let http = StubHTTPDataClient(data: success, statusCode: 200)
            let client = OpenAICompatibleAIClient(httpClient: http)
            let config = AIConfig(
                platform: preset,
                endpoint: preset.defaultEndpoint,
                apiKey: "test-key",
                model: model,
                searchStrategy: strategy
            )

            _ = try await client.complete(
                request: AICompletionRequest(
                    messages: [AIChatMessage(role: "user", content: "test")]
                ),
                config: config
            )

            let request = try #require(await http.lastRequest)
            let bodyData = try #require(request.httpBody)
            let body = try #require(
                JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            )
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

            switch strategy {
            case .enableSearch:
                #expect(body["enable_search"] as? Bool == true)
                let searchOptions = try #require(body["search_options"] as? [String: Any])
                #expect(searchOptions["forced_search"] as? Bool == true)
                #expect(body["web_search_options"] == nil)
                #expect(body["model"] as? String == model)
            case .onlineSuffix:
                #expect(body["enable_search"] == nil)
                #expect(body["web_search_options"] == nil)
                #expect(body["model"] as? String == "\(model):online")
            case .openAIWebSearch:
                #expect(body["enable_search"] == nil)
                #expect(body["web_search_options"] is [String: Any])
                #expect(body["model"] as? String == model)
            case .none:
                Issue.record("测试用例不应包含不联网策略")
            }
        }
    }

    @Test("百炼强制联网参数不泄漏到自定义兼容接口")
    func bailianForcedSearchDoesNotAffectCustomEndpoints() async throws {
        let success = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
        let http = StubHTTPDataClient(data: success, statusCode: 200)
        let client = OpenAICompatibleAIClient(httpClient: http)
        let config = AIConfig(
            platform: .custom,
            endpoint: URL(string: "https://api.example.com/v1")!,
            apiKey: "test-key",
            model: "search-model",
            searchStrategy: .enableSearch
        )

        _ = try await client.complete(
            request: AICompletionRequest(messages: [AIChatMessage(role: "user", content: "test")]),
            config: config
        )

        let request = try #require(await http.lastRequest)
        let bodyData = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(body["enable_search"] as? Bool == true)
        #expect(body["search_options"] == nil)
    }

    @Test("百炼连接探针关闭深度思考并限制输出长度")
    func bailianProbeUsesFastGenerationOptions() async throws {
        let success = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
        let http = StubHTTPDataClient(data: success, statusCode: 200)
        let client = OpenAICompatibleAIClient(httpClient: http)

        _ = try await client.complete(
            request: AISearchCapabilityProbe.bailianRequest(),
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )

        let request = try #require(await http.lastRequest)
        let bodyData = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(body["enable_thinking"] as? Bool == false)
        #expect(body["max_tokens"] as? Int == 256)
    }

    @Test("百炼深度思考请求限制思维链并使用总输出预算")
    func bailianThinkingRequestUsesBoundedCompletionBudget() async throws {
        let success = #"{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}"#.data(using: .utf8)!
        let http = StubHTTPDataClient(data: success, statusCode: 200)
        let client = OpenAICompatibleAIClient(httpClient: http)

        _ = try await client.complete(
            request: AICompletionRequest(
                messages: [AIChatMessage(role: "user", content: "test")],
                maximumCompletionTokens: 12_288,
                enableThinking: true,
                thinkingBudget: 4_096
            ),
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )

        let request = try #require(await http.lastRequest)
        let bodyData = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(body["max_completion_tokens"] as? Int == 12_288)
        #expect(body["thinking_budget"] as? Int == 4_096)
        #expect(body["max_tokens"] == nil)
    }

    @Test("连接测试可使用独立的较短补全超时")
    func supportsShorterCompletionTimeoutForConnectionProbe() async throws {
        let success = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
        let http = StubHTTPDataClient(data: success, statusCode: 200)
        let client = OpenAICompatibleAIClient(
            httpClient: http,
            completionTimeoutInterval: 30
        )

        _ = try await client.complete(
            request: AICompletionRequest(messages: [AIChatMessage(role: "user", content: "test")]),
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )

        #expect(await http.lastRequest?.timeoutInterval == 30)
    }

    @Test("单次生成请求可覆盖客户端默认超时时间")
    func requestSpecificCompletionTimeoutOverridesDefault() async throws {
        let success = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
        let http = StubHTTPDataClient(data: success, statusCode: 200)
        let client = OpenAICompatibleAIClient(
            httpClient: http,
            completionTimeoutInterval: 90
        )

        _ = try await client.complete(
            request: AICompletionRequest(
                messages: [AIChatMessage(role: "user", content: "test")],
                timeoutInterval: 600
            ),
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )

        #expect(await http.lastRequest?.timeoutInterval == 600)
    }

    @Test("未启用联网策略时不发出请求")
    func rejectsUnsupportedSearchBeforeSending() async {
        let http = StubHTTPDataClient(data: Data(), statusCode: 200)
        let client = OpenAICompatibleAIClient(httpClient: http)
        let config = AIConfig(
            platform: .deepSeek,
            endpoint: AIPlatformPreset.deepSeek.defaultEndpoint,
            apiKey: "test-key",
            model: "deepseek-chat",
            searchStrategy: .none
        )

        await #expect(throws: AIClientError.searchUnsupported) {
            _ = try await client.complete(
                request: AICompletionRequest(messages: []),
                config: config
            )
        }
        #expect(await http.lastRequest == nil)
    }

    @Test("401 与 403 统一映射为认证失败", arguments: [401, 403])
    func mapsAuthenticationFailures(statusCode: Int) async {
        let http = StubHTTPDataClient(data: Data(), statusCode: statusCode)
        let client = OpenAICompatibleAIClient(httpClient: http)

        await #expect(throws: AIClientError.unauthorized) {
            _ = try await client.listModels(
                config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
            )
        }
    }

    @Test("模型不存在与 Endpoint 路径错误有独立错误语义")
    func distinguishesModelAndEndpointFailures() async {
        let config = AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        let missingModel = #"{"code":"InvalidParameter","message":"Model not exist."}"#
            .data(using: .utf8)!
        await #expect(throws: AIClientError.modelUnavailable) {
            _ = try await OpenAICompatibleAIClient(
                httpClient: StubHTTPDataClient(data: missingModel, statusCode: 400)
            ).complete(request: AICompletionRequest(messages: []), config: config)
        }

        let missingEndpoint = #"{"message":"Not Found"}"#.data(using: .utf8)!
        await #expect(throws: AIClientError.endpointUnavailable) {
            _ = try await OpenAICompatibleAIClient(
                httpClient: StubHTTPDataClient(data: missingEndpoint, statusCode: 404)
            ).complete(request: AICompletionRequest(messages: []), config: config)
        }
    }

    @Test("最终 429 保留 Retry-After 并只尝试两次")
    func finalRateLimitStopsAfterOneRetry() async {
        let http = SequenceHTTPDataClient(responses: [
            (Data(), 429, ["Retry-After": "0"]),
            (Data(), 429, ["Retry-After": "7"])
        ])
        let client = OpenAICompatibleAIClient(httpClient: http)

        await #expect(throws: AIClientError.rateLimited(retryAfter: 7)) {
            _ = try await client.complete(
                request: AICompletionRequest(messages: []),
                config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
            )
        }
        #expect(await http.requestCount == 2)
    }

    @Test("连接探针可关闭 HTTP 层重试以免和外层重试叠加")
    func requestRetryCanBeDisabled() async {
        let http = SequenceHTTPDataClient(responses: [
            (Data(), 429, ["Retry-After": "0"]),
            (Data(), 200, [:])
        ])
        let client = OpenAICompatibleAIClient(
            httpClient: http,
            maximumRequestAttempts: 1
        )

        await #expect(throws: AIClientError.rateLimited(retryAfter: 0)) {
            _ = try await client.complete(
                request: AICompletionRequest(messages: []),
                config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
            )
        }
        #expect(await http.requestCount == 1)
    }

    @Test("服务端错误、超大响应和缺失 usage 都有稳定语义")
    func handlesServerAndResponseBoundaries() async throws {
        let serverClient = OpenAICompatibleAIClient(
            httpClient: StubHTTPDataClient(data: Data(), statusCode: 503)
        )
        await #expect(throws: AIClientError.server(statusCode: 503)) {
            _ = try await serverClient.listModels(
                config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
            )
        }

        let oversizedClient = OpenAICompatibleAIClient(
            httpClient: StubHTTPDataClient(
                data: Data(repeating: 0, count: 2_000_001),
                statusCode: 200
            )
        )
        await #expect(throws: AIClientError.responseTooLarge) {
            _ = try await oversizedClient.listModels(
                config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
            )
        }

        let noUsage = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
        let response = try await OpenAICompatibleAIClient(
            httpClient: StubHTTPDataClient(data: noUsage, statusCode: 200)
        ).complete(
            request: AICompletionRequest(messages: []),
            config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        )
        #expect(response.usage == .unknown)
    }

    @Test("最终 AI HTTP 请求体超过字节预算时不发送")
    func rejectsOversizedRequestBodyBeforeSending() async {
        let success = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
        let http = StubHTTPDataClient(data: success, statusCode: 200)
        let client = OpenAICompatibleAIClient(httpClient: http)
        let oversizedPrompt = String(repeating: "请", count: 100_000)

        await #expect(throws: AIClientError.requestTooLarge) {
            _ = try await client.complete(
                request: AICompletionRequest(
                    messages: [AIChatMessage(role: "user", content: oversizedPrompt)]
                ),
                config: AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
            )
        }
        #expect(await http.lastRequest == nil)
    }

    @Test("超时、取消与无效 JSON 保持可区分语义")
    func propagatesTimeoutCancellationAndInvalidJSON() async {
        let config = AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")

        await #expect(throws: URLError.self) {
            _ = try await OpenAICompatibleAIClient(
                httpClient: ThrowingHTTPDataClient(failure: .timeout)
            ).listModels(config: config)
        }
        await #expect(throws: CancellationError.self) {
            _ = try await OpenAICompatibleAIClient(
                httpClient: ThrowingHTTPDataClient(failure: .cancelled)
            ).complete(request: AICompletionRequest(messages: []), config: config)
        }
        await #expect(throws: AIClientError.invalidResponse) {
            _ = try await OpenAICompatibleAIClient(
                httpClient: StubHTTPDataClient(data: Data("not-json".utf8), statusCode: 200)
            ).listModels(config: config)
        }
    }

    @Test("生产 AI HTTP 客户端在读取内存前拒绝超限下载")
    func secureHTTPClientRejectsOversizedDownload() async {
        let rawResponse = Data(
            "HTTP/1.1 200 OK\r\nContent-Length: 17\r\nConnection: close\r\n\r\n12345678901234567".utf8
        )
        let factory = RecordingAIPinnedConnectionFactory(response: rawResponse)
        let client = SecureAIHTTPDataClient(
            maximumResponseBytes: 16,
            hostResolver: PublicAIHostResolver(),
            transport: NetworkPinnedHTTPTransport(connectionFactory: factory)
        )

        await #expect(throws: HTTPDataClientError.responseTooLarge) {
            _ = try await client.data(for: URLRequest(url: URL(string: "https://example.com/test")!))
        }
    }

    @Test("固定地址传输解码分块响应并按解码后正文执行上限")
    func pinnedTransportDecodesChunkedResponseWithinLimit() async throws {
        let rawResponse = Data(
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n2\r\nok\r\n0\r\n\r\n".utf8
        )
        let factory = RecordingAIPinnedConnectionFactory(response: rawResponse)
        let client = SecureAIHTTPDataClient(
            maximumResponseBytes: 2,
            hostResolver: PublicAIHostResolver(),
            transport: NetworkPinnedHTTPTransport(connectionFactory: factory)
        )

        let (data, response) = try await client.data(for: URLRequest(
            url: URL(string: "https://example.com/v1/models")!
        ))

        #expect(data == Data("ok".utf8))
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test("固定地址传输接受合法的分块尾部字段")
    func pinnedTransportAcceptsChunkedTrailers() async throws {
        let rawResponse = Data(
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n2\r\nok\r\n0\r\nX-Trace: done\r\n\r\n".utf8
        )
        let factory = RecordingAIPinnedConnectionFactory(response: rawResponse)
        let transport = NetworkPinnedHTTPTransport(connectionFactory: factory)

        let (data, _) = try await transport.data(
            for: URLRequest(url: URL(string: "https://example.com/v1/models")!),
            connectingTo: "93.184.216.34",
            serverName: "example.com",
            port: 443,
            maximumResponseBytes: 2
        )

        #expect(data == Data("ok".utf8))
    }

    @Test("生产 AI HTTP 客户端只拨号到已校验的数值地址并保留原主机名")
    func secureHTTPClientPinsValidatedAddress() async throws {
        let transport = RecordingAIPinnedHTTPTransport(
            responseData: Data("ok".utf8),
            statusCode: 200
        )
        let client = SecureAIHTTPDataClient(
            hostResolver: PublicAIHostResolver(),
            transport: transport
        )

        _ = try await client.data(for: URLRequest(
            url: URL(string: "https://example.com/v1/models")!
        ))

        let calls = await transport.recordedCalls
        #expect(calls.count == 1)
        #expect(calls.first?.address == "93.184.216.34")
        #expect(calls.first?.serverName == "example.com")
        #expect(calls.first?.port == 443)
    }

    @Test("固定地址传输使用数值地址建连并在 HTTP 与 TLS 中保留原主机名")
    func pinnedTransportPreservesOriginalHostIdentity() async throws {
        let rawResponse = Data(
            "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok".utf8
        )
        let factory = RecordingAIPinnedConnectionFactory(response: rawResponse)
        let client = SecureAIHTTPDataClient(
            hostResolver: PublicAIHostResolver(),
            transport: NetworkPinnedHTTPTransport(connectionFactory: factory)
        )

        let (data, _) = try await client.data(for: URLRequest(
            url: URL(string: "https://example.com/v1/models?api-version=2025-01-01")!
        ))

        #expect(data == Data("ok".utf8))
        let call = try #require(await factory.recordedCalls.first)
        #expect(call.address == "93.184.216.34")
        #expect(call.serverName == "example.com")
        #expect(call.port == 443)
        let wireRequest = String(decoding: call.requestData, as: UTF8.self)
        #expect(wireRequest.hasPrefix("GET /v1/models?api-version=2025-01-01 HTTP/1.1\r\n"))
        #expect(wireRequest.contains("Host: example.com\r\n"))
        #expect(wireRequest.contains("Accept-Encoding: identity\r\n"))
    }

    @Test("同源重定向会重新解析、重新校验并固定新的数值地址")
    func secureHTTPClientRepinsSafeRedirects() async throws {
        let resolver = SequenceAIHostResolver(addressBatches: [
            ["93.184.216.34"],
            ["93.184.216.35"]
        ])
        let transport = SequenceAIPinnedHTTPTransport(responses: [
            (Data(), 307, ["Location": "/v2/models"]),
            (Data("ok".utf8), 200, [:])
        ])
        let client = SecureAIHTTPDataClient(
            hostResolver: resolver,
            transport: transport
        )

        let (data, response) = try await client.data(for: URLRequest(
            url: URL(string: "https://example.com/v1/models")!
        ))

        #expect(data == Data("ok".utf8))
        #expect(response.url?.absoluteString == "https://example.com/v2/models")
        #expect(await resolver.queriedHosts == ["example.com", "example.com"])
        let calls = await transport.recordedCalls
        #expect(calls.map(\.address) == ["93.184.216.34", "93.184.216.35"])
        #expect(calls.map(\.url.path) == ["/v1/models", "/v2/models"])
    }

    @Test("固定地址连接失败时只在已校验地址集合内故障转移")
    func secureHTTPClientFailsOverWithinValidatedAddresses() async throws {
        let resolver = SequenceAIHostResolver(addressBatches: [[
            "93.184.216.34", "93.184.216.35"
        ]])
        let transport = FailoverAIPinnedHTTPTransport(failingAddress: "93.184.216.34")
        let client = SecureAIHTTPDataClient(
            hostResolver: resolver,
            transport: transport
        )

        let (data, _) = try await client.data(for: URLRequest(
            url: URL(string: "https://example.com/v1/models")!
        ))

        #expect(data == Data("ok".utf8))
        #expect(await transport.attemptedAddresses == ["93.184.216.34", "93.184.216.35"])
        #expect(await resolver.queriedHosts == ["example.com"])
    }

    @Test("普通元数据 HTTP 客户端在读取内存前拒绝超限下载")
    func metadataHTTPClientRejectsOversizedDownload() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OversizedDownloadURLProtocol.self]
        let client = URLSessionHTTPDataClient(
            configuration: configuration,
            maximumResponseBytes: 16
        )

        await #expect(throws: HTTPDataClientError.responseTooLarge) {
            _ = try await client.data(for: URLRequest(url: URL(string: "https://example.com/test")!))
        }
    }

    @Test("普通元数据 HTTP 客户端分别拒绝降级 HTTP 和跨主机 HTTPS 重定向")
    func metadataHTTPClientRejectsUnsafeRedirects() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MetadataRedirectURLProtocol.self]
        let client = URLSessionHTTPDataClient(configuration: configuration)

        MetadataRedirectURLProtocol.reset()
        var downgradeRequest = URLRequest(url: URL(string: "https://book.douban.com/downgrade")!)
        downgradeRequest.timeoutInterval = 0.1
        _ = try? await client.data(for: downgradeRequest)
        #expect(!MetadataRedirectURLProtocol.didReachRedirectTarget)

        MetadataRedirectURLProtocol.reset()
        var crossHostRequest = URLRequest(url: URL(string: "https://book.douban.com/cross-host")!)
        crossHostRequest.timeoutInterval = 0.1
        _ = try? await client.data(for: crossHostRequest)
        #expect(!MetadataRedirectURLProtocol.didReachRedirectTarget)
    }

    @Test("无 Content-Length 的响应按分块累计并在超限块到达时拒绝")
    func responseBufferRejectsOversizedChunkBeforeAppendingIt() throws {
        var buffer = BoundedHTTPResponseBuffer(maximumResponseBytes: 16)
        try buffer.append(Data(repeating: 1, count: 8))
        try buffer.append(Data(repeating: 2, count: 8))

        #expect(throws: HTTPDataClientError.responseTooLarge) {
            try buffer.append(Data(repeating: 3, count: 8))
        }
        #expect(buffer.data.count == 16)
    }

    @Test("生产 AI HTTP 客户端取消任务时停止底层加载")
    func secureHTTPClientCancellationStopsLoading() async {
        let transport = CancellationTrackingAIPinnedHTTPTransport()
        let client = SecureAIHTTPDataClient(
            hostResolver: PublicAIHostResolver(),
            transport: transport
        )
        let task = Task {
            try await client.data(for: URLRequest(url: URL(string: "https://example.com/pending")!))
        }

        for _ in 0..<100 where !(await transport.hasStarted) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(await transport.hasStarted)

        task.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        for _ in 0..<100 where !(await transport.hasStopped) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(await transport.hasStopped)
    }
}

private struct PublicAIHostResolver: AIHostAddressResolving {
    func resolve(_ host: String) async throws -> [String] {
        ["93.184.216.34"]
    }
}

private actor RecordingAIPinnedHTTPTransport: AIPinnedHTTPTransport {
    struct Call: Sendable {
        let address: String
        let serverName: String
        let port: UInt16
    }

    private let responseData: Data
    private let statusCode: Int
    private(set) var recordedCalls: [Call] = []

    init(responseData: Data, statusCode: Int) {
        self.responseData = responseData
        self.statusCode = statusCode
    }

    func data(
        for request: URLRequest,
        connectingTo address: String,
        serverName: String,
        port: UInt16,
        maximumResponseBytes: Int
    ) async throws -> (Data, HTTPURLResponse) {
        recordedCalls.append(Call(address: address, serverName: serverName, port: port))
        guard responseData.count <= maximumResponseBytes else {
            throw HTTPDataClientError.responseTooLarge
        }
        return (
            responseData,
            HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
        )
    }
}

private actor RecordingAIPinnedConnectionFactory: AIPinnedConnectionFactory {
    struct Call: Sendable {
        let address: String
        let serverName: String
        let port: UInt16
        let requestData: Data
    }

    private let response: Data
    private(set) var recordedCalls: [Call] = []

    init(response: Data) {
        self.response = response
    }

    func exchange(
        requestData: Data,
        connectingTo address: String,
        serverName: String,
        port: UInt16,
        timeout: TimeInterval,
        maximumWireBytes: Int
    ) async throws -> Data {
        recordedCalls.append(Call(
            address: address,
            serverName: serverName,
            port: port,
            requestData: requestData
        ))
        return response
    }
}

private actor SequenceAIHostResolver: AIHostAddressResolving {
    private var addressBatches: [[String]]
    private(set) var queriedHosts: [String] = []

    init(addressBatches: [[String]]) {
        self.addressBatches = addressBatches
    }

    func resolve(_ host: String) async throws -> [String] {
        queriedHosts.append(host)
        return addressBatches.removeFirst()
    }
}

private actor SequenceAIPinnedHTTPTransport: AIPinnedHTTPTransport {
    struct Call: Sendable {
        let address: String
        let url: URL
    }

    private var responses: [(Data, Int, [String: String])]
    private(set) var recordedCalls: [Call] = []

    init(responses: [(Data, Int, [String: String])]) {
        self.responses = responses
    }

    func data(
        for request: URLRequest,
        connectingTo address: String,
        serverName: String,
        port: UInt16,
        maximumResponseBytes: Int
    ) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        recordedCalls.append(Call(address: address, url: url))
        let next = responses.removeFirst()
        return (
            next.0,
            HTTPURLResponse(
                url: url,
                statusCode: next.1,
                httpVersion: "HTTP/1.1",
                headerFields: next.2
            )!
        )
    }
}

private actor FailoverAIPinnedHTTPTransport: AIPinnedHTTPTransport {
    private let failingAddress: String
    private(set) var attemptedAddresses: [String] = []

    init(failingAddress: String) {
        self.failingAddress = failingAddress
    }

    func data(
        for request: URLRequest,
        connectingTo address: String,
        serverName: String,
        port: UInt16,
        maximumResponseBytes: Int
    ) async throws -> (Data, HTTPURLResponse) {
        attemptedAddresses.append(address)
        if address == failingAddress {
            throw NWError.posix(.ECONNREFUSED)
        }
        return (
            Data("ok".utf8),
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
        )
    }
}

private struct ThrowingHTTPDataClient: HTTPDataClient {
    enum Failure: Sendable {
        case timeout
        case cancelled
    }

    let failure: Failure

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        switch failure {
        case .timeout:
            throw URLError(.timedOut)
        case .cancelled:
            throw CancellationError()
        }
    }
}

private final class OversizedDownloadURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "17"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 0, count: 17))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class MetadataRedirectURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var reachedRedirectTarget = false

    static var didReachRedirectTarget: Bool {
        lock.withLock { reachedRedirectTarget }
    }

    static func reset() {
        lock.withLock { reachedRedirectTarget = false }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.url?.host == "attacker.example" {
            Self.lock.withLock { Self.reachedRedirectTarget = true }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("unexpected".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let redirectURL = request.url?.path == "/cross-host"
            ? URL(string: "https://attacker.example/private")!
            : URL(string: "http://book.douban.com/private")!
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": redirectURL.absoluteString]
        )!
        client?.urlProtocol(
            self,
            wasRedirectedTo: URLRequest(url: redirectURL),
            redirectResponse: response
        )
    }

    override func stopLoading() {}
}

private actor CancellationTrackingAIPinnedHTTPTransport: AIPinnedHTTPTransport {
    private(set) var hasStarted = false
    private(set) var hasStopped = false

    func data(
        for request: URLRequest,
        connectingTo address: String,
        serverName: String,
        port: UInt16,
        maximumResponseBytes: Int
    ) async throws -> (Data, HTTPURLResponse) {
        hasStarted = true
        do {
            try await Task.sleep(for: .seconds(60))
            throw URLError(.timedOut)
        } catch is CancellationError {
            hasStopped = true
            throw CancellationError()
        }
    }
}

private actor StubHTTPDataClient: HTTPDataClient {
    private let data: Data
    private let statusCode: Int
    private(set) var lastRequest: URLRequest?

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (data, response)
    }
}

private actor SequenceHTTPDataClient: HTTPDataClient {
    private var responses: [(Data, Int, [String: String])]
    private(set) var requestCount = 0

    init(responses: [(Data, Int, [String: String])]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestCount += 1
        let next = responses.removeFirst()
        return (
            next.0,
            HTTPURLResponse(
                url: request.url!,
                statusCode: next.1,
                httpVersion: "HTTP/1.1",
                headerFields: next.2
            )!
        )
    }
}

private actor ConnectionLostThenSuccessHTTPDataClient: HTTPDataClient {
    private let success: Data
    private(set) var requestCount = 0

    init(success: Data) {
        self.success = success
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestCount += 1
        if requestCount == 1 {
            throw URLError(.networkConnectionLost)
        }
        return (
            success,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
        )
    }
}
