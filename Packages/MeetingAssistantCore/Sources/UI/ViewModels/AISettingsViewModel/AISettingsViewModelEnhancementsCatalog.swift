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
    func fetchEnhancementsAvailableModels(
        trigger: ModelFetchTrigger = .automatic,
        provider: AIProvider? = nil
    ) async {
        let targetProvider = provider ?? activeEnhancementsProvider
        if trigger == .automatic,
           let lastFetch = lastAutomaticEnhancementsModelsFetchAt,
           Date().timeIntervalSince(lastFetch) < automaticModelsFetchThrottleInterval
        {
            return
        }

        guard let fetchContext = resolvedEnhancementsModelsFetchContext(for: targetProvider) else {
            return
        }

        if targetProvider == .custom {
            enhancementsModelCatalogStatus = .unavailable
            enhancementsAvailableModels = []
            enhancementsModelsFetchError = nil
            return
        }

        if trigger == .automatic {
            lastAutomaticEnhancementsModelsFetchAt = Date()
        }

        if activeEnhancementsProvider == targetProvider {
            isLoadingEnhancementsModels = true
            enhancementsModelCatalogStatus = .loading
            enhancementsModelsFetchError = nil
        }
        defer {
            if activeEnhancementsProvider == targetProvider {
                isLoadingEnhancementsModels = false
            }
        }

        do {
            let models = try await llmService.fetchAvailableModels(
                baseURL: fetchContext.baseURL,
                apiKey: fetchContext.apiKey,
                provider: targetProvider
            )
            enhancementsModelsByProvider[targetProvider] = models

            if activeEnhancementsProvider == targetProvider {
                enhancementsAvailableModels = models
                enhancementsModelCatalogStatus = .loaded
                registerEnhancementsModelsRefreshResult(
                    success: true,
                    message: String(format: "settings.ai.models_loaded".localized, models.count)
                )
            }
        } catch {
            if activeEnhancementsProvider == targetProvider {
                enhancementsModelCatalogStatus = .failed
                enhancementsModelsFetchError = error.localizedDescription
                registerEnhancementsModelsRefreshResult(
                    success: false,
                    message: "settings.ai.models.fetch_failed".localized
                )
            }
        }
    }

    func fetchEnhancementsProviderModels(trigger: ModelFetchTrigger = .automatic) async {
        if trigger == .automatic,
           let lastFetch = lastAutomaticEnhancementsProviderModelsFetchAt,
           Date().timeIntervalSince(lastFetch) < automaticModelsFetchThrottleInterval
        {
            return
        }

        if trigger == .automatic {
            lastAutomaticEnhancementsProviderModelsFetchAt = Date()
        }

        isLoadingEnhancementsProviderModels = true
        enhancementsProviderModelsFetchError = nil
        defer { isLoadingEnhancementsProviderModels = false }

        var options = Set<EnhancementsProviderModelOption>()
        var hadFailure = false

        // Force one-time legacy migration (.aiAPIKey -> provider slot) when applicable.
        _ = try? keychain.retrieveAPIKey(for: settings.aiConfiguration.provider)

        let registrations = settings.enhancementsProviderRegistrations

        do {
            if registrations.isEmpty {
                hadFailure = try await collectLegacyEnhancementsProviderModelOptions(into: &options)
            } else {
                hadFailure = try await collectRegistrationEnhancementsProviderModelOptions(
                    registrations,
                    into: &options
                )
            }
        } catch {
            enhancementsProviderModels = []
            enhancementsProviderModelsFetchError = "settings.ai.models.fetch_failed".localized
            logger.error("Failed to read API keys in batch: \(error.localizedDescription)")
            return
        }

        enhancementsProviderModels = sortedEnhancementsProviderModelOptions(options)

        if hadFailure {
            enhancementsProviderModelsFetchError = "settings.ai.models.fetch_failed".localized
        }
    }

    private func resolvedEnhancementsModelsFetchContext(
        for targetProvider: AIProvider
    ) -> (baseURL: URL, apiKey: String)? {
        let config = enhancementsConfiguration(for: targetProvider)
        guard let baseURL = llmService.validateURL(config.baseURL) else {
            if activeEnhancementsProvider == targetProvider {
                enhancementsModelsFetchError = "settings.ai.connection.invalid_url".localized
                registerEnhancementsModelsRefreshResult(
                    success: false,
                    message: "settings.ai.connection.invalid_url".localized
                )
            }
            return nil
        }

        let registrationID = settings.enhancementsRegistration(for: targetProvider)?.id
        let resolvedAPIKey = resolvedEnhancementsPersistedAPIKey(
            registrationID: registrationID,
            provider: targetProvider
        )

        guard !resolvedAPIKey.isEmpty else {
            enhancementsModelsByProvider.removeValue(forKey: targetProvider)
            if activeEnhancementsProvider == targetProvider {
                enhancementsAvailableModels = []
                enhancementsModelsFetchError = nil
            }
            return nil
        }

        return (baseURL, resolvedAPIKey)
    }

    private func collectLegacyEnhancementsProviderModelOptions(
        into options: inout Set<EnhancementsProviderModelOption>
    ) async throws -> Bool {
        let apiKeysByProvider = try keychain.retrieveAPIKeys(for: AIProvider.allCases)
        var hadFailure = false

        for provider in AIProvider.allCases {
            guard provider != .custom else { continue }
            guard let apiKey = apiKeysByProvider[provider] else { continue }

            let config = enhancementsConfiguration(for: provider)
            guard let baseURL = llmService.validateURL(config.baseURL) else {
                hadFailure = true
                continue
            }

            do {
                let models = try await llmService.fetchAvailableModels(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    provider: provider
                )

                for model in models {
                    options.insert(
                        EnhancementsProviderModelOption(
                            provider: provider,
                            modelID: model.id
                        )
                    )
                }
            } catch {
                hadFailure = true
                logger.error("Failed to fetch enhancements provider models for \(provider.displayName): \(error.localizedDescription)")
            }
        }

        return hadFailure
    }

    private func collectRegistrationEnhancementsProviderModelOptions(
        _ registrations: [EnhancementsProviderRegistration],
        into options: inout Set<EnhancementsProviderModelOption>
    ) async throws -> Bool {
        let providerKeysByProvider = try keychain.retrieveAPIKeys(
            for: Array(Set(registrations.map(\.provider)))
        )
        let registrationScopedIDs = registrations
            .filter(\.provider.usesRegistrationScopedEnhancementsCredential)
            .map(\.id)
        let registrationKeysByID = try keychain.retrieveAPIKeys(
            for: registrationScopedIDs
        )
        var hadFailure = false

        for registration in registrations {
            let provider = registration.provider
            guard provider != .custom else { continue }

            let registrationKey = registrationKeysByID[registration.id]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let apiKey = if provider.usesRegistrationScopedEnhancementsCredential {
                registrationKey
            } else {
                providerKeysByProvider[provider]
            }

            guard let apiKey, !apiKey.isEmpty else { continue }

            let config = enhancementsConfiguration(for: registration)
            guard let baseURL = llmService.validateURL(config.baseURL) else {
                hadFailure = true
                continue
            }

            do {
                let models = try await llmService.fetchAvailableModels(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    provider: provider
                )

                for model in models {
                    options.insert(
                        EnhancementsProviderModelOption(
                            provider: provider,
                            registrationID: registration.id,
                            registrationName: registration.displayName,
                            modelID: model.id
                        )
                    )
                }
            } catch {
                hadFailure = true
                logger.error("Failed to fetch enhancements provider models for registration \(registration.displayName): \(error.localizedDescription)")
            }
        }

        return hadFailure
    }

    private func sortedEnhancementsProviderModelOptions(
        _ options: Set<EnhancementsProviderModelOption>
    ) -> [EnhancementsProviderModelOption] {
        options.sorted { lhs, rhs in
            let lhsName = lhs.registrationName ?? lhs.provider.displayName
            let rhsName = rhs.registrationName ?? rhs.provider.displayName

            if lhsName.caseInsensitiveCompare(rhsName) == .orderedSame {
                return lhs.modelID.localizedCaseInsensitiveCompare(rhs.modelID) == .orderedAscending
            }
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }

    private func enhancementsConfiguration(for registration: EnhancementsProviderRegistration) -> AIConfiguration {
        let selectedModel = settings.enhancementsSelectedModel(for: registration.id)

        return AIConfiguration(
            provider: registration.provider,
            baseURL: registration.resolvedBaseURL,
            selectedModel: selectedModel
        )
    }

    private func registerEnhancementsModelsRefreshResult(success: Bool, message: String) {
        enhancementsLastModelsRefreshSucceeded = success
        enhancementsLastModelsRefreshResultText = message
        enhancementsLastModelsRefreshAt = Date()
    }
}
