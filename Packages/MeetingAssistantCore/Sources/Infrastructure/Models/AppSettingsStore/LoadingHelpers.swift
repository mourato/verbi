import Foundation

extension AppSettingsStore {
    static let defaultSummaryTemplate = """
    ---
    title: "{{title}}"
    date: "{{date}}"
    duration: "{{duration}}"
    app: "{{app}}"
    type: "{{type}}"
    ---

    # {{title}}

    {{summary}}
    """

    static func loadDecoded<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func loadAIConfiguration() -> AIConfiguration {
        guard let config = loadDecoded(AIConfiguration.self, forKey: Keys.aiConfiguration) else {
            return .default
        }

        if !config.legacyApiKey.isEmpty {
            let providerKey = KeychainManager.apiKeyKey(for: config.provider)
            try? KeychainManager.store(config.legacyApiKey, for: providerKey)
            return config.withoutLegacyKey
        }

        return config
    }

    static func loadEnhancementsAISelection(defaultingTo config: AIConfiguration) -> EnhancementsAISelection {
        if let selection = loadDecoded(EnhancementsAISelection.self, forKey: Keys.enhancementsAISelection) {
            return selection
        }

        return EnhancementsAISelection(provider: config.provider, selectedModel: config.selectedModel)
    }

    static func loadEnhancementsDictationAISelection(
        defaultingTo selection: EnhancementsAISelection
    ) -> EnhancementsAISelection {
        if let dictationSelection = loadDecoded(EnhancementsAISelection.self, forKey: Keys.enhancementsDictationAISelection) {
            return dictationSelection
        }

        return selection
    }

    static func loadEnhancementsProviderSelectedModels(
        defaultMeetingSelection: EnhancementsAISelection,
        defaultDictationSelection: EnhancementsAISelection
    ) -> [String: String] {
        let loaded = loadDecoded([String: String].self, forKey: Keys.enhancementsProviderSelectedModels) ?? [:]
        var normalized: [String: String] = [:]

        for (providerRawValue, model) in loaded {
            guard AIProvider(rawValue: providerRawValue) != nil else { continue }
            let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedModel.isEmpty else { continue }
            normalized[providerRawValue] = normalizedModel
        }

        let meetingModel = defaultMeetingSelection.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !meetingModel.isEmpty {
            normalized[defaultMeetingSelection.provider.rawValue] = meetingModel
        }

        let dictationModel = defaultDictationSelection.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dictationModel.isEmpty {
            normalized[defaultDictationSelection.provider.rawValue] = dictationModel
        }

        return normalized
    }

    static func loadEnhancementsProviderRegistrations(
        aiConfiguration: AIConfiguration,
        meetingSelection: EnhancementsAISelection,
        dictationSelection: EnhancementsAISelection,
        legacyProviderSelectedModels: [String: String]
    ) -> [EnhancementsProviderRegistration] {
        if let loaded = loadDecoded(
            [EnhancementsProviderRegistration].self,
            forKey: Keys.enhancementsProviderRegistrations
        ) {
            let normalizedLoaded = normalizedEnhancementsProviderRegistrations(loaded)
            if !normalizedLoaded.isEmpty {
                return normalizedLoaded
            }
        }

        return migratedEnhancementsProviderRegistrations(
            aiConfiguration: aiConfiguration,
            meetingSelection: meetingSelection,
            dictationSelection: dictationSelection,
            legacyProviderSelectedModels: legacyProviderSelectedModels
        )
    }

    static func normalizedEnhancementsSelection(
        _ selection: EnhancementsAISelection,
        registrations: [EnhancementsProviderRegistration]
    ) -> EnhancementsAISelection {
        guard !registrations.isEmpty else {
            var cleared = selection
            cleared.registrationID = nil
            return cleared
        }

        var normalized = selection

        if let registrationID = selection.registrationID,
           let registration = registrations.first(where: { $0.id == registrationID })
        {
            normalized.provider = registration.provider
            normalized.registrationID = registration.id
            return normalized
        }

        normalized.registrationID = registrations.first(where: { $0.provider == selection.provider })?.id
        return normalized
    }

    static func loadEnhancementsProviderSelectedModelsByRegistration(
        registrations: [EnhancementsProviderRegistration],
        legacyProviderSelectedModels: [String: String],
        meetingSelection: EnhancementsAISelection,
        dictationSelection: EnhancementsAISelection
    ) -> [String: String] {
        let validRegistrationIDs = Set(registrations.map(\.id.uuidString))
        let loaded = loadDecoded(
            [String: String].self,
            forKey: Keys.enhancementsProviderSelectedModelsByRegistration
        ) ?? [:]

        var normalized: [String: String] = [:]
        for (registrationID, model) in loaded {
            guard validRegistrationIDs.contains(registrationID) else { continue }
            let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedModel.isEmpty else { continue }
            normalized[registrationID] = trimmedModel
        }

        let firstRegistrationIDByProvider = Dictionary(
            registrations.map { ($0.provider, $0.id.uuidString) },
            uniquingKeysWith: { current, _ in current }
        )

        for (providerRawValue, model) in legacyProviderSelectedModels {
            guard let provider = AIProvider(rawValue: providerRawValue),
                  let registrationID = firstRegistrationIDByProvider[provider],
                  normalized[registrationID] == nil
            else {
                continue
            }
            normalized[registrationID] = model
        }

        let meetingModel = meetingSelection.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if let registrationID = meetingSelection.registrationID?.uuidString,
           !meetingModel.isEmpty
        {
            normalized[registrationID] = meetingModel
        }

        let dictationModel = dictationSelection.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if let registrationID = dictationSelection.registrationID?.uuidString,
           !dictationModel.isEmpty
        {
            normalized[registrationID] = dictationModel
        }

        return normalized
    }

