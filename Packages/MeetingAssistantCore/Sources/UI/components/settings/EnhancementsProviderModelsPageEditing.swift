import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import SwiftUI

private struct ValidatedEditorDraft {
    let displayName: String
    let baseURL: String?
    let iconSystemName: String?
}

extension EnhancementsProviderModelsPage {
    func beginCreateRegistration(_ provider: AIProvider) {
        draftDisplayName = provider == .custom
            ? postProcessingViewModel.settings.suggestedCustomEnhancementsProviderName()
            : provider.displayName
        draftBaseURL = provider == .custom
            ? postProcessingViewModel.settings.aiConfiguration.baseURL
            : provider.defaultBaseURL
        draftIconSystemName = nil
        draftAPIKey = ""
        draftHasSavedAPIKey = viewModel.hasSavedEnhancementsAPIKey(for: nil, provider: provider)
        draftConnectionStatus = draftHasSavedAPIKey ? .saved : .unknown
        draftErrorMessage = nil

        registrationEditorContext = RegistrationEditorContext(
            mode: .create,
            provider: provider,
            registrationID: nil
        )
    }

    func beginEditRegistration(_ registration: EnhancementsProviderRegistration) {
        draftDisplayName = registration.displayName
        draftBaseURL = registration.provider == .custom ? registration.resolvedBaseURL : registration.provider.defaultBaseURL
        draftIconSystemName = registration.iconSystemName ?? registration.provider.icon
        draftAPIKey = ""
        draftHasSavedAPIKey = viewModel.hasSavedEnhancementsAPIKey(
            for: registration.id,
            provider: registration.provider
        )
        draftConnectionStatus = draftHasSavedAPIKey ? .saved : .unknown
        draftErrorMessage = nil

        registrationEditorContext = RegistrationEditorContext(
            mode: .edit,
            provider: registration.provider,
            registrationID: registration.id
        )
    }

    func saveRegistration(from context: RegistrationEditorContext, shouldTestConnection: Bool) {
        draftErrorMessage = nil

        guard let draft = validatedDraft(
            for: context.provider,
            requiresCredentialForTest: shouldTestConnection
        ) else {
            return
        }

        guard let targetRegistration = upsertRegistration(from: context, draft: draft) else {
            return
        }

        guard persistDraftCredentialIfNeeded(for: targetRegistration) else {
            return
        }

        if shouldTestConnection {
            runConnectionTest(for: targetRegistration)
            return
        }

        finalizeEditorFlow(afterEditing: targetRegistration.provider)
    }

    func removeRegistrationKey(from context: RegistrationEditorContext) {
        viewModel.removeEnhancementsAPIKey(registrationID: context.registrationID, provider: context.provider)
        draftHasSavedAPIKey = false
        draftConnectionStatus = .unknown
        draftErrorMessage = viewModel.enhancementsActionError
    }

    func deleteRegistration(from context: RegistrationEditorContext) {
        guard let registrationID = context.registrationID else { return }

        postProcessingViewModel.settings.removeEnhancementsProviderRegistration(id: registrationID)
        viewModel.refreshEnhancementsProviderModelsManually()
        registrationEditorContext = nil
        draftErrorMessage = nil
    }

