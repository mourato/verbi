import Combine
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import os.log
import SwiftUI

public extension AISettingsViewModel {
    func refreshEnhancementsProviderCredentialState(provider: AIProvider? = nil) {
        if let provider {
            activeEnhancementsProvider = provider
        }

        let activeProvider = activeEnhancementsProvider
        isEnhancementsProviderKeySaved = keychain.existsAPIKey(for: activeProvider)
        enhancementsModelsFetchError = nil
        enhancementsActionError = nil
        enhancementsLastModelsRefreshAt = nil
        enhancementsLastModelsRefreshSucceeded = false
        enhancementsLastModelsRefreshResultText = nil
        clearTransientEnhancementsAPIKey()

        if let cachedModels = enhancementsModelsByProvider[activeProvider] {
            enhancementsAvailableModels = cachedModels
        } else {
            enhancementsAvailableModels = []
        }

        if isEnhancementsProviderKeySaved {
            enhancementsConnectionStatus = .saved
            if activeProvider == .custom {
                enhancementsModelCatalogStatus = .unavailable
            } else if credentialBootstrapPolicy == .eager {
                Task {
                    await fetchEnhancementsAvailableModels(provider: activeProvider)
                }
            }
        } else {
            enhancementsConnectionStatus = .unknown
            enhancementsModelCatalogStatus = .idle
            enhancementsAvailableModels = []
        }
    }

    func prepareEnhancementsProvider(_ provider: AIProvider) {
        enhancementsActionError = nil
        refreshEnhancementsProviderCredentialState(provider: provider)
    }

    func hasSavedAPIKey(for provider: AIProvider) -> Bool {
        keychain.existsAPIKey(for: provider)
    }

    func hasSavedEnhancementsAPIKey(for registrationID: UUID?, provider: AIProvider) -> Bool {
        if provider.usesRegistrationScopedEnhancementsCredential,
           let registrationID,
           KeychainManager.existsAPIKey(for: registrationID)
        {
            return true
        }

        return keychain.existsAPIKey(for: provider)
    }

    func enhancementsReadinessIssue(for provider: AIProvider) -> EnhancementsInferenceReadinessIssue? {
        let config = enhancementsConfiguration(for: provider)
        guard llmService.validateURL(config.baseURL) != nil else {
            return .invalidBaseURL
        }

        let registrationID = settings.enhancementsRegistration(for: provider)?.id
        guard hasSavedEnhancementsAPIKey(for: registrationID, provider: provider) else {
            return .missingAPIKey
        }

        return nil
    }

    @discardableResult
    func testEnhancementsAPIConnection() -> Task<Void, Never> {
        let provider = activeEnhancementsProvider
        let config = enhancementsConfiguration(for: provider)
        let registrationID = settings.enhancementsRegistration(for: provider)?.id
        let pendingInput = normalizedEnhancementsAPIKeyText

        return Task {
            _ = await self.testEnhancementsAPIConnection(
                provider: provider,
                baseURLString: config.baseURL,
                registrationID: registrationID,
                pendingAPIKeyInput: pendingInput
            )
        }
    }

    func testEnhancementsAPIConnection(
        provider: AIProvider,
        baseURLString: String,
        registrationID: UUID?,
        pendingAPIKeyInput: String
    ) async -> Bool {
        enhancementsConnectionStatus = .testing
        enhancementsActionError = nil
        enhancementsModelsFetchError = nil

        guard let baseURL = llmService.validateURL(baseURLString) else {
            enhancementsConnectionStatus = .failure("settings.ai.connection.invalid_url".localized)
            return false
        }

        let pendingInput = pendingAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let persistedKey = resolvedEnhancementsPersistedAPIKey(
            registrationID: registrationID,
            provider: provider
        )
        let credential = pendingInput.isEmpty ? persistedKey : pendingInput

        guard !credential.isEmpty else {
            enhancementsConnectionStatus = .failure("transcription.qa.error.no_api".localized)
            return false
        }

        do {
            let success = try await llmService.testConnection(
                baseURL: baseURL,
                apiKey: credential,
                provider: provider
            )

            guard success else {
                enhancementsConnectionStatus = .failure("settings.ai.connection.invalid_response".localized)
                return false
            }

            if !pendingInput.isEmpty {
                try persistEnhancementsAPIKey(
                    pendingInput,
                    registrationID: registrationID,
                    provider: provider
                )
            }

            activeEnhancementsProvider = provider
            isEnhancementsProviderKeySaved = hasSavedEnhancementsAPIKey(
                for: registrationID,
                provider: provider
            )
            enhancementsConnectionStatus = .success
            clearTransientEnhancementsAPIKey()
            await fetchEnhancementsAvailableModels(trigger: .manual, provider: provider)
            await fetchEnhancementsProviderModels(trigger: .manual)

            if settings.aiConfiguration.provider == provider {
                refreshProviderCredentialState()
            }

            return true
        } catch {
            enhancementsConnectionStatus = .failure(connectionErrorMessage(from: error))
            logger.error("Enhancements connection test failed: \(error.localizedDescription)")
            return false
        }
    }

    func removeEnhancementsAPIKey() {
        let provider = activeEnhancementsProvider
        let registrationID = settings.enhancementsRegistration(for: provider)?.id
        removeEnhancementsAPIKey(registrationID: registrationID, provider: provider)
    }