    static func loadTranscriptionDictationSelection() -> TranscriptionProviderSelection {
        guard let selection = loadDecoded(
            TranscriptionProviderSelection.self,
            forKey: Keys.transcriptionDictationSelection
        ) else {
            return .default
        }

        let normalizedModel = selection.provider.normalizedModelID(selection.selectedModel)
        return TranscriptionProviderSelection(
            provider: selection.provider,
            selectedModel: normalizedModel
        )
    }

    static func loadTranscriptionProviderSelectedModels(
        defaultDictationSelection: TranscriptionProviderSelection
    ) -> [String: String] {
        let loaded = loadDecoded([String: String].self, forKey: Keys.transcriptionProviderSelectedModels) ?? [:]
        var normalized: [String: String] = [:]

        for (providerRawValue, model) in loaded {
            guard let provider = TranscriptionProvider(rawValue: providerRawValue) else { continue }
            normalized[providerRawValue] = provider.normalizedModelID(model)
        }

        normalized[defaultDictationSelection.provider.rawValue] = defaultDictationSelection.provider
            .normalizedModelID(defaultDictationSelection.selectedModel)
        return normalized
    }

    static func loadMeetingTranscriptionLocalModel(
        transcriptionProviderSelectedModels: [String: String]
    ) -> LocalTranscriptionModel {
        if let storedValue = UserDefaults.standard.string(forKey: Keys.meetingTranscriptionLocalModel),
           let model = LocalTranscriptionModel(rawValue: storedValue)
        {
            return model
        }

        if let legacyLocalModel = transcriptionProviderSelectedModels[TranscriptionProvider.local.rawValue],
           let model = LocalTranscriptionModel(rawValue: legacyLocalModel)
        {
            return model
        }

        return .parakeetTdt06BV3
    }

    static func loadUUID(forKey key: String) -> UUID? {
        UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    static func loadOptionalInt(forKey key: String) -> Int? {
        UserDefaults.standard.object(forKey: key) as? Int
    }

    static func loadInt(forKey key: String, defaultValue: Int) -> Int {
        let value = UserDefaults.standard.object(forKey: key) as? Int
        return value ?? defaultValue
    }

    static func loadDouble(forKey key: String, defaultValue: Double) -> Double {
        let value = UserDefaults.standard.object(forKey: key) as? Double
        return value ?? defaultValue
    }

    static func loadBoolDefaultIfUnset(forKey key: String, defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func loadCapabilityToggle(
        forKey key: String,
        defaultForNewInstall: Bool,
        defaultForExistingInstall: Bool
    ) -> Bool {
        guard UserDefaults.standard.object(forKey: key) == nil else {
            return UserDefaults.standard.bool(forKey: key)
        }

        return isExistingInstallForCapabilityMigration()
            ? defaultForExistingInstall
            : defaultForNewInstall
    }

    static func isExistingInstallForCapabilityMigration() -> Bool {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: Keys.hasCompletedOnboarding) != nil {
            return true
        }

        let legacyInstallMarkers: [String] = [
            Keys.aiConfiguration,
            Keys.assistantIntegrations,
            Keys.dictationSelectedPresetKey,
            Keys.meetingSelectedPresetKey
        ]

        return legacyInstallMarkers.contains { marker in
            defaults.object(forKey: marker) != nil
        }
    }

    static func loadEnum<T: RawRepresentable & Sendable>(forKey key: String, defaultValue: T) -> T where T.RawValue == String {
        let rawValue = UserDefaults.standard.string(forKey: key)
        return rawValue.flatMap(T.init(rawValue:)) ?? defaultValue
    }

    static func loadURLBookmark(forKey key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    static func loadDictationPresetKey(fallback: PresetShortcutKey) -> PresetShortcutKey {
        let rawValue = UserDefaults.standard.string(forKey: Keys.dictationSelectedPresetKey)
        return rawValue.flatMap { PresetShortcutKey(rawValue: $0) } ?? fallback
    }
}

private extension AppSettingsStore {
    static func normalizedEnhancementsProviderRegistrations(
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

    static func migratedEnhancementsProviderRegistrations(
        aiConfiguration: AIConfiguration,
        meetingSelection: EnhancementsAISelection,
        dictationSelection: EnhancementsAISelection,
        legacyProviderSelectedModels: [String: String]
    ) -> [EnhancementsProviderRegistration] {
        var registrations: [EnhancementsProviderRegistration] = []

        let selectedProviders = Set([
            aiConfiguration.provider,
            meetingSelection.provider,
            dictationSelection.provider
        ])

        for provider in AIProvider.allCases where provider != .custom {
            let hasLegacyModel = legacyProviderSelectedModels[provider.rawValue] != nil
            let shouldRegister = KeychainManager.existsAPIKey(for: provider)
                || selectedProviders.contains(provider)
                || hasLegacyModel

            guard shouldRegister else { continue }

            registrations.append(
                EnhancementsProviderRegistration(
                    provider: provider,
                    displayName: provider.displayName
                )
            )
        }

        let normalizedCustomBaseURL = aiConfiguration.baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLegacyCustomModel = legacyProviderSelectedModels[AIProvider.custom.rawValue] != nil
        let shouldRegisterCustom = KeychainManager.existsAPIKey(for: .custom)
            || selectedProviders.contains(.custom)
            || hasLegacyCustomModel
            || !normalizedCustomBaseURL.isEmpty

        if shouldRegisterCustom {
            registrations.append(
                EnhancementsProviderRegistration(
                    provider: .custom,
                    displayName: AIProvider.custom.displayName,
                    baseURLOverride: normalizedCustomBaseURL.isEmpty ? nil : normalizedCustomBaseURL
                )
            )
        }

        return normalizedEnhancementsProviderRegistrations(registrations)
    }
}
