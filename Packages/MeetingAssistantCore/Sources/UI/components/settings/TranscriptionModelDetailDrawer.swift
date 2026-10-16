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
            headerIdentity: ModelIdentityView(
                title: descriptor.displayName,
                subtitle: descriptor.providerDisplayName,
                brand: identity.brand,
                host: identity.host,
                fallbackSymbolName: descriptor.iconSystemName,
                size: .row
            ),
            onClose: onClose,
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        DrawerHeroView(viewModel: viewModel, descriptor: descriptor, brand: identity.brand, host: identity.host)
                        Divider()
                        DrawerMetadataGrid(descriptor: descriptor, usageSummary: usageSummaryText)
                        Divider()
                        DrawerCapabilities(descriptor: descriptor)
                        Divider()
                        actionsSection
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        )
    }

    private var identity: (brand: ModelBrand?, host: ModelBrand?) {
        ModelBrand.identity(for: descriptor.provider, modelID: descriptor.modelID)
    }

    @ViewBuilder
    private var actionsSection: some View {
        if descriptor.localModel != nil {
            localModelSection
        } else {
            DrawerApiKeyCard(viewModel: viewModel, descriptor: descriptor)
        }
    }

    private var localModelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DrawerEyebrow(title: "settings.models.local_models.title".localized)
            DSCard(style: .settings) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("settings.models.local_models.description".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let localModel = descriptor.localModel {
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
                    }
                    if let errorMessage = viewModel.localModelActionErrorMessage {
                        DSCallout(kind: .error, title: "common.error".localized, message: errorMessage)
                    }
                }
            }
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

private func drawerTintedBackground(tint: Color) -> some View {
    let shape = RoundedRectangle(
        cornerRadius: AppDesignSystem.Layout.cardCornerRadius,
        style: .continuous
    )
    return shape.fill(tint.opacity(0.1)).overlay(shape.stroke(tint.opacity(0.25), lineWidth: 1))
}

private struct DrawerEyebrow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct DrawerHeroView: View {
    @ObservedObject var viewModel: ServiceSettingsViewModel
    let descriptor: ServiceSettingsViewModel.CatalogModelDescriptor
    let brand: ModelBrand?
    let host: ModelBrand?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            BrandAvatar(
                brand: brand,
                badgeBrand: host,
                fallbackSymbolName: descriptor.iconSystemName,
                size: 40,
                glyphSize: 22
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(descriptor.displayName)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(descriptor.providerDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    DSBadge(statusText, kind: statusKind)
                }
            }
        }
        .padding(14)
        .background(drawerTintedBackground(tint: brand?.logoBackgroundColor ?? AppDesignSystem.Colors.accent))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(descriptor.displayName), \(descriptor.providerDisplayName), \(statusText)")
    }

    private var statusText: String {
        viewModel.catalogModelStatusText(descriptor)
    }

    /// Pill kind mirrors `catalogModelStatusColor`: success → success,
    /// warning → warning, error → error, anything else → neutral.
    private var statusKind: DSBadge.Kind {
        if let localModel = descriptor.localModel {
            if viewModel.isLocalModelLoaded(localModel) {
                return .success
            }
            if viewModel.isLocalModelBusy(localModel) {
                if viewModel.modelState == .downloading || viewModel.modelState == .loading {
                    return .warning
                }
                if viewModel.modelState == .error {
                    return .error
                }
            }
            if viewModel.isLocalModelInstalled(localModel) {
                return .success
            }
            return .neutral
        }
        return descriptor.isProviderReady ? .success : .warning
    }
}

