import Foundation
import Observation

enum AISearchStrategy: String, CaseIterable, Codable, Sendable {
    case none
    case enableSearch
    case onlineSuffix
    case openAIWebSearch

    var displayName: String {
        switch self {
        case .none: return "不支持联网"
        case .enableSearch: return "enable_search"
        case .onlineSuffix: return "模型名 :online"
        case .openAIWebSearch: return "OpenAI Web Search"
        }
    }
}

enum AIPlatformPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case bailian
    case openAI
    case deepSeek
    case openRouter
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bailian: return "百炼"
        case .openAI: return "OpenAI"
        case .deepSeek: return "DeepSeek"
        case .openRouter: return "OpenRouter"
        case .custom: return "自定义"
        }
    }

    var defaultEndpoint: URL {
        switch self {
        case .bailian:
            return URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1")!
        case .openAI:
            return URL(string: "https://api.openai.com/v1")!
        case .deepSeek:
            return URL(string: "https://api.deepseek.com/v1")!
        case .openRouter:
            return URL(string: "https://openrouter.ai/api/v1")!
        case .custom:
            return URL(string: "https://example.com/v1")!
        }
    }

    var recommendedModel: String {
        switch self {
        case .bailian: return "qwen-plus"
        case .openAI: return "gpt-5-search-api"
        case .deepSeek: return "deepseek-chat"
        case .openRouter: return "openai/gpt-5-mini"
        case .custom: return ""
        }
    }

    var defaultSearchStrategy: AISearchStrategy {
        switch self {
        case .bailian: return .enableSearch
        case .openAI: return .openAIWebSearch
        case .deepSeek: return .none
        case .openRouter: return .onlineSuffix
        case .custom: return .none
        }
    }

    var allowedSearchStrategies: [AISearchStrategy] {
        self == .custom ? AISearchStrategy.allCases : [defaultSearchStrategy]
    }

    func defaultConfig(apiKey: String = "") -> AIConfig {
        AIConfig(
            platform: self,
            endpoint: defaultEndpoint,
            apiKey: apiKey,
            model: recommendedModel,
            searchStrategy: defaultSearchStrategy
        )
    }
}

struct AIConfig: Equatable, Sendable {
    var platform: AIPlatformPreset
    var endpoint: URL
    private(set) var apiKey: String
    private(set) var apiKeyDestinationID: String?
    private(set) var apiKeyCredentialID: String?
    var model: String
    var searchStrategy: AISearchStrategy
    var verifiedSearchConfigurationID: String?

    init(
        platform: AIPlatformPreset,
        endpoint: URL,
        apiKey: String,
        model: String,
        searchStrategy: AISearchStrategy,
        verifiedSearchConfigurationID: String? = nil,
        apiKeyDestinationID: String? = nil,
        apiKeyCredentialID: String? = nil
    ) {
        self.platform = platform
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.searchStrategy = searchStrategy
        self.verifiedSearchConfigurationID = verifiedSearchConfigurationID
        self.apiKeyDestinationID = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : apiKeyDestinationID ?? Self.destinationID(platform: platform, endpoint: endpoint)
        self.apiKeyCredentialID = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : apiKeyCredentialID ?? UUID().uuidString
    }

    var credentialDestinationID: String {
        Self.destinationID(platform: platform, endpoint: endpoint)
    }

