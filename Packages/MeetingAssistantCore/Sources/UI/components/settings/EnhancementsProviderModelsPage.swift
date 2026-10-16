import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

// preview-check: ignore — provider models page requires the owning provider fixture.

public struct EnhancementsProviderModelsPage: View {
    struct RegistrationEditorContext: Identifiable {
        let id = UUID()
        let mode: EnhancementsProviderEditorMode
        let provider: AIProvider
        let registrationID: UUID?
    }

    @ObservedObject var viewModel: AISettingsViewModel
    @ObservedObject var postProcessingViewModel: PostProcessingSettingsViewModel

    @State var isShowingProviderPicker = false
    @State var registrationEditorContext: RegistrationEditorContext?

    @State var draftDisplayName = ""
    @State var draftBaseURL = ""
    @State var draftIconSystemName: String?
    @State var draftAPIKey = ""
    @State var draftHasSavedAPIKey = false
    @State var draftConnectionStatus: ConnectionStatus = .unknown
    @State var draftErrorMessage: String?

    public init(
        viewModel: AISettingsViewModel,
        postProcessingViewModel: PostProcessingSettingsViewModel,
        initialExpandedProvider: AIProvider? = nil
    ) {
        self.viewModel = viewModel
        self.postProcessingViewModel = postProcessingViewModel
        _ = initialExpandedProvider
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AppDesignSystem.Layout.sectionSpacing) {
            DSCallout(
                kind: .info,
                title: "settings.enhancements.provider_models.context_title".localized,
                message: "settings.enhancements.provider_models.context_desc".localized
            )

            providerRegistrationsSection
        }
        .onAppear {
            viewModel.refreshEnhancementsProviderModelsManually()
        }
        .sheet(isPresented: $isShowingProviderPicker) {
            EnhancementsProviderPickerSheet(
                registeredBuiltInProviders: registeredBuiltInProviders,
                onSelect: { provider in
                    isShowingProviderPicker = false
                    DispatchQueue.main.async {
                        beginCreateRegistration(provider)
                    }
                },
                onCancel: {
                    isShowingProviderPicker = false
                }
            )
        }
        .sheet(item: $registrationEditorContext) { context in
            EnhancementsProviderEditorSheet(
                mode: context.mode,
                provider: context.provider,
                displayName: $draftDisplayName,
                baseURL: $draftBaseURL,
                iconSystemName: $draftIconSystemName,
                apiKey: $draftAPIKey,
                hasSavedAPIKey: draftHasSavedAPIKey,
                connectionStatus: draftConnectionStatus,
                errorMessage: draftErrorMessage,
                onSave: {
                    saveRegistration(from: context, shouldTestConnection: false)
                },
                onTestAndSave: {
                    saveRegistration(from: context, shouldTestConnection: true)
                },
                onDelete: context.mode == .edit ? {
                    deleteRegistration(from: context)
                } : nil,
                onRemoveKey: {
                    removeRegistrationKey(from: context)
                },
                onCancel: {
                    registrationEditorContext = nil
                }
            )
        }
    }
}

extension EnhancementsProviderModelsPage {
    var providerRegistrationsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("settings.enhancements.providers.active_desc".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if activeRegistrations.isEmpty {
                    Text("settings.enhancements.providers.empty".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(Array(activeRegistrations.enumerated()), id: \.element.id) { index, registration in
                        registrationRow(registration)
                        if index < activeRegistrations.count - 1 {
                            Divider()
                        }
                    }
                }

                if let fetchError = viewModel.enhancementsProviderModelsFetchError,
                   !fetchError.isEmpty
                {
                    DSCallout(
                        kind: .warning,
                        title: "settings.enhancements.provider_models.error.title".localized,
                        message: fetchError
                    )
                }
            }
        } header: {
            SettingsFormSectionHeader(
                title: "settings.enhancements.providers.active_title".localized,
                icon: "square.stack.3d.up"
            ) {
                Button {
                    isShowingProviderPicker = true
                } label: {
                    Label("settings.enhancements.providers.add".localized, systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
    }

    func registrationRow(_ registration: EnhancementsProviderRegistration) -> some View {
        let readinessIssue = registrationReadinessIssue(for: registration)
        let identity = ModelBrand.identity(for: registration.provider, modelID: "")

        return Button {
            beginEditRegistration(registration)
        } label: {
            HStack(spacing: 12) {
                ModelIdentityView(
                    title: registration.displayName,
                    subtitle: providerDescription(for: registration.provider),
                    brand: identity.brand,
                    host: identity.host,
                    fallbackSymbolName: registration.iconSystemName ?? "brain.head.profile",
                    size: .row
                )

                Spacer()

                ForEach([IntelligenceKernelMode.meeting, .dictation], id: \.self) { mode in
                    if isRegistrationSelected(registration.id, in: mode) {
                        Text(mode == .meeting
                            ? "settings.enhancements.selector.meeting.title".localized
                            : "settings.enhancements.selector.dictation.title".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let readinessIssue {
                    readinessStatus(readinessIssue)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func readinessStatus(_ issue: EnhancementsInferenceReadinessIssue) -> some View {
        switch issue {
        case .missingAPIKey:
            Image(systemName: "key")
                .foregroundStyle(AppDesignSystem.Colors.warning)
                .help("settings.enhancements.provider_models.status.not_ready_missing_key".localized)
                .accessibilityLabel("settings.enhancements.provider_models.status.not_ready_missing_key".localized)
        case .missingModel, .invalidBaseURL:
            Text(issue == .missingModel
                ? "settings.enhancements.provider_models.status.not_ready_missing_model".localized
                : "settings.enhancements.provider_models.status.not_ready_invalid_url".localized)
                .font(.caption)
                .foregroundStyle(AppDesignSystem.Colors.warning)
        }
    }

    func providerDescription(for provider: AIProvider) -> String {
        switch provider {
        case .openai:
            "settings.enhancements.provider.openai.desc".localized
        case .anthropic:
            "settings.enhancements.provider.anthropic.desc".localized
        case .groq:
            "settings.enhancements.provider.groq.desc".localized
        case .google:
            "settings.enhancements.provider.google.desc".localized
        case .custom:
            "settings.enhancements.provider.custom.desc".localized
        }
    }
}

extension EnhancementsProviderModelsPage {
    var activeRegistrations: [EnhancementsProviderRegistration] {
        postProcessingViewModel.settings.enhancementsProviderRegistrations
    }

    var registeredBuiltInProviders: Set<AIProvider> {
        Set(activeRegistrations.filter { $0.provider != .custom }.map(\.provider))
    }

    func isRegistrationSelected(_ registrationID: UUID, in mode: IntelligenceKernelMode) -> Bool {
        guard let registration = postProcessingViewModel.settings.enhancementsRegistration(for: registrationID) else {
            return false
        }
        return postProcessingViewModel.settings.isEnhancementsRegistrationSelected(registration, for: mode)
    }
}
