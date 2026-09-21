import Foundation
import Testing
@testable import PersonalLibrary

@Suite("AI Config Tests")
struct AIConfigTests {
    @Test("百炼默认 endpoint、推荐模型和联网策略可直接使用")
    func bailianDefaults() {
        let config = AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")

        #expect(config.endpoint.absoluteString == "https://dashscope.aliyuncs.com/compatible-mode/v1")
        #expect(config.model == "qwen-plus")
        #expect(config.searchStrategy == .enableSearch)
        #expect(config.isAvailable)
    }

    @Test("预设平台只接受固定联网策略，自定义平台可选兼容策略")
    func platformSearchStrategyCompatibility() {
        for preset in AIPlatformPreset.allCases where preset != .custom {
            #expect(preset.allowedSearchStrategies == [preset.defaultSearchStrategy])
        }
        #expect(AIPlatformPreset.custom.allowedSearchStrategies == AISearchStrategy.allCases)

        var deepSeek = AIPlatformPreset.deepSeek.defaultConfig(apiKey: "test-key")
        deepSeek.searchStrategy = .enableSearch
        #expect(!deepSeek.isAvailable)

        var custom = AIPlatformPreset.custom.defaultConfig(apiKey: "test-key")
        custom.endpoint = URL(string: "https://api.example.com/v1")!
        custom.model = "model"
        custom.searchStrategy = .enableSearch
        custom.replaceAPIKey("test-key")
        #expect(!custom.isAvailable)
        custom.verifiedSearchConfigurationID = custom.searchConfigurationID
        #expect(custom.isAvailable)
        custom.model = "another-model"
        #expect(!custom.isAvailable)
        custom.searchStrategy = .none
        #expect(!custom.isAvailable)
    }

    @Test("AI endpoint 只允许无凭据的公网 HTTPS 地址")
    func endpointPolicyRejectsUnsafeTargets() {
        let unsafe = [
            "http://api.example.com/v1",
            "https://user:secret@api.example.com/v1",
            "https://api.example.com/v1#fragment",
            "https://api.example.com/v1?api_key=secret",
            "https://api.example.com/v1?access-token=secret",
            "https://api.example.com/v1?authorization=Bearer-secret",
            "https://api.example.com/v1?access_key=secret",
            "https://api.example.com/v1?secret_access_key=secret",
            "https://api.example.com/v1?subscription-key=secret",
            "https://api.example.com/v1?x-functions-key=secret",
            "https://api.example.com/v1?AccessKeyId=secret",
            "https://api.example.com/v1?auth=secret",
            "https://api.example.com/v1?sig=secret",
            "https://api.example.com/v1?authKey=secret",
            "https://api.example.com/v1?consumerKey=secret",
            "https://api.example.com/v1?privateKey=secret",
            "https://api.example.com/v1?authSig=secret",
            "https://api.example.com/v1?unknown_parameter=secret",
            "https://localhost/v1",
            "https://127.0.0.1/v1",
            "https://10.0.0.8/v1",
            "https://169.254.1.1/v1",
            "https://198.18.0.87/v1",
            "https://[::1]/v1",
            "https://[::ffff:127.0.0.1]/v1",
            "https://[::ffff:10.0.0.8]/v1",
            "https://2130706433/v1"
        ]

        for value in unsafe {
            #expect(throws: AIEndpointPolicyError.self) {
                try AIEndpointPolicy.validate(URL(string: value)!)
            }
        }