    mutating func replaceAPIKey(_ value: String) {
        apiKey = value
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            apiKeyDestinationID = nil
            apiKeyCredentialID = nil
        } else {
            apiKeyDestinationID = credentialDestinationID
            apiKeyCredentialID = UUID().uuidString
        }
    }

    mutating func restoreAPIKey(_ credential: AIStoredCredential) {
        guard credential.destinationID == credentialDestinationID,
              !credential.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        apiKey = credential.apiKey
        apiKeyDestinationID = credential.destinationID
        apiKeyCredentialID = credential.credentialID
    }

    mutating func discardAPIKeyIfDestinationChanged() {
        guard apiKeyDestinationID != nil,
              apiKeyDestinationID != credentialDestinationID else { return }
        apiKey = ""
        apiKeyDestinationID = nil
        apiKeyCredentialID = nil
    }

    private static func destinationID(platform: AIPlatformPreset, endpoint: URL) -> String {
        [platform.rawValue, endpoint.absoluteString].joined(separator: "\n")
    }

    var searchConfigurationID: String {
        [
            platform.rawValue,
            endpoint.absoluteString,
            model.trimmingCharacters(in: .whitespacesAndNewlines),
            searchStrategy.rawValue,
            apiKeyCredentialID ?? "no-credential"
        ].joined(separator: "\n")
    }

    var isConnectionTestable: Bool {
        (try? AIEndpointPolicy.validate(endpoint)) != nil
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && apiKeyDestinationID == credentialDestinationID
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && searchStrategy != .none
            && platform.allowedSearchStrategies.contains(searchStrategy)
    }

    var isAvailable: Bool {
        isConnectionTestable
            && (usesRecommendedPreset
                || verifiedSearchConfigurationID == searchConfigurationID)
    }

    private var usesRecommendedPreset: Bool {
        platform != .custom
            && endpoint == platform.defaultEndpoint
            && model.trimmingCharacters(in: .whitespacesAndNewlines) == platform.recommendedModel
            && searchStrategy == platform.defaultSearchStrategy
    }
}

struct AIStoredCredential: Codable, Equatable, Sendable {
    let apiKey: String
    let destinationID: String
    let credentialID: String
}

enum AISettingsConfigBuilder {
    static func makeConfig(
        platform: AIPlatformPreset,
        endpoint: URL,
        model: String,
        searchStrategy: AISearchStrategy,
        enteredAPIKey: String,
        savedCredential: AIStoredCredential?,
        pendingCredentialID: String?,
        verifiedSearchConfigurationID: String?
    ) throws -> AIConfig {
        try AIEndpointPolicy.validate(endpoint)
        let enteredAPIKey = enteredAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var config = AIConfig(
            platform: platform,
            endpoint: endpoint,
            apiKey: enteredAPIKey,
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            searchStrategy: searchStrategy,
            verifiedSearchConfigurationID: verifiedSearchConfigurationID,
            apiKeyCredentialID: enteredAPIKey.isEmpty ? nil : pendingCredentialID
        )
        if enteredAPIKey.isEmpty, let savedCredential {
            config.restoreAPIKey(savedCredential)
        }
        return config
    }
}

protocol AISecretStore: Sendable {
    func loadCredential() -> AIStoredCredential?
    func saveCredential(_ credential: AIStoredCredential) -> Bool
    func deleteCredential() -> Bool
}

struct KeychainAISecretStore: AISecretStore {
    func loadCredential() -> AIStoredCredential? {
        guard let value = KeychainService.loadString(key: KeychainService.aiApiKey),
              let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AIStoredCredential.self, from: data)
    }

    func saveCredential(_ credential: AIStoredCredential) -> Bool {
        guard let data = try? JSONEncoder().encode(credential),
              let value = String(data: data, encoding: .utf8) else { return false }
        return KeychainService.save(key: KeychainService.aiApiKey, string: value)
    }

    func deleteCredential() -> Bool {
        KeychainService.delete(key: KeychainService.aiApiKey)
    }
}

struct AIConfigStore {
    static let shared = AIConfigStore()
    private static let persistenceLock = NSLock()

    enum ConditionalSaveResult: Equatable {
        case saved
        case configurationChanged
        case failed
    }

    private enum Keys {
        static let platform = "ai.platform"
        static let endpoint = "ai.endpoint"
        static let model = "ai.model"
        static let searchStrategy = "ai.search_strategy"
        static let verifiedSearchConfigurationID = "ai.verified_search_configuration_id"
        static let revision = "ai.configuration_revision"
    }

    private let defaults: UserDefaults
    private let secretStore: any AISecretStore

    init(
        defaults: UserDefaults = .standard,
        secretStore: any AISecretStore = KeychainAISecretStore()
    ) {
        self.defaults = defaults
        self.secretStore = secretStore
    }

