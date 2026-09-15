import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

public extension AppSettingsStore {
    func backfillEnhancementsSelectionModelsIfNeeded() {
        let normalizedRegistrations = Self.normalizedEnhancementsProviderRegistrationsForBackfill(
            enhancementsProviderRegistrations
        )
        var updatedProviderSelectedModels = enhancementsProviderSelectedModels
        var updatedProviderSelectedModelsByRegistration = enhancementsProviderSelectedModelsByRegistration

        let updatedMeetingSelection = Self.withBackfilledEnhancementsModel(
            for: enhancementsAISelection,
            providerSelectedModels: &updatedProviderSelectedModels,
            providerSelectedModelsByRegistration: &updatedProviderSelectedModelsByRegistration,
            registrations: normalizedRegistrations,
            legacyConfiguration: aiConfiguration
        )
        let updatedDictationSelection = Self.withBackfilledEnhancementsModel(
            for: enhancementsDictationAISelection,
            providerSelectedModels: &updatedProviderSelectedModels,
            providerSelectedModelsByRegistration: &updatedProviderSelectedModelsByRegistration,
            registrations: normalizedRegistrations,
            legacyConfiguration: aiConfiguration
        )

        guard normalizedRegistrations != enhancementsProviderRegistrations
            || updatedMeetingSelection != enhancementsAISelection
            || updatedDictationSelection != enhancementsDictationAISelection
            || updatedProviderSelectedModels != enhancementsProviderSelectedModels
            || updatedProviderSelectedModelsByRegistration != enhancementsProviderSelectedModelsByRegistration
        else {
            return
        }

        enhancementsProviderRegistrations = normalizedRegistrations
        enhancementsAISelection = updatedMeetingSelection
        enhancementsDictationAISelection = updatedDictationSelection
        enhancementsProviderSelectedModels = updatedProviderSelectedModels
        enhancementsProviderSelectedModelsByRegistration = updatedProviderSelectedModelsByRegistration

        Self.persistBackfilledProviderRegistrations(enhancementsProviderRegistrations)
        Self.persistBackfilledEnhancementsSelection(enhancementsAISelection)
        Self.persistBackfilledDictationSelection(enhancementsDictationAISelection)
        Self.persistBackfilledProviderModels(enhancementsProviderSelectedModels)
        Self.persistBackfilledProviderModelsByRegistration(enhancementsProviderSelectedModelsByRegistration)
    }

    func setEnhancementsProviderSelectedModel(_ model: String, for provider: AIProvider) {
        let normalizedModel = normalizedEnhancementsModelID(model, for: provider)
        var updated = enhancementsProviderSelectedModels
        if normalizedModel.isEmpty {
            updated.removeValue(forKey: provider.rawValue)
        } else {
            updated[provider.rawValue] = normalizedModel
        }
        enhancementsProviderSelectedModels = updated

        if let registrationID = enhancementsRegistration(for: provider)?.id {
            setEnhancementsProviderSelectedModel(normalizedModel, for: registrationID)
        }
    }

    func setEnhancementsProviderSelectedModel(_ model: String, for registrationID: UUID) {
        guard let registration = enhancementsRegistration(for: registrationID) else { return }
        let normalizedModel = normalizedEnhancementsModelID(model, for: registration.provider)

        var updated = enhancementsProviderSelectedModelsByRegistration
        if normalizedModel.isEmpty {
            updated.removeValue(forKey: registrationID.uuidString)
        } else {
            updated[registrationID.uuidString] = normalizedModel
        }
        enhancementsProviderSelectedModelsByRegistration = updated
    }
}

private extension AppSettingsStore {
    static let enhancementsSelectionStorageKey = "enhancementsAISelection"
    static let enhancementsDictationSelectionStorageKey = "enhancementsDictationAISelection"
    static let enhancementsProviderModelsStorageKey = "enhancementsProviderSelectedModels"
    static let enhancementsProviderRegistrationsStorageKey = "enhancementsProviderRegistrations"
    static let enhancementsProviderModelsByRegistrationStorageKey = "enhancementsProviderSelectedModelsByRegistration"