    func registrationReadinessIssue(
        for registration: EnhancementsProviderRegistration
    ) -> EnhancementsInferenceReadinessIssue? {
        guard isValidHTTPURLString(registration.resolvedBaseURL) else {
            return .invalidBaseURL
        }

        guard viewModel.hasSavedEnhancementsAPIKey(
            for: registration.id,
            provider: registration.provider
        ) else {
            return .missingAPIKey
        }

        guard isRegistrationSelectedForActiveUse(registration) else {
            return nil
        }

        let selectedModel = postProcessingViewModel.settings
            .enhancementsSelectedModel(for: registration.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedModel.isEmpty else {
            return .missingModel
        }

        return nil
    }

    func isRegistrationSelectedForActiveUse(_ registration: EnhancementsProviderRegistration) -> Bool {
        isRegistrationSelected(registration.id, in: .meeting)
            || isRegistrationSelected(registration.id, in: .dictation)
    }

    func isValidHTTPURLString(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty
        else {
            return false
        }

        return true
    }

    private func upsertRegistration(
        from context: RegistrationEditorContext,
        draft: ValidatedEditorDraft
    ) -> EnhancementsProviderRegistration? {
        let settings = postProcessingViewModel.settings

        switch context.mode {
        case .create:
            guard let created = settings.addEnhancementsProviderRegistration(
                provider: context.provider,
                displayName: draft.displayName,
                baseURLOverride: draft.baseURL,
                iconSystemName: draft.iconSystemName
            ) else {
                draftErrorMessage = "settings.enhancements.providers.editor.create_failed".localized
                return nil
            }
            return created

        case .edit:
            guard let registrationID = context.registrationID,
                  var existing = settings.enhancementsRegistration(for: registrationID)
            else {
                draftErrorMessage = "settings.enhancements.providers.editor.missing_registration".localized
                return nil
            }

            existing.displayName = draft.displayName
            if existing.provider == .custom {
                existing.baseURLOverride = draft.baseURL
                existing.iconSystemName = draft.iconSystemName
            }
            settings.updateEnhancementsProviderRegistration(existing)
            return existing
        }
    }

    private func persistDraftCredentialIfNeeded(for registration: EnhancementsProviderRegistration) -> Bool {
        let normalizedDraftKey = draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDraftKey.isEmpty else { return true }

        let keySaved = viewModel.saveEnhancementsAPIKey(
            normalizedDraftKey,
            registrationID: registration.id,
            provider: registration.provider
        )

        guard keySaved else {
            draftErrorMessage = viewModel.enhancementsActionError
            return false
        }

        draftHasSavedAPIKey = true
        return true
    }

    private func runConnectionTest(for registration: EnhancementsProviderRegistration) {
        Task {
            let success = await viewModel.testEnhancementsAPIConnection(
                provider: registration.provider,
                baseURLString: registration.resolvedBaseURL,
                registrationID: registration.id,
                pendingAPIKeyInput: draftAPIKey
            )

            await MainActor.run {
                draftConnectionStatus = viewModel.enhancementsConnectionStatus
                draftErrorMessage = viewModel.enhancementsActionError ?? viewModel.enhancementsConnectionStatus.detail

                if success {
                    draftHasSavedAPIKey = true
                    finalizeEditorFlow(afterEditing: registration.provider)
                }
            }
        }
    }

    private func finalizeEditorFlow(afterEditing provider: AIProvider) {
        registrationEditorContext = nil
        draftErrorMessage = nil
        draftAPIKey = ""
        viewModel.prepareEnhancementsProvider(provider)
        viewModel.refreshEnhancementsProviderModelsManually()
    }

    private func validatedDraft(
        for provider: AIProvider,
        requiresCredentialForTest: Bool
    ) -> ValidatedEditorDraft? {
        let normalizedDisplayName = draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBaseURL = draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAPIKey = draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedIconSystemName = draftIconSystemName?.trimmingCharacters(in: .whitespacesAndNewlines)

        if provider == .custom {
            guard !normalizedDisplayName.isEmpty else {
                draftErrorMessage = "settings.enhancements.providers.editor.validation.name_required".localized
                return nil
            }

            guard !normalizedBaseURL.isEmpty else {
                draftErrorMessage = "settings.enhancements.providers.editor.validation.base_url_required".localized
                return nil
            }

            guard isValidHTTPURLString(normalizedBaseURL) else {
                draftErrorMessage = "settings.enhancements.providers.editor.validation.base_url_invalid".localized
                return nil
            }
        }

        if requiresCredentialForTest,
           normalizedAPIKey.isEmpty,
           !draftHasSavedAPIKey
        {
            draftErrorMessage = "settings.enhancements.providers.editor.validation.key_required_for_test".localized
            return nil
        }

        let resolvedDisplayName = if provider == .custom {
            normalizedDisplayName
        } else {
            provider.displayName
        }

        let resolvedBaseURL: String? = if provider == .custom {
            normalizedBaseURL
        } else {
            nil
        }

        let resolvedIconSystemName: String? = if provider == .custom {
            if let normalizedIconSystemName,
               EnhancementsProviderEditorSheet.curatedCustomProviderIcons.contains(normalizedIconSystemName),
               normalizedIconSystemName != provider.icon
            {
                normalizedIconSystemName
            } else {
                nil
            }
        } else {
            nil
        }

        return ValidatedEditorDraft(
            displayName: resolvedDisplayName,
            baseURL: resolvedBaseURL,
            iconSystemName: resolvedIconSystemName
        )
    }
}
