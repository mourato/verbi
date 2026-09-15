import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

public extension AppSettingsStore {
    /// Updates the selected model for the current AI provider.
    /// This properly triggers the @Published didSet to persist changes.
    func updateSelectedModel(_ model: String) {
        var config = aiConfiguration
        config.selectedModel = model
        aiConfiguration = config
    }

    /// Updates the AI configuration for a specific provider.
    /// Properly triggers the @Published didSet to persist changes.
    func updateAIConfiguration(provider: AIProvider, baseURL: String? = nil, selectedModel: String? = nil) {
        var config = aiConfiguration
        config.provider = provider
        if let baseURL {
            config.baseURL = baseURL
        }
        if let selectedModel {
            config.selectedModel = selectedModel
        }
        aiConfiguration = config
    }

    func enhancementsRegistration(for id: UUID?) -> EnhancementsProviderRegistration? {
        guard let id else { return nil }
        return enhancementsProviderRegistrations.first(where: { $0.id == id })
    }

    func enhancementsRegistration(for provider: AIProvider) -> EnhancementsProviderRegistration? {
        enhancementsProviderRegistrations.first(where: { $0.provider == provider })
    }

    func enhancementsRegistrations(for provider: AIProvider) -> [EnhancementsProviderRegistration] {
        enhancementsProviderRegistrations.filter { $0.provider == provider }
    }

    func canAddEnhancementsProviderRegistration(_ provider: AIProvider) -> Bool {
        provider == .custom || enhancementsRegistration(for: provider) == nil
    }

    func suggestedCustomEnhancementsProviderName() -> String {
        let customCount = enhancementsProviderRegistrations.count(where: { $0.provider == .custom })
        let nextIndex = customCount + 1
        return "settings.enhancements.provider.custom.default_name".localized(with: nextIndex)
    }

    @discardableResult
    func addEnhancementsProviderRegistration(
        provider: AIProvider,
        displayName: String? = nil,
        baseURLOverride: String? = nil,
        iconSystemName: String? = nil
    ) -> EnhancementsProviderRegistration? {
        guard canAddEnhancementsProviderRegistration(provider) else { return nil }

        let registration = EnhancementsProviderRegistration(
            provider: provider,
            displayName: displayName ?? defaultRegistrationDisplayName(for: provider),
            baseURLOverride: provider == .custom ? baseURLOverride : nil,
            iconSystemName: provider == .custom ? iconSystemName : nil
        )

        var updated = enhancementsProviderRegistrations
        updated.append(registration)
        enhancementsProviderRegistrations = updated

        if enhancementsAISelection.registrationID == nil,
           enhancementsAISelection.provider == provider
        {
            enhancementsAISelection.registrationID = registration.id
        }

        if enhancementsDictationAISelection.registrationID == nil,
           enhancementsDictationAISelection.provider == provider
        {
            enhancementsDictationAISelection.registrationID = registration.id
        }

        return registration
    }

    func updateEnhancementsProviderRegistration(_ registration: EnhancementsProviderRegistration) {
        guard let index = enhancementsProviderRegistrations.firstIndex(where: { $0.id == registration.id }) else {
            return
        }

        var normalized = registration
        normalized.touchUpdatedAt()

        var updated = enhancementsProviderRegistrations
        updated[index] = normalized

        if normalized.isBuiltInSingleton {
            var seenBuiltInProviders = Set<AIProvider>()
            updated = updated.filter { candidate in
                if candidate.id == normalized.id {
                    seenBuiltInProviders.insert(candidate.provider)
                    return true
                }

                if candidate.provider == .custom {
                    return true
                }

                guard !seenBuiltInProviders.contains(candidate.provider) else {
                    return false
                }

                seenBuiltInProviders.insert(candidate.provider)
                return true
            }
        }

        enhancementsProviderRegistrations = updated
    }

    func removeEnhancementsProviderRegistration(id: UUID) {
        guard let removed = enhancementsProviderRegistrations.first(where: { $0.id == id }) else {
            return
        }

        enhancementsProviderRegistrations.removeAll { $0.id == id }
        enhancementsProviderSelectedModelsByRegistration.removeValue(forKey: id.uuidString)
        try? KeychainManager.deleteAPIKey(for: id)

        if !enhancementsProviderRegistrations.contains(where: { $0.provider == removed.provider }) {
            enhancementsProviderSelectedModels.removeValue(forKey: removed.provider.rawValue)
        }

        if enhancementsAISelection.registrationID == id {
            enhancementsAISelection.registrationID = nil
            enhancementsAISelection.selectedModel = ""
        }

        if enhancementsDictationAISelection.registrationID == id {
            enhancementsDictationAISelection.registrationID = nil
            enhancementsDictationAISelection.selectedModel = ""
        }
    }

