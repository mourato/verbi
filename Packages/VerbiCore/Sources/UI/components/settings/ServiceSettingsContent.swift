import AppKit
import SwiftUI
import VerbiCoreAI
import VerbiCoreAudio
import VerbiCoreCommon
import VerbiCoreData
import VerbiCoreDomain
import VerbiCoreInfrastructure

public struct ServiceSettingsContent: View {
    @ObservedObject private var viewModel: ServiceSettingsViewModel
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
        self.viewModel = viewModel
        self.runInitialTasks = runInitialTasks
        self.includeTranscriptionProviderSection = includeTranscriptionProviderSection
        self.includeMeetingTranscriptionSection = includeMeetingTranscriptionSection
    }

    public var body: some View {
        Group {
            if includeTranscriptionProviderSection {
                ServiceTranscriptionProviderSection(viewModel: viewModel)
            }

            transcriptionModelsSection

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
        }
    }

    private var transcriptionModelsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("settings.models.transcription_models_desc".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(viewModel.catalogModels.enumerated()), id: \.element.id) { index, descriptor in
                    catalogModelRow(descriptor)
                    if index < viewModel.catalogModels.count - 1 {
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
            SettingsFormSectionHeader(title: "settings.models.transcription_models".localized, icon: "waveform")
        }
    }

    private func catalogModelRow(_ descriptor: ServiceSettingsViewModel.CatalogModelDescriptor) -> some View {
        Button {
            viewModel.selectCatalogModel(descriptor)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                let identity = ModelBrand.identity(for: descriptor.provider, modelID: descriptor.modelID)
                ModelIdentityView(
                    title: descriptor.displayName,
                    subtitle: catalogRowSubtitle(for: descriptor),
                    brand: identity.brand,
                    host: identity.host,
                    fallbackSymbolName: descriptor.iconSystemName,
                    size: .row
                )

                Spacer(minLength: 8)

                let activeContexts = activeUsageLabels(for: descriptor)
                if !activeContexts.isEmpty {
                    Text(activeContexts.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                catalogRowStatus(for: descriptor)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }

    /// Trailing status shown only when the model needs attention; ready models stay quiet.
    @ViewBuilder
    private func catalogRowStatus(for descriptor: ServiceSettingsViewModel.CatalogModelDescriptor) -> some View {
        if descriptor.isBusy {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(
                    (descriptor.isInstalled
                        ? "transcription.model_state.loading"
                        : "transcription.model_state.downloading").localized
                )
        } else if descriptor.showsRequiresKeyBadge {
            Image(systemName: "key")
                .font(.caption)
                .foregroundStyle(AppDesignSystem.Colors.warning)
                .help("settings.models.catalog.badge.requires_key".localized)
                .accessibilityLabel("settings.models.catalog.badge.requires_key".localized)
        } else if descriptor.isLocal, !descriptor.isInstalled {
            Text(viewModel.catalogModelStatusText(descriptor))
                .font(.caption)
                .foregroundStyle(viewModel.catalogModelStatusColor(descriptor))
        }
    }

    private func catalogRowSubtitle(for descriptor: ServiceSettingsViewModel.CatalogModelDescriptor) -> String {
        var parts = [descriptor.providerDisplayName]
        if descriptor.isLocal {
            if descriptor.supportsIncrementalTranscription {
                parts.append("settings.models.local_models.capability.incremental".localized)
            }
            if descriptor.supportsDiarization {
                parts.append("settings.models.local_models.capability.diarization".localized)
            }
            if !descriptor.supportsIncrementalTranscription, !descriptor.supportsDiarization {
                parts.append("settings.models.local_models.capability.basic".localized)
            }
        } else {
            parts.append("settings.models.catalog.capability.cloud".localized)
        }
        return parts.joined(separator: " · ")
    }

    private func activeUsageLabels(for descriptor: ServiceSettingsViewModel.CatalogModelDescriptor) -> [String] {
        var labels: [String] = []
        if descriptor.isUsedForDictation {
            labels.append("settings.models.drawer.usage.dictation".localized)
        }
        if descriptor.isUsedForMeetings {
            labels.append("settings.models.drawer.usage.meetings".localized)
        }
        return labels
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
        SettingsFormPage {
            EmptyView()
        } content: {
            ServiceSettingsContent(viewModel: viewModel, runInitialTasks: false)
        }
        .windowSidePanel(
            isPresented: viewModel.selectedCatalogModel != nil,
            onDismiss: { viewModel.dismissSelectedCatalogModel() },
            content: {
                if let selectedCatalogModel = viewModel.selectedCatalogModel {
                    TranscriptionModelDetailDrawer(
                        viewModel: viewModel,
                        descriptor: selectedCatalogModel,
                        onClose: { viewModel.dismissSelectedCatalogModel() }
                    )
                }
            }
        )
        .frame(width: 760, height: 640)
    }
}

#Preview("Service Settings Content") {
    ServiceSettingsContentPreview()
}
