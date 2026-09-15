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
        let isReady = readinessIssue == nil
        let isSelectedForActiveUse = isRegistrationSelectedForActiveUse(registration)

        return Button {
            beginEditRegistration(registration)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                EnhancementsProviderAvatar(
                    provider: registration.provider,
                    customIconName: registration.iconSystemName
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(registration.displayName)
                            .font(.headline)

                        if isRegistrationSelected(registration.id, in: .meeting) {
                            DSBadge("settings.enhancements.selector.meeting.title".localized, kind: .success)
                        }

                        if isRegistrationSelected(registration.id, in: .dictation) {
                            DSBadge("settings.enhancements.selector.dictation.title".localized, kind: .neutral)
                        }
                    }

                    Text(providerDescription(for: registration.provider))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(isReady ? AppDesignSystem.Colors.success : AppDesignSystem.Colors.warning)
                            .frame(width: 7, height: 7)
                        Text(
                            providerStatusText(
                                isReady: isReady,
                                issue: readinessIssue,
                                isSelectedForActiveUse: isSelectedForActiveUse
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func providerStatusText(
        isReady: Bool,
        issue: EnhancementsInferenceReadinessIssue?,
        isSelectedForActiveUse: Bool
    ) -> String {
        guard !isReady else {
            if !isSelectedForActiveUse {
                return "settings.enhancements.provider_models.status.registered".localized
            }
            return "settings.enhancements.provider_models.status.ready".localized
        }

        guard let issue else {
            return "settings.enhancements.provider_models.status.not_ready".localized
        }

        switch issue {
        case .missingModel:
            return "settings.enhancements.provider_models.status.not_ready_missing_model".localized
        case .missingAPIKey:
            return "settings.enhancements.provider_models.status.not_ready_missing_key".localized
        case .invalidBaseURL:
            return "settings.enhancements.provider_models.status.not_ready_invalid_url".localized
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
