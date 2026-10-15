import AppKit
import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct TranscriptionModelDetailDrawer: View {
    @ObservedObject private var viewModel: ServiceSettingsViewModel
    private let descriptor: ServiceSettingsViewModel.CatalogModelDescriptor
    private let onClose: () -> Void

    public init(
        viewModel: ServiceSettingsViewModel,
        descriptor: ServiceSettingsViewModel.CatalogModelDescriptor,
        onClose: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.descriptor = descriptor
        self.onClose = onClose
    }

    public var body: some View {
        ModeEditorDrawer(
            headerStyle: .close,
            title: descriptor.displayName,
            iconSymbol: descriptor.iconSystemName,
            onClose: onClose,
            content: {
                overviewSection
                capabilitiesSection
                actionsSection
            }
        )
    }

    private var overviewSection: some View {
        Section("settings.models.drawer.overview.title".localized) {
            LabeledContent("settings.service.transcription_provider.provider".localized) {
                Text(descriptor.providerDisplayName)
            }

            LabeledContent("settings.models.drawer.execution_type".localized) {
                Text(
                    descriptor.isLocal
                        ? "settings.models.drawer.execution_type.local".localized
                        : "settings.models.drawer.execution_type.cloud".localized
                )
            }

            LabeledContent("settings.models.drawer.model_id".localized) {
                Text(descriptor.modelID)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            LabeledContent("settings.models.drawer.status".localized) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.catalogModelStatusColor(descriptor))
                        .frame(width: 7, height: 7)
                    Text(viewModel.catalogModelStatusText(descriptor))
                }
            }

            LabeledContent("settings.models.drawer.usage".localized) {
                Text(usageSummaryText)
                    .foregroundStyle(descriptor.isInUse ? .primary : .secondary)
            }
        }
    }

    private var capabilitiesSection: some View {
        Section("settings.models.drawer.capabilities.title".localized) {
            capabilityRow(
                title: "settings.models.local_models.capability.incremental".localized,
                isSupported: descriptor.supportsIncrementalTranscription
            )
            capabilityRow(
                title: "settings.models.local_models.capability.diarization".localized,
                isSupported: descriptor.supportsDiarization
            )
            capabilityRow(
                title: "settings.models.local_models.capability.basic".localized,
                isSupported: descriptor.isLocal
            )
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        if let localModel = descriptor.localModel {
            Section("settings.models.local_models.title".localized) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("settings.models.local_models.description".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if descriptor.isBusy {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(viewModel.localModelStatusText(localModel))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if descriptor.isInstalled {
                        Button(role: .destructive) {
                            viewModel.deleteLocalModel(localModel)
                        } label: {
                            Label("settings.models.local_models.remove".localized, systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            viewModel.downloadLocalModel(localModel)
                        } label: {
                            Label("settings.models.local_models.download".localized, systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if let errorMessage = viewModel.localModelActionErrorMessage {
                        DSCallout(
                            kind: .error,
                            title: "common.error".localized,
                            message: errorMessage
                        )
                    }
                }
            }
        } else {
            Section("settings.ai.api_key".localized) {
                VStack(alignment: .leading, spacing: 12) {
                    if descriptor.isProviderReady {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(AppDesignSystem.Colors.success)
                                .accessibilityHidden(true)
                            Text("settings.ai.keychain_secure".localized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(
                            "settings.service.transcription_provider.missing_key.message".localized(
                                with: descriptor.providerDisplayName
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        SecureField(
                            "settings.ai.api_key_placeholder".localized,
                            text: Binding(
                                get: { viewModel.transcriptionAPIKeyInputsByProvider[descriptor.provider.rawValue] ?? "" },
                                set: { viewModel.transcriptionAPIKeyInputsByProvider[descriptor.provider.rawValue] = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)

                        Button("common.save".localized) {
                            viewModel.saveTranscriptionAPIKey(
                                viewModel.transcriptionAPIKeyInputsByProvider[descriptor.provider.rawValue] ?? "",
                                for: descriptor.provider
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            (viewModel.transcriptionAPIKeyInputsByProvider[descriptor.provider.rawValue] ?? "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )
                    }

                    if let errorMessage = viewModel.transcriptionAPIKeyErrorMessage,
                       !errorMessage.isEmpty
                    {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(AppDesignSystem.Colors.error)
                    }

                    HStack(spacing: 8) {
                        if descriptor.isProviderReady {
                            Button {
                                viewModel.removeTranscriptionAPIKey(for: descriptor.provider)
                            } label: {
                                Text("settings.ai.remove_key".localized)
                            }
                            .buttonStyle(.bordered)
                            .tint(AppDesignSystem.Colors.error)
                        }

                        if let url = descriptor.apiKeyURL {
                            Button("settings.service.transcription_provider.get_api_key".localized(with: descriptor.providerDisplayName)) {
                                NSWorkspace.shared.open(url)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private func capabilityRow(title: String, isSupported: Bool) -> some View {
        LabeledContent(title) {
            Text(
                isSupported
                    ? "settings.models.drawer.capability.supported".localized
                    : "settings.models.drawer.capability.unsupported".localized
            )
            .foregroundStyle(isSupported ? .primary : .secondary)
        }
    }

    private var usageSummaryText: String {
        var contexts: [String] = []
        if descriptor.isUsedForDictation {
            contexts.append("settings.models.drawer.usage.dictation".localized)
        }
        if descriptor.isUsedForMeetings {
            contexts.append("settings.models.drawer.usage.meetings".localized)
        }
        guard !contexts.isEmpty else {
            return "settings.models.drawer.usage.none".localized
        }
        return contexts.joined(separator: ", ")
    }
}

#Preview("Transcription Model Detail Drawer") {
    let viewModel = ServiceSettingsViewModel()
    if let descriptor = viewModel.catalogModels.first {
        TranscriptionModelDetailDrawer(
            viewModel: viewModel,
            descriptor: descriptor,
            onClose: {}
        )
        .frame(width: 480, height: 540)
    }
}