        #expect(throws: Never.self) {
            try AIEndpointPolicy.validate(AIPlatformPreset.bailian.defaultEndpoint)
        }
        #expect(
            AIEndpointPolicyError.credentialsNotAllowed.errorDescription
                == "接口地址不能包含用户名、密码或除 api-version 外的查询参数"
        )
    }

    @Test("AI endpoint 路径拼接保留基础路径和查询参数")
    func endpointPathAppending() throws {
        #expect(try AIEndpointPolicy.appending(
            "models",
            to: URL(string: "https://api.example.com/v1/")!
        ).absoluteString == "https://api.example.com/v1/models")
        #expect(try AIEndpointPolicy.appending(
            "chat/completions",
            to: URL(string: "https://api.example.com/v1?api-version=2026-09-01")!
        ).absoluteString == "https://api.example.com/v1/chat/completions?api-version=2026-09-01")
    }

    @Test("不安全 endpoint 即使字段齐全也不能启用 AI")
    func unsafeEndpointIsUnavailable() {
        let config = AIConfig(
            platform: .custom,
            endpoint: URL(string: "https://127.0.0.1/v1")!,
            apiKey: "test-key",
            model: "model",
            searchStrategy: .enableSearch
        )

        #expect(!config.isAvailable)
    }

    @Test("AI API Key 只写入密钥存储而不进入 UserDefaults")
    func apiKeyUsesSecretStore() {
        let defaults = UserDefaults(suiteName: "AIConfigTests.\(UUID().uuidString)")!
        let secrets = InMemoryAISecretStore()
        let store = AIConfigStore(defaults: defaults, secretStore: secrets)
        let config = AIPlatformPreset.bailian.defaultConfig(apiKey: "super-secret")

        #expect(store.save(config))
        #expect(secrets.credential?.apiKey == "super-secret")
        #expect(secrets.credential?.destinationID == config.credentialDestinationID)
        #expect(!defaults.dictionaryRepresentation().values.contains { ($0 as? String) == "super-secret" })
    }

    @Test("API Key 与平台和 Endpoint 绑定，目标变化后不能复用")
    func apiKeyIsBoundToDestination() {
        var config = AIPlatformPreset.bailian.defaultConfig(apiKey: "old-key")
        let originalDestination = config.credentialDestinationID
        let originalCredentialID = config.apiKeyCredentialID

        #expect(config.apiKeyDestinationID == originalDestination)
        #expect(config.isConnectionTestable)

        config.platform = .custom
        config.endpoint = URL(string: "https://api.example.com/v1")!
        config.model = "search-model"
        config.searchStrategy = .enableSearch
        #expect(!config.isConnectionTestable)

        config.discardAPIKeyIfDestinationChanged()
        #expect(config.apiKey.isEmpty)
        #expect(config.apiKeyDestinationID == nil)

        config.replaceAPIKey("new-key")
        #expect(config.apiKeyDestinationID == config.credentialDestinationID)
        #expect(config.apiKeyCredentialID != originalCredentialID)
        #expect(config.isConnectionTestable)
    }

    @Test("配置存储拒绝把旧目标的 API Key 保存给新目标")
    func storeRejectsCredentialDestinationMismatch() {
        let defaults = UserDefaults(suiteName: "AIConfigTests.\(UUID().uuidString)")!
        let secrets = InMemoryAISecretStore()
        let store = AIConfigStore(defaults: defaults, secretStore: secrets)
        let original = AIPlatformPreset.bailian.defaultConfig(apiKey: "old-key")
        #expect(store.save(original))

        var changed = store.load()
        changed.platform = .custom
        changed.endpoint = URL(string: "https://api.example.com/v1")!
        changed.model = "search-model"
        changed.searchStrategy = .enableSearch
        #expect(!store.save(changed))
        #expect(secrets.credential?.apiKey == "old-key")

        changed.replaceAPIKey("new-key")
        #expect(store.save(changed))
        #expect(secrets.credential?.apiKey == "new-key")
        #expect(store.load().apiKeyDestinationID == changed.credentialDestinationID)
    }

    @Test("密钥更新失败时保留之前可用的配置")
    func failedCredentialUpdatePreservesPreviousConfiguration() {
        let defaults = UserDefaults(suiteName: "AIConfigTests.\(UUID().uuidString)")!
        let secrets = FailingOnceAISecretStore()
        let store = AIConfigStore(defaults: defaults, secretStore: secrets)
        let original = AIPlatformPreset.bailian.defaultConfig(apiKey: "old-key")
        #expect(store.save(original))

        var replacement = original
        replacement.replaceAPIKey("new-key")
        secrets.failNextSaveAfterMutation = true

        #expect(!store.save(replacement))
        #expect(store.load().apiKey == "old-key")
        #expect(store.load().apiKeyCredentialID == original.apiKeyCredentialID)
        #expect(store.load().model == original.model)
    }

    @Test("缺少目标绑定的旧密钥默认拒绝加载")
    func legacyUnboundCredentialFailsClosed() {
        let defaults = UserDefaults(suiteName: "AIConfigTests.\(UUID().uuidString)")!
        let secrets = InMemoryAISecretStore(credential: AIStoredCredential(
            apiKey: "legacy-key",
            destinationID: "",
            credentialID: UUID().uuidString
        ))

        let config = AIConfigStore(defaults: defaults, secretStore: secrets).load()

        #expect(config.apiKey.isEmpty)
        #expect(!config.isConnectionTestable)
    }

    @Test("更换 API Key 会使旧联网验证失效")
    func replacingCredentialInvalidatesSearchVerification() {
        var config = AIPlatformPreset.custom.defaultConfig(apiKey: "old-key")
        config.endpoint = URL(string: "https://api.example.com/v1")!
        config.model = "search-model"
        config.searchStrategy = .enableSearch
        config.replaceAPIKey("old-key")
        config.verifiedSearchConfigurationID = config.searchConfigurationID
        #expect(config.isAvailable)

        config.replaceAPIKey("new-key")

        #expect(!config.isAvailable)
    }

    @Test("联网能力探针用不可预测随机信标校验真实检索")
    func searchCapabilityProbeRequiresBeaconValue() async throws {
        let endpoint = AIPlatformPreset.bailian.defaultEndpoint
        let randomness = String(repeating: "ab", count: 32)
        let beacon = #"{"round":246810,"randomness":"\#(randomness)"}"#.data(using: .utf8)!
        let challenge = try await AISearchCapabilityProbe.fetchChallenge(
            httpClient: ProbeHTTPDataClient(data: beacon, statusCode: 200)
        )
        let request = AISearchCapabilityProbe.request(for: challenge)

        #expect(request.requiresJSON)
        #expect(request.messages.first?.content.contains("246810") == true)
        #expect(request.messages.first?.content.contains(randomness) == false)
        #expect(throws: AISearchCapabilityProbeError.self) {
            try AISearchCapabilityProbe.validate("连接成功", challenge: challenge, endpoint: endpoint)
        }
        #expect(throws: AISearchCapabilityProbeError.self) {
            try AISearchCapabilityProbe.validate(
                #"{"status":"ok","round":246810,"randomness":"wrong","sources":["https://api.drand.sh/public/246810"]}"#,
                challenge: challenge,
                endpoint: endpoint
            )
        }

        let sources = try AISearchCapabilityProbe.validate(
            #"{"status":"ok","round":246810,"randomness":"\#(randomness)","sources":["https://api.drand.sh/public/246810"]}"#,
            challenge: challenge,
            endpoint: endpoint
        )
        #expect(sources.map { $0.host } == ["api.drand.sh"])
    }

    @Test("联网能力探针接受模型返回的 JSON 代码块")
    func searchCapabilityProbeAcceptsFencedJSON() throws {
        let endpoint = AIPlatformPreset.bailian.defaultEndpoint
        let randomness = String(repeating: "ab", count: 32)
        let challenge = AISearchCapabilityChallenge(round: 246810, randomness: randomness)
        let content = """
        ```json
        {"status":"ok","round":246810,"randomness":"\(randomness)","sources":["https://api.drand.sh/public/246810"]}
        ```
        """

        let sources = try AISearchCapabilityProbe.validate(
            content,
            challenge: challenge,
            endpoint: endpoint
        )

        #expect(sources.map(\.host) == ["api.drand.sh"])
    }

    @Test("百炼联网能力探针不依赖随机信标并校验搜索注入和外部来源")
    func bailianSearchCapabilityProbeUsesSearchInjectionEvidence() throws {
        let endpoint = AIPlatformPreset.bailian.defaultEndpoint
        let request = AISearchCapabilityProbe.bailianRequest()

        #expect(request.requiresJSON)
        #expect(request.temperature == 0)
        #expect(request.messages.first?.content.contains("drand") == false)
        #expect(request.messages.first?.content.contains("只需使用搜索结果中的 URL，不要尝试打开网页正文") == true)

        let content = #"{"status":"ok","sources":["https://www.isbn-international.org/content/what-isbn"]}"#
        #expect(throws: AISearchCapabilityProbeError.self) {
            try AISearchCapabilityProbe.validateBailian(
                AICompletionResponse(
                    content: content,
                    usage: AITokenUsage(input: nil, output: 20, total: nil)
                ),
                endpoint: endpoint
            )
        }
        #expect(throws: AISearchCapabilityProbeError.self) {
            try AISearchCapabilityProbe.validateBailian(
                AICompletionResponse(
                    content: content,
                    usage: AITokenUsage(input: 199, output: 20, total: 219)
                ),
                endpoint: endpoint
            )
        }

        let sources = try AISearchCapabilityProbe.validateBailian(
            AICompletionResponse(
                content: content,
                usage: AITokenUsage(input: 200, output: 20, total: 220)
            ),
            endpoint: endpoint
        )
        #expect(sources.map(\.host) == ["www.isbn-international.org"])
    }

    @Test("百炼 token 证据探针只用于官方 Endpoint")
    func bailianSearchCapabilityProbeIsBoundToOfficialEndpoint() {
        let official = AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        #expect(AISearchCapabilityProbe.usesBailianEvidence(for: official))

        var trailingSlash = official
        trailingSlash.endpoint = URL(
            string: "https://dashscope.aliyuncs.com/compatible-mode/v1/"
        )!
        trailingSlash.replaceAPIKey("test-key")
        #expect(AISearchCapabilityProbe.usesBailianEvidence(for: trailingSlash))

        var edited = official
        edited.endpoint = URL(string: "https://api.example.com/v1")!
        edited.replaceAPIKey("test-key")
        #expect(!AISearchCapabilityProbe.usesBailianEvidence(for: edited))

        var custom = AIPlatformPreset.custom.defaultConfig(apiKey: "test-key")
        custom.endpoint = AIPlatformPreset.bailian.defaultEndpoint
        custom.model = "qwen-plus"
        custom.searchStrategy = .enableSearch
        custom.replaceAPIKey("test-key")
        #expect(!AISearchCapabilityProbe.usesBailianEvidence(for: custom))
    }

    @Test("连接测试硬截止不等待不响应取消的底层操作")
    func connectionTestDeadlineIsGlobal() async {
        await #expect(throws: AIConnectionTestError.timedOut) {
            try await AIConnectionTestDeadline.run(timeout: .milliseconds(20)) {
                let nonCooperativeWork = Task.detached {
                    try? await Task.sleep(for: .seconds(1))
                }
                await nonCooperativeWork.value
            }
        }
    }

    @MainActor
    @Test("连接测试成功后立即持久化验证并启用 AI 补全")
    func successfulConnectionTestAutomaticallyEnablesAIEnrichment() async throws {
        let defaults = UserDefaults(suiteName: "AIConfigTests.\(UUID().uuidString)")!
        let store = AIConfigStore(defaults: defaults, secretStore: InMemoryAISecretStore())
        var config = AIPlatformPreset.custom.defaultConfig(apiKey: "test-key")
        config.endpoint = URL(string: "https://api.example.com/v1")!
        config.model = "custom-search-model"
        config.searchStrategy = .enableSearch
        config.replaceAPIKey("test-key")
        #expect(!store.load().isAvailable)

        let expectedConfigurationID = config.searchConfigurationID
        let service = AIConnectionTestService(store: store, probe: { testedConfig in
            #expect(testedConfig.searchConfigurationID == expectedConfigurationID)
        })
        let baselineRevision = store.revision()

        let verified = try await service.testAndSave(
            config,
            expectedStoreRevision: baselineRevision
        )

        #expect(verified.isAvailable)
        #expect(store.load().isAvailable)
        #expect(
            store.load().verifiedSearchConfigurationID
                == store.load().searchConfigurationID
        )
    }

    @MainActor
    @Test("连接测试在首次短暂超时后自动重试")
    func connectionTestRetriesOneTransientTimeout() async throws {
        let defaults = UserDefaults(suiteName: "AIConfigTests.\(UUID().uuidString)")!
        let store = AIConfigStore(defaults: defaults, secretStore: InMemoryAISecretStore())
        var config = AIPlatformPreset.custom.defaultConfig(apiKey: "test-key")
        config.endpoint = URL(string: "https://api.example.com/v1")!
        config.model = "custom-search-model"
        config.searchStrategy = .enableSearch
        config.replaceAPIKey("test-key")
        let attempts = ProbeAttemptCounter()
        let service = AIConnectionTestService(
            store: store,
            maximumAttempts: 2,
            probe: { _ in
                if await attempts.next() == 1 {
                    throw URLError(.timedOut)
                }
            }
        )
        let baselineRevision = store.revision()

        let verified = try await service.testAndSave(
            config,
            expectedStoreRevision: baselineRevision
        )

        #expect(await attempts.value == 2)
        #expect(verified.isAvailable)
        #expect(store.load().isAvailable)
    }

    @MainActor
    @Test("连接测试在首次短暂网络中断后自动重试")
    func connectionTestRetriesOneTransientNetworkFailure() async throws {
        let defaults = UserDefaults(suiteName: "AIConfigTests.\(UUID().uuidString)")!
        let store = AIConfigStore(defaults: defaults, secretStore: InMemoryAISecretStore())
        var config = AIPlatformPreset.custom.defaultConfig(apiKey: "test-key")
        config.endpoint = URL(string: "https://api.example.com/v1")!
        config.model = "custom-search-model"
        config.searchStrategy = .enableSearch
        config.replaceAPIKey("test-key")
        let attempts = ProbeAttemptCounter()
        let service = AIConnectionTestService(
            store: store,
            maximumAttempts: 2,
            probe: { _ in
                if await attempts.next() == 1 {
                    throw URLError(.networkConnectionLost)
                }
            }
        )

        let verified = try await service.testAndSave(
            config,
            expectedStoreRevision: store.revision()
        )

        #expect(await attempts.value == 2)
        #expect(verified.isAvailable)
    }

    @MainActor
    @Test("连接测试按 Retry-After 等待后再重试且不叠加请求")
    func connectionTestHonorsRetryAfterBeforeSingleRetry() async throws {
        let defaults = UserDefaults(suiteName: "AIConfigTests.\(UUID().uuidString)")!
        let store = AIConfigStore(defaults: defaults, secretStore: InMemoryAISecretStore())
        var config = AIPlatformPreset.custom.defaultConfig(apiKey: "test-key")
        config.endpoint = URL(string: "https://api.example.com/v1")!
        config.model = "custom-search-model"
        config.searchStrategy = .enableSearch
        config.replaceAPIKey("test-key")
        let attempts = ProbeAttemptCounter()
        let delays = RetryDelayRecorder()
        let service = AIConnectionTestService(
            store: store,
            maximumAttempts: 2,
            retrySleep: { delay in await delays.record(delay) },
            probe: { _ in
                if await attempts.next() == 1 {
                    throw AIClientError.rateLimited(retryAfter: 7)
                }
            }
        )

        _ = try await service.testAndSave(
            config,
            expectedStoreRevision: store.revision()
        )

        #expect(await attempts.value == 2)
        #expect(await delays.values == [7])
    }

    @MainActor
    @Test("连接测试不会将非有限限流延迟传入休眠")
    func connectionTestSanitizesNonFiniteRetryAfter() async throws {
        let defaults = UserDefaults(suiteName: "AIConfigTests.\(UUID().uuidString)")!
        let store = AIConfigStore(defaults: defaults, secretStore: InMemoryAISecretStore())
        var config = AIPlatformPreset.custom.defaultConfig(apiKey: "test-key")
        config.endpoint = URL(string: "https://api.example.com/v1")!
        config.model = "custom-search-model"
        config.searchStrategy = .enableSearch
        config.replaceAPIKey("test-key")
        let attempts = ProbeAttemptCounter()
        let delays = RetryDelayRecorder()
        let service = AIConnectionTestService(
            store: store,
            maximumAttempts: 2,
            retrySleep: { delay in await delays.record(delay) },
            probe: { _ in
                if await attempts.next() == 1 {
                    throw AIClientError.rateLimited(retryAfter: .nan)
                }
            }
        )

        _ = try await service.testAndSave(
            config,
            expectedStoreRevision: store.revision()
        )

        #expect(await attempts.value == 2)
        #expect(await delays.values == [1])
    }

    @MainActor
    @Test("每次连接探针都有独立截止时间且最多只重试一次")
    func connectionTestBoundsEachNonCooperativeProbeAttempt() async throws {
        let defaults = UserDefaults(suiteName: "AIConfigTests.\(UUID().uuidString)")!
        let store = AIConfigStore(defaults: defaults, secretStore: InMemoryAISecretStore())
        var config = AIPlatformPreset.custom.defaultConfig(apiKey: "test-key")
        config.endpoint = URL(string: "https://api.example.com/v1")!
        config.model = "custom-search-model"
        config.searchStrategy = .enableSearch
        config.replaceAPIKey("test-key")
        let attempts = ProbeAttemptCounter()
        let service = AIConnectionTestService(
            store: store,
            maximumAttempts: 2,
            attemptTimeout: .milliseconds(20),
            probe: { _ in
                _ = await attempts.next()
                let nonCooperativeWork = Task.detached {
                    try? await Task.sleep(for: .seconds(1))
                }
                await nonCooperativeWork.value
            }
        )
        await #expect(throws: AIConnectionTestError.timedOut) {
            _ = try await service.testAndSave(
                config,
                expectedStoreRevision: store.revision()
            )
        }

        #expect(await attempts.value == 2)
        #expect(!store.load().isAvailable)
    }

    @MainActor
    @Test("连接测试第二次仍被限流时停止且不保存")
    func connectionTestStopsAfterSecondRateLimit() async throws {
        let defaults = UserDefaults(suiteName: "AIConfigTests.\(UUID().uuidString)")!
        let store = AIConfigStore(defaults: defaults, secretStore: InMemoryAISecretStore())
        var config = AIPlatformPreset.custom.defaultConfig(apiKey: "test-key")
        config.endpoint = URL(string: "https://api.example.com/v1")!
        config.model = "custom-search-model"
        config.searchStrategy = .enableSearch
        config.replaceAPIKey("test-key")
        let attempts = ProbeAttemptCounter()
        let delays = RetryDelayRecorder()
        let service = AIConnectionTestService(
            store: store,
            maximumAttempts: 2,
            retrySleep: { delay in await delays.record(delay) },
            probe: { _ in
                _ = await attempts.next()
                throw AIClientError.rateLimited(retryAfter: 3)
            }
        )

        await #expect(throws: AIClientError.rateLimited(retryAfter: 3)) {
            _ = try await service.testAndSave(
                config,
                expectedStoreRevision: store.revision()
            )
        }

        #expect(await attempts.value == 2)
        #expect(await delays.values == [3])
        #expect(!store.load().isAvailable)
    }

    @MainActor
    @Test("连接测试在限流退避期间取消时不再请求也不保存")
    func connectionTestCancellationDuringRateLimitBackoffDoesNotSave() async throws {
        let defaults = UserDefaults(suiteName: "AIConfigTests.\(UUID().uuidString)")!
        let store = AIConfigStore(defaults: defaults, secretStore: InMemoryAISecretStore())
        var config = AIPlatformPreset.custom.defaultConfig(apiKey: "test-key")
        config.endpoint = URL(string: "https://api.example.com/v1")!
        config.model = "custom-search-model"
        config.searchStrategy = .enableSearch
        config.replaceAPIKey("test-key")
        let attempts = ProbeAttemptCounter()
        let service = AIConnectionTestService(
            store: store,
            maximumAttempts: 2,
            retrySleep: { _ in throw CancellationError() },
            probe: { _ in
                _ = await attempts.next()
                throw AIClientError.rateLimited(retryAfter: 5)
            }
        )

        await #expect(throws: CancellationError.self) {
            _ = try await service.testAndSave(
                config,
                expectedStoreRevision: store.revision()
            )
        }

        #expect(await attempts.value == 1)
        #expect(!store.load().isAvailable)
    }

    @MainActor
    @Test("连接测试期间已保存新配置时拒绝旧结果覆盖")
    func staleConnectionTestCannotOverwriteNewerConfiguration() async throws {
        let defaults = UserDefaults(suiteName: "AIConfigTests.\(UUID().uuidString)")!
        let store = AIConfigStore(defaults: defaults, secretStore: InMemoryAISecretStore())
        var tested = AIPlatformPreset.custom.defaultConfig(apiKey: "old-key")
        tested.endpoint = URL(string: "https://old.example.com/v1")!
        tested.model = "old-search-model"
        tested.searchStrategy = .enableSearch
        tested.replaceAPIKey("old-key")
        #expect(store.save(tested))

        var newer = AIPlatformPreset.custom.defaultConfig(apiKey: "new-key")
        newer.endpoint = URL(string: "https://new.example.com/v1")!
        newer.model = "new-search-model"
        newer.searchStrategy = .enableSearch
        newer.replaceAPIKey("new-key")
        let newerConfig = newer
        let baselineRevision = store.revision()

        let service = AIConnectionTestService(store: store, probe: { _ in
            #expect(store.save(newerConfig))
        })

        await #expect(throws: AIConnectionTestError.configurationChanged) {
            _ = try await service.testAndSave(
                tested,
                expectedStoreRevision: baselineRevision
            )
        }
        #expect(store.load().endpoint == newerConfig.endpoint)
        #expect(store.load().model == newerConfig.model)
    }

    @MainActor
    @Test("配置内容即使改回原值也拒绝旧测试结果")
    func connectionTestRejectsABAConfigurationChange() async throws {
        let defaults = UserDefaults(suiteName: "AIConfigTests.\(UUID().uuidString)")!
        let store = AIConfigStore(defaults: defaults, secretStore: InMemoryAISecretStore())
        var original = AIPlatformPreset.custom.defaultConfig(apiKey: "original-key")
        original.endpoint = URL(string: "https://original.example.com/v1")!
        original.model = "original-model"
        original.searchStrategy = .enableSearch
        original.replaceAPIKey("original-key")
        #expect(store.save(original))

        var tested = original
        tested.model = "tested-model"

        var intermediate = original
        intermediate.model = "intermediate-model"
        let originalConfig = original
        let intermediateConfig = intermediate
        let baselineRevision = store.revision()
        let service = AIConnectionTestService(store: store, probe: { _ in
            #expect(store.save(intermediateConfig))
            #expect(store.save(originalConfig))
        })

        await #expect(throws: AIConnectionTestError.configurationChanged) {
            _ = try await service.testAndSave(
                tested,
                expectedStoreRevision: baselineRevision
            )
        }
        #expect(store.load().model == originalConfig.model)
    }

    @MainActor
    @Test("AI 配置状态源可在保存后立即刷新")
    func aiAvailabilityRefreshesAfterSaving() {
        let defaults = UserDefaults(suiteName: "AIConfigTests.\(UUID().uuidString)")!
        let store = AIConfigStore(defaults: defaults, secretStore: InMemoryAISecretStore())
        let availability = AIConfigAvailability(store: store)
        #expect(!availability.isAvailable)

        let config = AIPlatformPreset.bailian.defaultConfig(apiKey: "test-key")
        #expect(store.save(config))
        availability.refresh()

        #expect(availability.isAvailable)
    }

    @Test("自定义模型的联网验证只对当前配置组合有效")
    func persistsMatchingSearchCapabilityVerification() {
        let defaults = UserDefaults(suiteName: "AIConfigTests.\(UUID().uuidString)")!
        let store = AIConfigStore(defaults: defaults, secretStore: InMemoryAISecretStore())
        var config = AIPlatformPreset.custom.defaultConfig(apiKey: "test-key")
        config.endpoint = URL(string: "https://api.example.com/v1")!
        config.model = "custom-search-model"
        config.searchStrategy = .enableSearch
        config.replaceAPIKey("test-key")
        config.verifiedSearchConfigurationID = config.searchConfigurationID

        #expect(store.save(config))
        #expect(store.load().isAvailable)

        config.model = "untested-model"
        #expect(store.save(config))
        #expect(!store.load().isAvailable)
    }

    @Test("新 Key 测试连接后保存会保留同一凭据版本")
    func testedCredentialRemainsVerifiedWhenSaved() throws {
        let defaults = UserDefaults(suiteName: "AIConfigTests.\(UUID().uuidString)")!
        let store = AIConfigStore(defaults: defaults, secretStore: InMemoryAISecretStore())
        let endpoint = URL(string: "https://api.example.com/v1")!
        let credentialID = "credential-version-1"

        var tested = try AISettingsConfigBuilder.makeConfig(
            platform: .custom,
            endpoint: endpoint,
            model: "search-model",
            searchStrategy: .enableSearch,
            enteredAPIKey: "new-key",
            savedCredential: nil,
            pendingCredentialID: credentialID,
            verifiedSearchConfigurationID: nil
        )
        tested.verifiedSearchConfigurationID = tested.searchConfigurationID

        let saved = try AISettingsConfigBuilder.makeConfig(
            platform: .custom,
            endpoint: endpoint,
            model: "search-model",
            searchStrategy: .enableSearch,
            enteredAPIKey: "new-key",
            savedCredential: nil,
            pendingCredentialID: credentialID,
            verifiedSearchConfigurationID: tested.verifiedSearchConfigurationID
        )

        #expect(saved.apiKeyCredentialID == tested.apiKeyCredentialID)
        #expect(saved.verifiedSearchConfigurationID == saved.searchConfigurationID)
        #expect(store.save(saved))
        #expect(store.load().isAvailable)
    }

    @Test("AI 重定向只允许同一公网主机")
    func redirectPolicyPreventsCredentialLeaks() {
        let original = URL(string: "https://api.example.com/v1/chat/completions")!

        #expect(AIEndpointPolicy.allowsRedirect(
            from: original,
            to: URL(string: "https://api.example.com/v2/chat/completions")!
        ))
        #expect(!AIEndpointPolicy.allowsRedirect(
            from: original,
            to: URL(string: "https://evil.example/collect")!
        ))
        #expect(!AIEndpointPolicy.allowsRedirect(
            from: original,
            to: URL(string: "https://127.0.0.1/collect")!
        ))
    }

    @Test("DNS 解析到私网地址时在发送请求前拒绝")
    func rejectsHostnameResolvingToPrivateAddress() async {
        let client = SecureAIHTTPDataClient(
            maximumResponseBytes: 2_000_000,
            hostResolver: StubAIHostResolver(addresses: ["10.0.0.8"])
        )

        await #expect(throws: AIEndpointPolicyError.privateOrReservedHost) {
            _ = try await client.data(for: URLRequest(
                url: URL(string: "https://api.example.com/v1/models")!
            ))
        }
    }

    @Test("VPN Fake-IP 仅允许受信任的 AI 与联网验证主机")
    func allowsVPNFakeIPOnlyForTrustedHosts() async throws {
        let client = SecureAIHTTPDataClient(
            hostResolver: StubAIHostResolver(addresses: ["198.18.0.87"]),
            transport: SuccessfulAIPinnedHTTPTransport()
        )

        let trustedURLs = AIPlatformPreset.allCases
            .filter { $0 != .custom }
            .map(\.defaultEndpoint)
            + [URL(string: "https://api.drand.sh/public/latest")!]
        for url in trustedURLs {
            let (_, response) = try await client.data(for: URLRequest(url: url))
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
        }

        await #expect(throws: AIEndpointPolicyError.privateOrReservedHost) {
            _ = try await client.data(for: URLRequest(
                url: URL(string: "https://api.example.com/v1/models")!
            ))
        }

        let privateAddressClient = SecureAIHTTPDataClient(
            hostResolver: StubAIHostResolver(addresses: ["10.0.0.8"]),
            transport: SuccessfulAIPinnedHTTPTransport()
        )
        await #expect(throws: AIEndpointPolicyError.privateOrReservedHost) {
            _ = try await privateAddressClient.data(for: URLRequest(
                url: AIPlatformPreset.bailian.defaultEndpoint
            ))
        }
    }
}