private struct DrawerMetadataGrid: View {
    let descriptor: ServiceSettingsViewModel.CatalogModelDescriptor
    let usageSummary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DrawerEyebrow(title: "settings.models.drawer.overview.title".localized)
            DSCard(style: .settings) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        cell(label: "settings.service.transcription_provider.provider".localized) {
                            HStack(spacing: 6) {
                                BrandAvatar(
                                    brand: descriptor.provider.brand,
                                    fallbackSymbolName: descriptor.iconSystemName,
                                    size: 16,
                                    glyphSize: 10
                                )
                                Text(descriptor.providerDisplayName).font(.callout).lineLimit(1)
                            }
                        }
                        cell(label: "settings.models.drawer.execution_type".localized) {
                            Text(
                                descriptor.isLocal
                                    ? "settings.models.drawer.execution_type.local".localized
                                    : "settings.models.drawer.execution_type.cloud".localized
                            )
                            .font(.callout)
                        }
                    }
                    Divider()
                    HStack(alignment: .top, spacing: 12) {
                        cell(label: "settings.models.drawer.model_id".localized) {
                            HStack(spacing: 6) {
                                Text(descriptor.modelID)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(descriptor.modelID, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc").font(.caption).foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("common.copy".localized)
                                .help("common.copy".localized)
                            }
                        }
                        cell(label: "settings.models.drawer.usage".localized) {
                            Text(usageSummary)
                                .font(.callout)
                                .foregroundStyle(descriptor.isInUse ? .primary : .secondary)
                        }
                    }
                }
            }
        }
    }

    private func cell(label: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DrawerCapabilities: View {
    let descriptor: ServiceSettingsViewModel.CatalogModelDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DrawerEyebrow(title: "settings.models.drawer.capabilities.title".localized)
            DSCard(style: .settings) {
                VStack(alignment: .leading, spacing: 8) {
                    if descriptor.isLocal {
                        chip(
                            title: "settings.models.local_models.capability.incremental".localized,
                            isSupported: descriptor.supportsIncrementalTranscription
                        )
                        chip(
                            title: "settings.models.local_models.capability.diarization".localized,
                            isSupported: descriptor.supportsDiarization
                        )
                        chip(
                            title: "settings.models.local_models.capability.basic".localized,
                            isSupported: descriptor.isLocal
                        )
                    } else {
                        chip(title: "settings.models.catalog.capability.cloud".localized, isSupported: true)
                    }
                }
            }
        }
    }

    private func chip(title: String, isSupported: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isSupported ? "checkmark.circle" : "minus.circle")
                .foregroundStyle(isSupported ? AppDesignSystem.Colors.success : .secondary)
                .accessibilityHidden(true)
            Text(title).font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(Capsule().stroke(AppDesignSystem.Colors.separator.opacity(0.4), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(title), \(isSupported ? "settings.models.drawer.capability.supported".localized : "settings.models.drawer.capability.unsupported".localized)"
        )
    }
}

private struct DrawerApiKeyCard: View {
    @ObservedObject var viewModel: ServiceSettingsViewModel
    let descriptor: ServiceSettingsViewModel.CatalogModelDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DrawerEyebrow(title: "settings.ai.api_key".localized)
            VStack(alignment: .leading, spacing: 10) {
                if isSharedKeyReady {
                    successFields
                } else {
                    keyFields
                }
            }
            .padding(14)
            .background(drawerTintedBackground(tint: cardTint))
            if let url = descriptor.apiKeyURL {
                apiKeyLinkRow(url: url)
            }
        }
    }

    private var isSharedKeyReady: Bool {
        descriptor.usesSharedCredential && descriptor.isProviderReady
    }

    private var cardTint: Color {
        if isSharedKeyReady {
            return AppDesignSystem.Colors.success
        }
        if descriptor.isProviderReady {
            return .secondary
        }
        return AppDesignSystem.Colors.warning
    }

    private var successFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(AppDesignSystem.Colors.success)
                    .accessibilityHidden(true)
                Text("settings.models.cloud_models.provider_ready".localized)
                    .font(.callout.bold())
            }
            Text("settings.ai.keychain_secure".localized).font(.caption).foregroundStyle(.secondary)
            Text("settings.models.drawer.shared_key.saved".localized).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var keyFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            if descriptor.isProviderReady {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(AppDesignSystem.Colors.success)
                        .accessibilityHidden(true)
                    Text("settings.ai.keychain_secure".localized).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(
                    "settings.service.transcription_provider.missing_key.message".localized(
                        with: descriptor.providerDisplayName
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if descriptor.usesSharedCredential {
                    Text("settings.models.drawer.shared_key.new".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                SecureField("settings.ai.api_key_placeholder".localized, text: apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                Button("common.save".localized) {
                    viewModel.saveTranscriptionAPIKey(apiKeyInput.wrappedValue, for: descriptor.provider)
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyInput.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let errorMessage = viewModel.transcriptionAPIKeyErrorMessage, !errorMessage.isEmpty {
                Text(errorMessage).font(.caption).foregroundStyle(AppDesignSystem.Colors.error)
            }
            if descriptor.isProviderReady, !descriptor.usesSharedCredential {
                Button {
                    viewModel.removeTranscriptionAPIKey(for: descriptor.provider)
                } label: {
                    Text("settings.ai.remove_key".localized)
                }
                .buttonStyle(.bordered)
                .tint(AppDesignSystem.Colors.error)
            }
        }
    }

    private func apiKeyLinkRow(url: URL) -> some View {
        let title = "settings.service.transcription_provider.get_api_key".localized(with: descriptor.providerDisplayName)
        return Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 6) {
                Text(title).font(.caption)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right").font(.caption).accessibilityHidden(true)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppDesignSystem.Colors.accent)
        .accessibilityLabel(title)
    }

    private var apiKeyInput: Binding<String> {
        Binding(
            get: { viewModel.transcriptionAPIKeyInputsByProvider[descriptor.provider.rawValue] ?? "" },
            set: { viewModel.transcriptionAPIKeyInputsByProvider[descriptor.provider.rawValue] = $0 }
        )
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