    static func persistBackfilledEnhancementsSelection(_ selection: EnhancementsAISelection) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        UserDefaults.standard.set(data, forKey: enhancementsSelectionStorageKey)
    }

    static func persistBackfilledDictationSelection(_ selection: EnhancementsAISelection) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        UserDefaults.standard.set(data, forKey: enhancementsDictationSelectionStorageKey)
    }

    static func persistBackfilledProviderModels(_ models: [String: String]) {
        guard let data = try? JSONEncoder().encode(models) else { return }
        UserDefaults.standard.set(data, forKey: enhancementsProviderModelsStorageKey)
    }

    static func persistBackfilledProviderRegistrations(_ registrations: [EnhancementsProviderRegistration]) {
        guard let data = try? JSONEncoder().encode(registrations) else { return }
        UserDefaults.standard.set(data, forKey: enhancementsProviderRegistrationsStorageKey)
    }

    static func persistBackfilledProviderModelsByRegistration(_ models: [String: String]) {
        guard let data = try? JSONEncoder().encode(models) else { return }
        UserDefaults.standard.set(data, forKey: enhancementsProviderModelsByRegistrationStorageKey)
    }

    private static func backfilledEnhancementsSelection(
        provider: AIProvider,
        model: String,
        registration: EnhancementsProviderRegistration?
    ) -> EnhancementsAISelection {
        EnhancementsAISelection(
            provider: provider,
            selectedModel: model,
            registrationID: registration?.id
        )
    }

    private static func backfilledEnhancementsModel(
        for selection: EnhancementsAISelection,
        registration: EnhancementsProviderRegistration?,
        providerSelectedModels: [String: String],
        providerSelectedModelsByRegistration: [String: String],
        legacyConfiguration: AIConfiguration
    ) -> (model: String, persistRegistrationModel: Bool)? {
        let provider = registration?.provider ?? selection.provider
        let normalizedSelectedModel = normalizedEnhancementsModelID(
            selection.selectedModel,
            for: provider
        )
        if !normalizedSelectedModel.isEmpty {
            return (normalizedSelectedModel, true)
        }

        if let registration,
           let registrationModel = providerSelectedModelsByRegistration[registration.id.uuidString].map({
               normalizedEnhancementsModelID($0, for: provider)
           }),
           !registrationModel.isEmpty
        {
            return (registrationModel, false)
        }

        if let providerModel = providerSelectedModels[provider.rawValue].map({
            normalizedEnhancementsModelID($0, for: provider)
        }),
            !providerModel.isEmpty
        {
            return (providerModel, true)
        }

        let normalizedLegacyModel = normalizedEnhancementsModelID(
            legacyConfiguration.selectedModel,
            for: provider
        )
        guard legacyConfiguration.provider == provider,
              !normalizedLegacyModel.isEmpty
        else {
            return nil
        }
        return (normalizedLegacyModel, true)
    }

    static func withBackfilledEnhancementsModel(
        for selection: EnhancementsAISelection,
        providerSelectedModels: inout [String: String],
        providerSelectedModelsByRegistration: inout [String: String],
        registrations: [EnhancementsProviderRegistration],
        legacyConfiguration: AIConfiguration
    ) -> EnhancementsAISelection {
        let registration = if let registrationID = selection.registrationID {
            registrations.first(where: { $0.id == registrationID })
        } else {
            registrations.first(where: { $0.provider == selection.provider })
        }

        let provider = registration?.provider ?? selection.provider
        let providerKey = provider.rawValue
        if let backfilledModel = backfilledEnhancementsModel(
            for: selection,
            registration: registration,
            providerSelectedModels: providerSelectedModels,
            providerSelectedModelsByRegistration: providerSelectedModelsByRegistration,
            legacyConfiguration: legacyConfiguration
        ) {
            providerSelectedModels[providerKey] = backfilledModel.model
            if backfilledModel.persistRegistrationModel, let registration {
                providerSelectedModelsByRegistration[registration.id.uuidString] = backfilledModel.model
            }
            return backfilledEnhancementsSelection(
                provider: provider,
                model: backfilledModel.model,
                registration: registration
            )
        }

        providerSelectedModels.removeValue(forKey: providerKey)
        if let registration {
            providerSelectedModelsByRegistration.removeValue(forKey: registration.id.uuidString)
        }
        return EnhancementsAISelection(
            provider: provider,
            selectedModel: "",
            registrationID: registration?.id
        )
    }

    static func normalizedEnhancementsProviderRegistrationsForBackfill(
        _ registrations: [EnhancementsProviderRegistration]
    ) -> [EnhancementsProviderRegistration] {
        var seenIDs = Set<UUID>()
        var seenBuiltInProviders = Set<AIProvider>()
        var normalized: [EnhancementsProviderRegistration] = []
        normalized.reserveCapacity(registrations.count)

        for var registration in registrations {
            guard seenIDs.insert(registration.id).inserted else { continue }
            registration.normalizeInPlace()

            if registration.isBuiltInSingleton,
               !seenBuiltInProviders.insert(registration.provider).inserted
            {
                continue
            }

            normalized.append(registration)
        }

        return normalized
    }
}