private struct StubAIHostResolver: AIHostAddressResolving {
    let addresses: [String]

    func resolve(_ host: String) async throws -> [String] {
        addresses
    }
}

private actor ProbeAttemptCounter {
    private(set) var value = 0

    func next() -> Int {
        value += 1
        return value
    }
}

private actor RetryDelayRecorder {
    private(set) var values: [TimeInterval] = []

    func record(_ value: TimeInterval) {
        values.append(value)
    }
}

private final class InMemoryAISecretStore: AISecretStore, @unchecked Sendable {
    var credential: AIStoredCredential?

    init(credential: AIStoredCredential? = nil) {
        self.credential = credential
    }

    func loadCredential() -> AIStoredCredential? { credential }
    func saveCredential(_ credential: AIStoredCredential) -> Bool {
        self.credential = credential
        return true
    }
    func deleteCredential() -> Bool {
        credential = nil
        return true
    }
}

private final class FailingOnceAISecretStore: AISecretStore, @unchecked Sendable {
    var credential: AIStoredCredential?
    var failNextSaveAfterMutation = false

    func loadCredential() -> AIStoredCredential? { credential }

    func saveCredential(_ credential: AIStoredCredential) -> Bool {
        self.credential = credential
        if failNextSaveAfterMutation {
            self.credential = nil
            failNextSaveAfterMutation = false
            return false
        }
        return true
    }

    func deleteCredential() -> Bool {
        credential = nil
        return true
    }
}

private actor ProbeHTTPDataClient: HTTPDataClient {
    let data: Data
    let statusCode: Int

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (data, response)
    }
}

private struct SuccessfulAIPinnedHTTPTransport: AIPinnedHTTPTransport {
    func data(
        for request: URLRequest,
        connectingTo address: String,
        serverName: String,
        port: UInt16,
        maximumResponseBytes: Int
    ) async throws -> (Data, HTTPURLResponse) {
        (
            Data(),
            HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
            )!
        )
    }
}
