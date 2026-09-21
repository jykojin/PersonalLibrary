import SwiftUI
import SwiftData

struct AISettingsView: View {
    private let store: AIConfigStore
    private let availability: AIConfigAvailability

    @State private var platform: AIPlatformPreset
    @State private var endpointText: String
    @State private var model: String
    @State private var searchStrategy: AISearchStrategy
    @State private var apiKeyInput = ""
    @State private var savedAPIKey: String
    @State private var savedAPIKeyDestinationID: String?
    @State private var savedAPIKeyCredentialID: String?
    @State private var pendingAPIKeyCredentialID: String?
    @State private var verifiedSearchConfigurationID: String?
    @State private var models: [AIModelOption] = []
    @State private var isLoadingModels = false
    @State private var isTesting = false
    @State private var connectionTestTask: Task<Void, Never>?
    @State private var message: String?

    init() {
        self.init(store: .shared, availability: .shared)
    }

    init(store: AIConfigStore, availability: AIConfigAvailability) {
        self.store = store
        self.availability = availability
        let config = store.load()
        _platform = State(initialValue: config.platform)
        _endpointText = State(initialValue: config.endpoint.absoluteString)
        _model = State(initialValue: config.model)
        _searchStrategy = State(initialValue:
            config.platform.allowedSearchStrategies.contains(config.searchStrategy)
                ? config.searchStrategy
                : config.platform.defaultSearchStrategy
        )
        _savedAPIKey = State(initialValue: config.apiKey)
        _savedAPIKeyDestinationID = State(initialValue: config.apiKeyDestinationID)
        _savedAPIKeyCredentialID = State(initialValue: config.apiKeyCredentialID)
        _pendingAPIKeyCredentialID = State(initialValue: nil)
        _verifiedSearchConfigurationID = State(initialValue: config.verifiedSearchConfigurationID)
    }

