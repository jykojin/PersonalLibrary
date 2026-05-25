import SwiftUI

/// 微信读书 Skill API Key 配置视图
struct WeReadSkillSetupView: View {
    @Environment(\.dismiss) private var dismiss

    let skillService: WeReadSkillProvider
    let onSuccess: () -> Void

    @State private var apiKey = ""
    @State private var isValidating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("wrk-xxxxxxxx", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("API Key")
                } footer: {
                    Text("从微信读书 Skill 平台获取，格式为 wrk- 开头")
                }

                Section {
                    Button {
                        Task { await validateAndSave() }
                    } label: {
                        HStack {
                            Spacer()
                            if isValidating {
                                ProgressView()
                                    .controlSize(.small)
                                Text("验证中...")
                            } else {
                                Text("验证并保存")
                            }
                            Spacer()
                        }
                    }
                    .disabled(apiKey.isEmpty || !apiKey.hasPrefix("wrk-") || isValidating)
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("配置 Skill API")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func validateAndSave() async {
        isValidating = true
        errorMessage = nil
        defer { isValidating = false }

        await skillService.setApiKey(apiKey)

        do {
            let valid = try await skillService.validateApiKey()
            if valid {
                onSuccess()
                dismiss()
            } else {
                errorMessage = "API Key 无效，请检查后重试"
                await skillService.disconnect()
            }
        } catch {
            errorMessage = "验证失败: \(error.localizedDescription)"
            await skillService.disconnect()
        }
    }
}