    func removeEnhancementsAPIKey(registrationID: UUID?, provider: AIProvider) {
        enhancementsActionError = nil

        do {
            if provider.usesRegistrationScopedEnhancementsCredential,
               let registrationID
            {
                try KeychainManager.deleteAPIKey(for: registrationID)
            } else {
                let providerKey = KeychainManager.apiKeyKey(for: provider)
                try keychain.delete(for: providerKey)
                if let registrationID {
                    try? keychain.deleteAPIKey(for: registrationID)
                }
            }

            clearTransientEnhancementsAPIKey()
            isEnhancementsProviderKeySaved = hasSavedEnhancementsAPIKey(
                for: settings.enhancementsRegistration(for: provider)?.id,
                provider: provider
            )
            enhancementsConnectionStatus = .unknown
            enhancementsAvailableModels = []
            enhancementsModelsFetchError = nil
            enhancementsModelCatalogStatus = .idle

            if settings.aiConfiguration.provider == provider {
                refreshProviderCredentialState()
            }
        } catch {
            enhancementsActionError = "settings.ai.remove_failed".localized
            logger.error("Failed to remove enhancements API key: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func saveEnhancementsAPIKey(
        _ value: String,
        registrationID: UUID?,
        provider: AIProvider
    ) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }

        do {
            try persistEnhancementsAPIKey(normalized, registrationID: registrationID, provider: provider)
            let saved = hasSavedEnhancementsAPIKey(
                for: registrationID,
                provider: provider
            )
            guard saved else {
                enhancementsActionError = "settings.ai.save_failed".localized
                let registrationDescription = registrationID?.uuidString ?? "none"
                let message = "Enhancements API key save verification failed for provider "
                    + "\(provider.rawValue), registration \(registrationDescription)"
                logger.error(
                    "\(message)"
                )
                return false
            }

            isEnhancementsProviderKeySaved = true
            enhancementsActionError = nil
            return true
        } catch {
            enhancementsActionError = "settings.ai.save_failed".localized
            logger.error("Failed to save enhancements API key: \(error.localizedDescription)")
            return false
        }
    }

    func resetEnhancementsProviderStateForDeferredBootstrap(provider: AIProvider) {
        activeEnhancementsProvider = provider
        isEnhancementsProviderKeySaved = false
        enhancementsConnectionStatus = .unknown
        enhancementsAvailableModels = enhancementsModelsByProvider[provider] ?? []
        enhancementsModelsFetchError = nil
        enhancementsModelCatalogStatus = provider == .custom ? .unavailable : .idle
        enhancementsActionError = nil
        clearTransientEnhancementsAPIKey()
    }

    private var normalizedEnhancementsAPIKeyText: String {
        enhancementsAPIKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clearTransientEnhancementsAPIKey() {
        guard !enhancementsAPIKeyText.isEmpty else { return }
        enhancementsAPIKeyText = ""
    }

    func enhancementsConfiguration(for provider: AIProvider) -> AIConfiguration {
        let baseURL = provider == .custom ? settings.aiConfiguration.baseURL : provider.defaultBaseURL
        let selectedModel = settings.enhancementsSelectedModel(for: provider)

        return AIConfiguration(
            provider: provider,
            baseURL: baseURL,
            selectedModel: selectedModel
        )
    }

    private func enhancementsConfiguration(for registration: EnhancementsProviderRegistration) -> AIConfiguration {
        let selectedModel = settings.enhancementsSelectedModel(for: registration.id)

        return AIConfiguration(
            provider: registration.provider,
            baseURL: registration.resolvedBaseURL,
            selectedModel: selectedModel
        )
    }

    private func persistEnhancementsAPIKey(_ value: String, for provider: AIProvider) throws {
        try persistEnhancementsAPIKey(value, registrationID: nil, provider: provider)
    }

    private func persistEnhancementsAPIKey(
        _ value: String,
        registrationID: UUID?,
        provider: AIProvider
    ) throws {
        do {
            if provider.usesRegistrationScopedEnhancementsCredential,
               let registrationID
            {
                try keychain.storeAPIKey(value, for: registrationID)
            } else {
                let providerKey = KeychainManager.apiKeyKey(for: provider)
                try keychain.store(value, for: providerKey)
                if let registrationID {
                    try? keychain.deleteAPIKey(for: registrationID)
                }
            }
            // swiftformat:disable:next redundantSelf
            let registrationDescription = registrationID?.uuidString ?? "none"
            let message = "Enhancements API key persisted for provider "
                + "\(provider.rawValue), registration \(registrationDescription), "
                + "registrationScoped \(provider.usesRegistrationScopedEnhancementsCredential)"
            logger.info(
                "\(message)"
            )
        } catch {
            let registrationDescription = registrationID?.uuidString ?? "none"
            let message = "Failed to persist enhancements API key for provider "
                + "\(provider.rawValue), registration \(registrationDescription): "
                + error.localizedDescription
            logger.error(
                "\(message)"
            )
            throw error
        }
    }

    func resolvedEnhancementsPersistedAPIKey(
        registrationID: UUID?,
        provider: AIProvider
    ) -> String {
        if provider.usesRegistrationScopedEnhancementsCredential,
           let registrationID,
           let key = (try? keychain.retrieveAPIKey(for: registrationID))?
           .trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty
        {
            return key
        }

        return (try? keychain.retrieveAPIKey(for: provider))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