    var body: some View {
        Form {
            Section("平台") {
                Picker("AI 平台", selection: $platform) {
                    ForEach(AIPlatformPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .onChange(of: platform) { _, preset in
                    endpointText = preset.defaultEndpoint.absoluteString
                    model = preset.recommendedModel
                    searchStrategy = preset.defaultSearchStrategy
                    verifiedSearchConfigurationID = nil
                    models = []
                    apiKeyInput = ""
                    pendingAPIKeyCredentialID = nil
                    message = nil
                }

                TextField("接口地址", text: $endpointText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: endpointText) { _, _ in
                        refreshPendingCredentialID()
                    }

                SecureField(canReuseSavedAPIKey ? "API Key（已保存，留空则不修改）" : "API Key", text: $apiKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: apiKeyInput) { _, _ in
                        refreshPendingCredentialID()
                    }
            }
            .disabled(isTesting)

            Section("模型与联网") {
                TextField("模型 ID", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isTesting)

                if !models.isEmpty {
                    Picker("已读取模型", selection: $model) {
                        ForEach(models) { option in
                            Text(option.id == platform.recommendedModel
                                ? "\(option.id)（推荐）"
                                : option.id)
                                .tag(option.id)
                        }
                    }
                    .disabled(isTesting)
                }

                Text(modelSpeedHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("联网方式", selection: $searchStrategy) {
                    ForEach(platform.allowedSearchStrategies, id: \.self) { strategy in
                        Text(strategy.displayName).tag(strategy)
                    }
                }
                .disabled(isTesting)

                if searchStrategy == .none {
                    Label("未启用联网检索时，AI 智能补全不可用。", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button {
                    Task { await loadModels() }
                } label: {
                    Label(isLoadingModels ? "正在读取…" : "读取模型列表", systemImage: "list.bullet")
                }
                .disabled(isLoadingModels || isTesting)

                Button {
                    startConnectionTest()
                } label: {
                    Label(isTesting ? "正在测试…" : "测试连接与联网能力", systemImage: "network")
                }
                .disabled(isLoadingModels || isTesting || searchStrategy == .none)
            }

            Section {
                Button("保存设置") { save() }
                    .frame(maxWidth: .infinity)
                    .disabled(isTesting)

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.hasPrefix("已") || message.hasPrefix("连接成功") ? .green : .red)
                }
            } footer: {
                Text("AI 补全和微信读书自动生成 AI简介会调用所选平台并消耗 token。书名、作者、已有简介以及可能的评分和备注会作为调研原料发送给该平台。\(AIResearchSourceValidator.verificationDisclaimer)")
            }
        }
        .navigationTitle("AI 智能补全")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            connectionTestTask?.cancel()
            connectionTestTask = nil
        }
    }

    private func currentConfig() throws -> AIConfig {
        guard let endpoint = URL(string: endpointText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw AIEndpointPolicyError.missingHost
        }
        let enteredKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let pendingCredentialID: String?
        if enteredKey.isEmpty {
            pendingCredentialID = nil
        } else if let existing = pendingAPIKeyCredentialID {
            pendingCredentialID = existing
        } else {
            let created = UUID().uuidString
            pendingAPIKeyCredentialID = created
            pendingCredentialID = created
        }
        let savedCredential: AIStoredCredential?
        if let destinationID = savedAPIKeyDestinationID,
           let credentialID = savedAPIKeyCredentialID {
            savedCredential = AIStoredCredential(
                apiKey: savedAPIKey,
                destinationID: destinationID,
                credentialID: credentialID
            )
        } else {
            savedCredential = nil
        }
        return try AISettingsConfigBuilder.makeConfig(
            platform: platform,
            endpoint: endpoint,
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            searchStrategy: searchStrategy,
            enteredAPIKey: enteredKey,
            savedCredential: savedCredential,
            pendingCredentialID: pendingCredentialID,
            verifiedSearchConfigurationID: verifiedSearchConfigurationID
        )
    }

    private func refreshPendingCredentialID() {
        let enteredKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if enteredKey.isEmpty {
            pendingAPIKeyCredentialID = nil
            if !canReuseSavedAPIKey {
                verifiedSearchConfigurationID = nil
            }
        } else {
            pendingAPIKeyCredentialID = UUID().uuidString
            verifiedSearchConfigurationID = nil
        }
    }

    private var canReuseSavedAPIKey: Bool {
        guard !savedAPIKey.isEmpty,
              let endpoint = URL(string: endpointText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        let config = AIConfig(
            platform: platform,
            endpoint: endpoint,
            apiKey: savedAPIKey,
            model: model,
            searchStrategy: searchStrategy,
            apiKeyDestinationID: savedAPIKeyDestinationID,
            apiKeyCredentialID: savedAPIKeyCredentialID
        )
        return config.apiKeyDestinationID == config.credentialDestinationID
    }

    private var modelSpeedHint: String {
        let recommended = platform.recommendedModel
        guard !recommended.isEmpty else {
            return "模型会影响联网检索速度；大型或深度思考模型通常更慢。"
        }
        return "模型会影响联网检索速度；建议优先使用 \(recommended)，大型或深度思考模型通常更慢。"
    }

    private func save() {
        do {
            let config = try currentConfig()
            guard store.save(config) else {
                message = "保存失败，请检查接口地址或 Keychain 权限"
                return
            }
            savedAPIKey = config.apiKey
            savedAPIKeyDestinationID = config.apiKeyDestinationID
            savedAPIKeyCredentialID = config.apiKeyCredentialID
            apiKeyInput = ""
            pendingAPIKeyCredentialID = nil
            availability.refresh()
            message = config.isAvailable
                ? "已安全保存"
                : "已安全保存；当前模型需先通过联网测试"
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func loadModels() async {
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            let config = try currentConfig()
            let loaded = try await OpenAICompatibleAIClient().listModels(config: config)
            models = loaded
            message = loaded.isEmpty ? "平台未返回模型列表，可手动输入模型 ID" : "已读取 \(loaded.count) 个模型"
        } catch {
            message = "读取失败：\(error.localizedDescription)；仍可手动输入模型 ID"
        }
    }

    @MainActor
    private func startConnectionTest() {
        guard connectionTestTask == nil else { return }
        do {
            let baselineRevision = store.revision()
            let config = try currentConfig()
            isTesting = true
            connectionTestTask = Task {
                await testConnection(
                    config,
                    expectedStoreRevision: baselineRevision
                )
            }
        } catch {
            message = "连接失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func testConnection(
        _ config: AIConfig,
        expectedStoreRevision: Int
    ) async {
        defer {
            isTesting = false
            connectionTestTask = nil
        }
        do {
            let verified = try await AIConnectionTestService(store: store).testAndSave(
                config,
                expectedStoreRevision: expectedStoreRevision
            )
            verifiedSearchConfigurationID = verified.verifiedSearchConfigurationID
            savedAPIKey = verified.apiKey
            savedAPIKeyDestinationID = verified.apiKeyDestinationID
            savedAPIKeyCredentialID = verified.apiKeyCredentialID
            apiKeyInput = ""
            pendingAPIKeyCredentialID = nil
            availability.refresh()
            message = "连接成功，已验证联网能力并安全保存"
        } catch is CancellationError {
            return
        } catch {
            message = "连接失败：\(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack { AISettingsView() }
        .modelContainer(
            for: [Book.self, Bookshelf.self, Tag.self, ReadingRecord.self, ImportRecord.self],
            inMemory: true
        )
}
