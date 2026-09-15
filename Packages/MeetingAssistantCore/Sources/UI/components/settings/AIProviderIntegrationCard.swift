import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

/// A unified card for configuring AI provider settings, including status indicators and verification.
public struct AIProviderIntegrationCard: View {
    @ObservedObject var viewModel: AISettingsViewModel
    private let runInitialTasks: Bool

    /// Binding that properly triggers persistence when selectedModel changes.
    /// Using direct struct mutation ($viewModel.settings.aiConfiguration.selectedModel)
    /// does NOT trigger @Published didSet because structs are value types.
    private var selectedModelBinding: Binding<String> {
        Binding(
            get: { viewModel.settings.aiConfiguration.selectedModel },
            set: { newValue in
                viewModel.settings.updateSelectedModel(newValue)
            }
        )
    }

    public init(
        viewModel: AISettingsViewModel,
        runInitialTasks: Bool = !PreviewRuntime.isRunning
    ) {
        self.viewModel = viewModel
        self.runInitialTasks = runInitialTasks
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AppDesignSystem.Layout.itemSpacing) {
            Text("settings.ai.api_config".localized)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 8) {
                providerRow
                apiKeyRow
                modelRow
                if viewModel.settings.aiConfiguration.provider == .custom {
                    baseURLRow
                }

                if let detail = viewModel.connectionStatus.detail, !detail.isEmpty, viewModel.connectionStatus != .success {
                    connectionDetailRow(detail)
                }

                if let actionError = viewModel.actionError {
                    actionErrorRow(actionError)
                }
                footerActions
            }
        }
        .task {
            guard runInitialTasks else { return }
            viewModel.refreshProviderCredentialState()
        }
    }

    // MARK: - Rows

    private var providerRow: some View {
        LabeledContent("settings.ai.provider".localized) {
            HStack(spacing: 8) {
                if viewModel.connectionStatus == .success || viewModel.connectionStatus == .saved {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.connectionStatus.color)
                            .frame(width: 8, height: 8)
                        Text(viewModel.connectionStatus.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("", selection: $viewModel.settings.aiConfiguration.provider) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.settings.aiConfiguration.provider) { _, newProvider in
                    if newProvider != .custom {
                        viewModel.settings.aiConfiguration.baseURL = newProvider.defaultBaseURL
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var modelRow: some View {
        LabeledContent("settings.ai.model".localized) {
            HStack {
                if viewModel.settings.aiConfiguration.provider == .custom {
                    TextField(
                        "",
                        text: $viewModel.settings.aiConfiguration.selectedModel
                    )
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: AppDesignSystem.Layout.maxCompactTextFieldWidth)
                } else {
                    if viewModel.canRefreshModels {
                        Button {
                            viewModel.refreshModelsManually()
                        } label: {
                            if viewModel.isLoadingModels {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.6)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .accessibilityLabel("settings.ai.model_refresh".localized)
                                    .fontWeight(.medium)
                            }
                        }
                        .controlSize(.regular)
                        .buttonStyle(.borderless)
                        .disabled(viewModel.isLoadingModels || viewModel.connectionStatus == .testing)
                    }

                    Picker("", selection: selectedModelBinding) {
                        if viewModel.isLoadingModels {
                            Text("settings.ai.loading".localized).tag("")
                        } else if viewModel.availableModels.isEmpty {
                            Text("settings.ai.no_models".localized).tag("")
                        } else {
                            Text("settings.ai.model_select".localized).tag("")
                            ForEach(viewModel.availableModels) { model in
                                Text(model.id).tag(model.id)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(viewModel.isLoadingModels || viewModel.availableModels.isEmpty)
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            modelStatusMessage
                .offset(y: 22)
        }
        .padding(.bottom, hasModelStatusMessage ? 22 : 0)
    }

    private var hasModelStatusMessage: Bool {
        viewModel.modelsRefreshSummary != nil
            || viewModel.modelCatalogStatus == .unavailable
            || (viewModel.canRefreshModels && viewModel.availableModels.isEmpty && !viewModel.isLoadingModels)
    }

    @ViewBuilder
    private var modelStatusMessage: some View {
        if let refreshSummary = viewModel.modelsRefreshSummary {
            Label(
                refreshSummary,
                systemImage: viewModel.lastModelsRefreshSucceeded
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(
                viewModel.lastModelsRefreshSucceeded
                    ? AppDesignSystem.Colors.success
                    : AppDesignSystem.Colors.warning
            )
            .font(.caption)
        } else if viewModel.modelCatalogStatus == .unavailable {
            Text("settings.ai.models.catalog_unavailable".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if viewModel.canRefreshModels, viewModel.availableModels.isEmpty, !viewModel.isLoadingModels {
            Text("settings.ai.model_hint".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var baseURLRow: some View {
        HStack {
            Text("settings.ai.base_url".localized)
                .foregroundStyle(.secondary)
            Spacer()
            TextField(
                "https://api.example.com/v1",
                text: $viewModel.settings.aiConfiguration.baseURL
            )
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
    }

    private var apiKeyRow: some View {
        HStack {
            Text("settings.ai.api_key".localized)
                .foregroundStyle(.secondary)
            Spacer()

            if viewModel.isKeySaved {
                HStack(spacing: 8) {
                    Text("settings.ai.keychain_secure".localized)
                        .font(.caption)
                        .foregroundStyle(AppDesignSystem.Colors.success)

                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(AppDesignSystem.Colors.success)

                    Button {
                        viewModel.removeAPIKey()
                    } label: {
                        Text("settings.ai.remove_key".localized)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppDesignSystem.Colors.error)
                    .controlSize(.regular)
                }
            } else {
                SecureField("settings.ai.api_key_placeholder".localized, text: $viewModel.apiKeyText)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: AppDesignSystem.Layout.maxCompactTextFieldWidth)
            }
        }
        .padding(.vertical, 8)
    }

    private func connectionDetailRow(_ detail: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppDesignSystem.Colors.warning)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 4)
    }

    private func actionErrorRow(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(AppDesignSystem.Colors.error)
            Text(error)
                .font(.caption)
                .foregroundStyle(AppDesignSystem.Colors.error)
            Spacer()
        }
        .padding(.top, 4)
    }

    private var footerActions: some View {
        HStack {
            if viewModel.showGetApiKeyButton, let url = viewModel.settings.aiConfiguration.provider.apiKeyURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "key.fill")
                        Text("settings.ai.get_api_key".localized)
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer()

            if viewModel.hasPendingAPIKeyInput {
                Button("settings.ai.save_without_verification".localized) {
                    viewModel.saveAPIKeyWithoutVerification()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            if viewModel.showVerifyButton {
                Button {
                    viewModel.testAPIConnection()
                } label: {
                    if viewModel.connectionStatus == .testing {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.6)
                    } else {
                        Text("settings.ai.verify_and_save".localized)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(!viewModel.canVerifyConnection || viewModel.connectionStatus == .testing)
            }
        }
        .padding(.top, 8)
    }
}

private struct PreviewKeychainProvider: KeychainProvider {
    func store(_: String, for _: KeychainManager.Key) throws {}
    func retrieve(for _: KeychainManager.Key) throws -> String? {
        nil
    }

    func delete(for _: KeychainManager.Key) throws {}
    func exists(for _: KeychainManager.Key) -> Bool {
        false
    }

    func retrieveAPIKey(for _: AIProvider) throws -> String? {
        nil
    }

    func existsAPIKey(for _: AIProvider) -> Bool {
        false
    }

    func storeAPIKey(_: String, for _: UUID) throws {}
    func retrieveAPIKey(for _: UUID) throws -> String? {
        nil
    }

    func retrieveAPIKeys(for _: [UUID]) throws -> [UUID: String] {
        [:]
    }

    func existsAPIKey(for _: UUID) -> Bool {
        false
    }

    func deleteAPIKey(for _: UUID) throws {}
}

private struct PreviewLLMService: LLMService {
    func validateURL(_: String) -> URL? {
        URL(string: "https://api.openai.com/v1")
    }

    func fetchAvailableModels(baseURL _: URL, apiKey _: String, provider _: AIProvider) throws -> [LLMModel] {
        []
    }

    func testConnection(baseURL _: URL, apiKey _: String, provider _: AIProvider) throws -> Bool {
        true
    }
}

@MainActor
private struct AIProviderIntegrationCardPreview: View {
    @StateObject private var viewModel: AISettingsViewModel

    init() {
        let viewModel = AISettingsViewModel(
            settings: .shared,
            keychain: PreviewKeychainProvider(),
            llmService: PreviewLLMService()
        )
        viewModel.settings.aiConfiguration.provider = .openai
        viewModel.settings.aiConfiguration.baseURL = AIProvider.openai.defaultBaseURL
        viewModel.settings.updateSelectedModel("gpt-4o-mini")
        viewModel.apiKeyText = "sk-preview-key"
        viewModel.connectionStatus = .unknown
        viewModel.availableModels = []
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        AIProviderIntegrationCard(viewModel: viewModel, runInitialTasks: false)
            .padding()
            .frame(width: 760)
    }
}

#Preview("AI Provider Integration") {
    AIProviderIntegrationCardPreview()
}