    func migrateEnhancementsProviderRegistrationAPIKeysIfNeeded() {
        let firstCustomRegistrationID = enhancementsProviderRegistrations
            .first(where: { $0.provider == .custom })?
            .id

        for registration in enhancementsProviderRegistrations {
            if registration.provider.usesRegistrationScopedEnhancementsCredential {
                migrateRegistrationScopedCredential(
                    registration,
                    firstCustomRegistrationID: firstCustomRegistrationID
                )
                continue
            }

            migrateProviderScopedCredential(registration)
        }
    }

    private func migrateRegistrationScopedCredential(
        _ registration: EnhancementsProviderRegistration,
        firstCustomRegistrationID: UUID?
    ) {
        guard !KeychainManager.existsAPIKey(for: registration.id),
              registration.id == firstCustomRegistrationID
        else { return }

        let legacyProviderKey: String?
        do {
            legacyProviderKey = try KeychainManager.retrieveAPIKey(for: registration.provider)
        } catch {
            AppLogger.warning(
                "Could not read legacy provider credential during migration",
                category: .security,
                extra: [
                    "provider": registration.provider.rawValue,
                    "registrationID": registration.id.uuidString
                ]
            )
            return
        }

        guard let legacyProviderKey else { return }
        let apiKey = legacyProviderKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return }

        do {
            try KeychainManager.storeAPIKey(apiKey, for: registration.id)
        } catch {
            AppLogger.error(
                "Could not migrate provider credential to registration scope",
                category: .security,
                error: error,
                extra: ["registrationID": registration.id.uuidString]
            )
        }
    }

    private func migrateProviderScopedCredential(_ registration: EnhancementsProviderRegistration) {
        let registrationKey = (try? KeychainManager.retrieveAPIKey(for: registration.id))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !registrationKey.isEmpty else { return }

        if !KeychainManager.existsAPIKey(for: registration.provider) {
            do {
                try KeychainManager.store(registrationKey, for: KeychainManager.apiKeyKey(for: registration.provider))
            } catch {
                AppLogger.error(
                    "Could not migrate registration credential to provider scope",
                    category: .security,
                    error: error,
                    extra: ["provider": registration.provider.rawValue]
                )
            }
        }

        do {
            try KeychainManager.deleteAPIKey(for: registration.id)
        } catch {
            AppLogger.warning(
                "Could not remove legacy registration credential after migration",
                category: .security,
                extra: ["registrationID": registration.id.uuidString]
            )
        }
    }

    func enhancementsAPIKey(for mode: IntelligenceKernelMode) -> String? {
        if let key = enhancementsAPIKeyInternal(for: mode) {
            return key
        }
        return enhancementsAPIKeyInternal(for: siblingEnhancementsMode(for: mode))
    }

    func enhancementsAPIKey(for selection: EnhancementsAISelection) -> String? {
        let selectedRegistration = enhancementsRegistration(for: selection.registrationID)

        if let registrationID = selection.registrationID,
           let registrationKey = try? KeychainManager.retrieveAPIKey(for: registrationID)
        {
            let trimmed = registrationKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        let providerForFallback = selectedRegistration?.provider ?? selection.provider
        if let providerKey = try? KeychainManager.retrieveAPIKey(for: providerForFallback) {
            let trimmed = providerKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    private func enhancementsAPIKeyInternal(for mode: IntelligenceKernelMode) -> String? {
        let selection = enhancementsSelection(for: mode)
        let selectedRegistration = enhancementsRegistration(for: selection.registrationID)

        if let registrationID = selection.registrationID,
           let registrationKey = try? KeychainManager.retrieveAPIKey(for: registrationID)
        {
            let trimmed = registrationKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        let providerForFallback = selectedRegistration?.provider ?? selection.provider
        if let providerKey = try? KeychainManager.retrieveAPIKey(for: providerForFallback) {
            let trimmed = providerKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }
}
