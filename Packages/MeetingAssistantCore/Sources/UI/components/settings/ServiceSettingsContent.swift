import AppKit
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct ServiceSettingsContent: View {
    @StateObject private var viewModel: ServiceSettingsViewModel
    private let runInitialTasks: Bool
    private let includeTranscriptionProviderSection: Bool
    private let includeMeetingTranscriptionSection: Bool

    public init(
        viewModel: ServiceSettingsViewModel = ServiceSettingsViewModel(),
        settings _: AppSettingsStore = .shared,
        runInitialTasks: Bool = !PreviewRuntime.isRunning,
        includeTranscriptionProviderSection: Bool = true,
        includeMeetingTranscriptionSection: Bool = true
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.runInitialTasks = runInitialTasks
        self.includeTranscriptionProviderSection = includeTranscriptionProviderSection
        self.includeMeetingTranscriptionSection = includeMeetingTranscriptionSection
    }

    public var body: some View {
        Group {
            if includeTranscriptionProviderSection {
                ServiceTranscriptionProviderSection(viewModel: viewModel)
            }
            localModelsSection
            cloudModelsSection

            if includeMeetingTranscriptionSection,
               viewModel.shouldShowMeetingSection
            {
                ServiceMeetingTranscriptionSection(viewModel: viewModel)
            }

            runtimeSection
            statusSection
        }
        .task {
            guard runInitialTasks else { return }
            viewModel.refreshInstalledModelStates()
            viewModel.testConnection()
        }
    }

    private var localModelsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("settings.models.local_models.description".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(viewModel.localModels) { localModel in
                    localModelRow(localModel)
                    if localModel.id != viewModel.localModels.last?.id {
                        Divider()
                    }
                }

                if let errorMessage = viewModel.localModelActionErrorMessage {
                    DSCallout(
                        kind: .error,
                        title: "common.error".localized,
                        message: errorMessage
                    )
                }
            }
        } header: {
            SettingsFormSectionHeader(title: "settings.models.local_models.title".localized, icon: "internaldrive")
        }
    }

    private func localModelRow(_ descriptor: ServiceSettingsViewModel.LocalModelDescriptor) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(descriptor.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if viewModel.selectedMeetingLocalModel == descriptor.model,
                       viewModel.shouldShowMeetingSection
                    {
                        Text("settings.models.local_models.used_for_meetings".localized)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppDesignSystem.Colors.accent.opacity(0.12))
                            .foregroundStyle(AppDesignSystem.Colors.accent)
                            .clipShape(Capsule())
                    }
                }

                Text(localModelCapabilityText(descriptor))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(viewModel.localModelStatusText(descriptor.model))
                    .font(.caption2)
                    .foregroundStyle(viewModel.localModelStatusColor(descriptor.model))
            }

            Spacer()

            if viewModel.isLocalModelBusy(descriptor.model) {
                ProgressView()
                    .controlSize(.small)
            } else if viewModel.isLocalModelInstalled(descriptor.model) {
                Button(role: .destructive) {
                    viewModel.deleteLocalModel(descriptor.model)
                } label: {
                    Label("settings.models.local_models.remove".localized, systemImage: "trash")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    viewModel.downloadLocalModel(descriptor.model)
                } label: {
                    Label("settings.models.local_models.download".localized, systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var cloudModelsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Text("settings.models.cloud_models.description".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(viewModel.cloudProviders) { provider in
                    cloudProviderCard(provider)
                }
            }
        } header: {
            SettingsFormSectionHeader(title: "settings.models.cloud_models.title".localized, icon: "cloud")
        }
    }

    private func cloudProviderCard(_ provider: ServiceSettingsViewModel.CloudProviderDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(
                        provider.isReady
                            ? "settings.models.cloud_models.provider_ready".localized
                            : "settings.models.cloud_models.provider_requires_key".localized
                    )
                    .font(.caption)
                    .foregroundStyle(provider.isReady ? AppDesignSystem.Colors.success : .secondary)
                }

                Spacer()

                if viewModel.selectedDictationProvider == provider.provider {
                    Text("settings.models.cloud_models.active_provider".localized)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppDesignSystem.Colors.accent.opacity(0.12))
                        .foregroundStyle(AppDesignSystem.Colors.accent)
                        .clipShape(Capsule())
                }
            }

            cloudProviderModelRow(provider)

            if provider.provider == .elevenLabs, !provider.isReady {
                LabeledContent("settings.ai.api_key".localized) {
                    HStack(spacing: 8) {
                        SecureField(
                            "settings.ai.api_key_placeholder".localized,
                            text: Binding(
                                get: { viewModel.transcriptionAPIKeyInputsByProvider[provider.provider.rawValue] ?? "" },
                                set: { viewModel.transcriptionAPIKeyInputsByProvider[provider.provider.rawValue] = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)

                        Button("common.save".localized) {
                            viewModel.saveTranscriptionAPIKey(
                                viewModel.transcriptionAPIKeyInputsByProvider[provider.provider.rawValue] ?? "",
                                for: provider.provider
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            (viewModel.transcriptionAPIKeyInputsByProvider[provider.provider.rawValue] ?? "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )
                    }
                }
            }

            HStack(spacing: 8) {
                if provider.isReady {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(AppDesignSystem.Colors.success)
                        Text("settings.ai.keychain_secure".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        viewModel.removeTranscriptionAPIKey(for: provider.provider)
                    } label: {
                        Text("settings.ai.remove_key".localized)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppDesignSystem.Colors.error)
                } else {
                    Text(
                        "settings.service.transcription_provider.missing_key.message".localized(
                            with: provider.displayName
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if let url = provider.apiKeyURL {
                    Button("settings.service.transcription_provider.get_api_key".localized(with: provider.displayName)) {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
    }

    private var runtimeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Picker(
                        "settings.service.model_residency_timeout".localized,
                        selection: Binding(
                            get: { viewModel.modelResidencyTimeout },
                            set: { viewModel.modelResidencyTimeout = $0 }
                        )
                    ) {
                        ForEach(viewModel.modelResidencyTimeoutOptions, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("settings.service.model_residency_timeout.help".localized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("settings.service.no_internet".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            SettingsFormSectionHeader(title: "settings.models.runtime.title".localized, icon: "cpu")
        }
    }

    private var statusSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.transcriptionStatus.color)
                            .frame(width: 8, height: 8)
                        Text(viewModel.transcriptionStatus.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let detail = viewModel.transcriptionStatus.detail,
                       !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                Spacer()

                Button {
                    viewModel.testConnection()
                } label: {
                    if viewModel.transcriptionStatus == .testing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("settings.service.verify".localized, systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.transcriptionStatus == .testing)
            }
        } header: {
            SettingsFormSectionHeader(title: "settings.models.service_status".localized, icon: "dot.radiowaves.left.and.right")
        }
    }

    private func cloudProviderModelRow(_ provider: ServiceSettingsViewModel.CloudProviderDescriptor) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Picker(
                "settings.service.transcription_provider.model".localized,
                selection: Binding(
                    get: { provider.selectedModelID },
                    set: { viewModel.updateCloudProviderModel($0, for: provider.provider) }
                )
            ) {
                ForEach(provider.availableModelIDs, id: \.self) { modelID in
                    Text(viewModel.displayName(forModelID: modelID)).tag(modelID)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func localModelCapabilityText(_ descriptor: ServiceSettingsViewModel.LocalModelDescriptor) -> String {
        var capabilities: [String] = []
        if descriptor.supportsIncrementalTranscription {
            capabilities.append("settings.models.local_models.capability.incremental".localized)
        }
        if descriptor.supportsDiarization {
            capabilities.append("settings.models.local_models.capability.diarization".localized)
        }
        if capabilities.isEmpty {
            capabilities.append("settings.models.local_models.capability.basic".localized)
        }
        return capabilities.joined(separator: " · ")
    }
}

@MainActor
private struct ServiceSettingsContentPreview: View {
    @StateObject private var viewModel: ServiceSettingsViewModel

    init() {
        let viewModel = ServiceSettingsViewModel()
        viewModel.transcriptionStatus = .success
        viewModel.modelState = .loaded
        viewModel.isASRInstalled = true
        viewModel.isDiarizationLoaded = true
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ServiceSettingsContent(viewModel: viewModel, runInitialTasks: false)
            .padding()
            .frame(width: 760)
    }
}

#Preview("Service Settings Content") {
    ServiceSettingsContentPreview()
}