    func load() -> AIConfig {
        Self.persistenceLock.withLock {
            loadUnlocked()
        }
    }

    func revision() -> Int {
        Self.persistenceLock.withLock {
            defaults.integer(forKey: Keys.revision)
        }
    }

    private func loadUnlocked() -> AIConfig {
        let platform = defaults.string(forKey: Keys.platform)
            .flatMap(AIPlatformPreset.init(rawValue:)) ?? .bailian
        let endpoint = defaults.string(forKey: Keys.endpoint)
            .flatMap(URL.init(string:)) ?? platform.defaultEndpoint
        let model = defaults.string(forKey: Keys.model) ?? platform.recommendedModel
        let strategy = defaults.string(forKey: Keys.searchStrategy)
            .flatMap(AISearchStrategy.init(rawValue:)) ?? platform.defaultSearchStrategy
        var config = AIConfig(
            platform: platform,
            endpoint: endpoint,
            apiKey: "",
            model: model,
            searchStrategy: strategy,
            verifiedSearchConfigurationID: defaults.string(forKey: Keys.verifiedSearchConfigurationID)
        )
        if let credential = secretStore.loadCredential() {
            config.restoreAPIKey(credential)
        }
        return config
    }

    @discardableResult
    func save(_ config: AIConfig) -> Bool {
        Self.persistenceLock.withLock {
            saveUnlocked(config)
        }
    }

    func save(
        _ config: AIConfig,
        ifRevisionMatches expectedRevision: Int
    ) -> ConditionalSaveResult {
        Self.persistenceLock.withLock {
            guard defaults.integer(forKey: Keys.revision) == expectedRevision else {
                return .configurationChanged
            }
            return saveUnlocked(config) ? .saved : .failed
        }
    }

    private func saveUnlocked(_ config: AIConfig) -> Bool {
        guard (try? AIEndpointPolicy.validate(config.endpoint)) != nil else { return false }
        let revision = defaults.integer(forKey: Keys.revision)
        guard revision < Int.max else { return false }
        let key = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.isEmpty || config.apiKeyDestinationID == config.credentialDestinationID else {
            return false
        }
        let previousCredential = secretStore.loadCredential()
        let keySaved: Bool
        if key.isEmpty {
            keySaved = secretStore.deleteCredential()
        } else if let credentialID = config.apiKeyCredentialID {
            keySaved = secretStore.saveCredential(AIStoredCredential(
                apiKey: key,
                destinationID: config.credentialDestinationID,
                credentialID: credentialID
            ))
        } else {
            return false
        }
        guard keySaved else {
            if let previousCredential {
                _ = secretStore.saveCredential(previousCredential)
            } else {
                _ = secretStore.deleteCredential()
            }
            return false
        }

        defaults.set(config.platform.rawValue, forKey: Keys.platform)
        defaults.set(config.endpoint.absoluteString, forKey: Keys.endpoint)
        defaults.set(config.model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.model)
        defaults.set(config.searchStrategy.rawValue, forKey: Keys.searchStrategy)
        if config.verifiedSearchConfigurationID == config.searchConfigurationID {
            defaults.set(
                config.verifiedSearchConfigurationID,
                forKey: Keys.verifiedSearchConfigurationID
            )
        } else {
            defaults.removeObject(forKey: Keys.verifiedSearchConfigurationID)
        }
        defaults.set(revision + 1, forKey: Keys.revision)
        return true
    }
}

/// 向所有补全入口发布同一份 AI 可用状态。
/// 配置页保存后刷新此对象，已展示的添加、编辑和批量页会立即更新。
@MainActor
@Observable
final class AIConfigAvailability {
    static let shared = AIConfigAvailability()

    private let store: AIConfigStore
    private(set) var isAvailable: Bool

    init(store: AIConfigStore = .shared) {
        self.store = store
        self.isAvailable = store.load().isAvailable
    }

    func refresh() {
        isAvailable = store.load().isAvailable
    }
}
