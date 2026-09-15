import Foundation
import MeetingAssistantCoreCommon
import Security

extension KeychainManager {
    // MARK: - Public API

    /// Store a string securely in the Keychain.
    /// - Parameters:
    ///   - value: The string value to store.
    ///   - key: The key to store the value under.
    /// - Throws: `KeychainError` if storage fails.
    static func store(_ value: String, for key: Key) throws {
        try mutateConsolidated { consolidated in
            guard keyValue(in: consolidated, for: key) != value else { return false }
            setValue(value, in: &consolidated, for: key)
            return true
        }
    }

    /// Retrieve a string from the Keychain.
    /// - Parameter key: The key to retrieve the value for.
    /// - Returns: The stored string value, or `nil` if not found.
    /// - Throws: `KeychainError` if retrieval fails for reasons other than item not found.
    static func retrieve(for key: Key) throws -> String? {
        let consolidated = try loadConsolidated()

        if let value = keyValue(in: consolidated, for: key) {
            return value
        }

        let allServices = [serviceIdentifier] + legacyServiceIdentifiers
        for serviceId in allServices {
            guard let legacyValue = try retrieve(account: key.rawValue, serviceIdentifier: serviceId),
                  !legacyValue.isEmpty
            else { continue }

            try mutateConsolidated { mutableConsolidated in
                setValue(legacyValue, in: &mutableConsolidated, for: key)
                return true
            }
            try delete(account: key.rawValue, serviceIdentifier: serviceId)
            return legacyValue
        }

        return nil
    }

    /// Delete a value from the Keychain.
    /// - Parameter key: The key to delete.
    /// - Throws: `KeychainError` if deletion fails.
    static func delete(for key: Key) throws {
        try mutateConsolidated { consolidated in
            guard keyValue(in: consolidated, for: key) != nil else { return false }
            setValue(nil, in: &consolidated, for: key)
            return true
        }
    }

    /// Check if a value exists in the Keychain.
    /// - Parameter key: The key to check.
    /// - Returns: `true` if the key exists, `false` otherwise.
    static func exists(for key: Key) -> Bool {
        do {
            let consolidated = try loadConsolidated()
            if keyValue(in: consolidated, for: key) != nil {
                return true
            }

            let allServices = [serviceIdentifier] + legacyServiceIdentifiers
            return allServices.contains { exists(account: key.rawValue, serviceIdentifier: $0) }
        } catch {
            return false
        }
    }

    // MARK: - Provider-specific helpers
}

public extension KeychainManager {
    static func apiKeyKey(for provider: AIProvider) -> Key {
        switch provider {
        case .openai:
            .aiAPIKeyOpenAI
        case .anthropic:
            .aiAPIKeyAnthropic
        case .groq:
            .aiAPIKeyGroq
        case .google:
            .aiAPIKeyGoogle
        case .custom:
            .aiAPIKeyCustom
        }
    }

    static func retrieveAPIKey(for provider: AIProvider) throws -> String? {
        let providerKey = apiKeyKey(for: provider)
        if let value = try retrieve(for: providerKey), !value.isEmpty {
            return value
        }

        // Legacy unified key fallback: migrate to provider-specific slot and
        // delete the old individual entry so the fallback in retrieve(for:)
        // won't re-migrate it on subsequent calls for other providers.
        if let legacyValue = try retrieve(for: .aiAPIKey), !legacyValue.isEmpty {
            try mutateConsolidated { consolidated in
                setValue(legacyValue, in: &consolidated, for: providerKey)
                setValue(nil, in: &consolidated, for: .aiAPIKey)
                return true
            }

            let allServices = [serviceIdentifier] + legacyServiceIdentifiers
            for serviceId in allServices {
                try? delete(account: Key.aiAPIKey.rawValue, serviceIdentifier: serviceId)
            }

            return legacyValue
        }

        return nil
    }

    static func retrieveAPIKeys(for providers: [AIProvider]) throws -> [AIProvider: String] {
        var valuesByProvider: [AIProvider: String] = [:]

        for provider in providers {
            let normalizedAPIKey = try retrieveAPIKey(for: provider)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                let apiKey = normalizedAPIKey,
                !apiKey.isEmpty
            else {
                continue
            }
            valuesByProvider[provider] = apiKey
        }

        return valuesByProvider
    }

    static func existsAPIKey(for provider: AIProvider) -> Bool {
        let providerKey = apiKeyKey(for: provider)
        let allServices = [serviceIdentifier] + legacyServiceIdentifiers

        do {
            let consolidated = try loadConsolidated()
            if keyValue(in: consolidated, for: providerKey) != nil {
                return true
            }
            if keyValue(in: consolidated, for: .aiAPIKey) != nil {
                return true
            }
        } catch {
            return allServices.contains { exists(account: providerKey.rawValue, serviceIdentifier: $0) }
                || allServices.contains { exists(account: Key.aiAPIKey.rawValue, serviceIdentifier: $0) }
        }

        return allServices.contains { exists(account: providerKey.rawValue, serviceIdentifier: $0) }
            || allServices.contains { exists(account: Key.aiAPIKey.rawValue, serviceIdentifier: $0) }
    }

    static func transcriptionAPIKeyKey(for provider: TranscriptionProvider) -> Key? {
        switch provider {
        case .local:
            nil
        case .groq:
            .aiAPIKeyGroq
        case .elevenLabs:
            .transcriptionAPIKeyElevenLabs
        }
    }

    static func storeTranscriptionAPIKey(_ value: String, for provider: TranscriptionProvider) throws {
        guard let key = transcriptionAPIKeyKey(for: provider) else { return }
        try store(value, for: key)
    }

    static func retrieveTranscriptionAPIKey(for provider: TranscriptionProvider) throws -> String? {
        guard let key = transcriptionAPIKeyKey(for: provider) else { return nil }
        return key == .aiAPIKeyGroq ? try retrieveAPIKey(for: .groq) : try retrieve(for: key)
    }

    static func existsTranscriptionAPIKey(for provider: TranscriptionProvider) -> Bool {
        guard let key = transcriptionAPIKeyKey(for: provider) else { return true }
        return key == .aiAPIKeyGroq ? existsAPIKey(for: .groq) : exists(for: key)
    }

    static func deleteTranscriptionAPIKey(for provider: TranscriptionProvider) throws {
        guard let key = transcriptionAPIKeyKey(for: provider) else { return }
        try delete(for: key)
    }

    static func registrationAPIKeyAccount(for registrationID: UUID) -> String {
        "\(providerRegistrationAccountPrefix)\(registrationID.uuidString.lowercased())"
    }

    static func storeAPIKey(_ value: String, for registrationID: UUID) throws {
        let account = registrationAPIKeyAccount(for: registrationID)
        try mutateConsolidated { consolidated in
            guard consolidated.registrationKeys[account] != value else { return false }
            consolidated.registrationKeys[account] = value
            return true
        }

        for serviceId in [serviceIdentifier] + legacyServiceIdentifiers {
            try? delete(account: account, serviceIdentifier: serviceId)
        }
    }

    static func retrieveAPIKey(for registrationID: UUID) throws -> String? {
        let account = registrationAPIKeyAccount(for: registrationID)

        let consolidated = try loadConsolidated()
        if let value = consolidated.registrationKeys[account], !value.isEmpty {
            return value
        }

        for serviceId in [serviceIdentifier] + legacyServiceIdentifiers {
            guard let legacyValue = try retrieve(account: account, serviceIdentifier: serviceId),
                  !legacyValue.isEmpty
            else {
                continue
            }

            try mutateConsolidated { mutableConsolidated in
                mutableConsolidated.registrationKeys[account] = legacyValue
                return true
            }
            try? delete(account: account, serviceIdentifier: serviceId)
            return legacyValue
        }

        return nil
    }

    static func retrieveAPIKeys(for registrationIDs: [UUID]) throws -> [UUID: String] {
        let consolidated = try loadConsolidated()
        var mutableConsolidated = consolidated
        var valuesByRegistrationID: [UUID: String] = [:]
        var migratedAccounts: [(account: String, serviceIdentifier: String)] = []

        for registrationID in registrationIDs {
            let account = registrationAPIKeyAccount(for: registrationID)
            let consolidatedValue = mutableConsolidated.registrationKeys[account]
            let legacyValue: String?

            if consolidatedValue == nil {
                legacyValue = try legacyRegistrationAPIKey(for: account, migratedAccounts: &migratedAccounts)
                if let legacyValue, !legacyValue.isEmpty {
                    mutableConsolidated.registrationKeys[account] = legacyValue
                }
            } else {
                legacyValue = nil
            }

            let normalizedAPIKey = (consolidatedValue ?? legacyValue)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                let apiKey = normalizedAPIKey,
                !apiKey.isEmpty
            else {
                continue
            }
            valuesByRegistrationID[registrationID] = apiKey
        }

        if mutableConsolidated.registrationKeys != consolidated.registrationKeys {
            try mutateConsolidated { consolidated in
                for migratedAccount in migratedAccounts {
                    consolidated.registrationKeys[migratedAccount.account] =
                        mutableConsolidated.registrationKeys[migratedAccount.account]
                }
                return true
            }
            for migratedAccount in migratedAccounts {
                try? delete(account: migratedAccount.account, serviceIdentifier: migratedAccount.serviceIdentifier)
            }
        }

        return valuesByRegistrationID
    }

    static func existsAPIKey(for registrationID: UUID) -> Bool {
        let account = registrationAPIKeyAccount(for: registrationID)
        do {
            let consolidated = try loadConsolidated()
            if consolidated.registrationKeys[account] != nil {
                return true
            }
        } catch {
            return exists(account: account, serviceIdentifier: serviceIdentifier)
                || legacyServiceIdentifiers.contains {
                    exists(account: account, serviceIdentifier: $0)
                }
        }

        if exists(account: account, serviceIdentifier: serviceIdentifier) {
            return true
        }
        return legacyServiceIdentifiers.contains {
            exists(account: account, serviceIdentifier: $0)
        }
    }

    static func deleteAPIKey(for registrationID: UUID) throws {
        let account = registrationAPIKeyAccount(for: registrationID)
        try mutateConsolidated { consolidated in
            consolidated.registrationKeys.removeValue(forKey: account) != nil
        }

        if AppIdentity.isRunningTests {
            return
        }

        try delete(account: account, serviceIdentifier: serviceIdentifier)
        for legacyServiceIdentifier in legacyServiceIdentifiers {
            try delete(account: account, serviceIdentifier: legacyServiceIdentifier)
        }
    }

    private static func legacyRegistrationAPIKey(
        for account: String,
        migratedAccounts: inout [(account: String, serviceIdentifier: String)]
    ) throws -> String? {
        for serviceId in [serviceIdentifier] + legacyServiceIdentifiers {
            guard let legacyValue = try retrieve(account: account, serviceIdentifier: serviceId),
                  !legacyValue.isEmpty
            else {
                continue
            }

            migratedAccounts.append((account, serviceId))
            return legacyValue
        }

        return nil
    }
}

public extension KeychainManager {
    @available(*, deprecated, message: "Use retrieveAPIKeys(for:) or retrieveAPIKeysMap(allowedProviders:) instead")
    static func mapAPIKeyItems(
        _ items: [[String: Any]],
        allowedProviders: [AIProvider]
    ) -> [AIProvider: String] {
        let accountToProvider = Dictionary(uniqueKeysWithValues: allowedProviders.map {
            (apiKeyKey(for: $0).rawValue, $0)
        })
        var valuesByProvider: [AIProvider: String] = [:]

        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  let provider = accountToProvider[account],
                  let rawData = item[kSecValueData as String] as? Data,
                  let rawValue = String(data: rawData, encoding: .utf8)
            else {
                continue
            }

            let apiKey = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else { continue }
            valuesByProvider[provider] = apiKey
        }

        return valuesByProvider
    }

    /// Reads API keys from consolidated storage for the given providers.
    /// This is the consolidated-aware replacement for `mapAPIKeyItems(allowedProviders:)`.
    static func retrieveAPIKeysMap(allowedProviders: [AIProvider]) throws -> [AIProvider: String] {
        let consolidated = try loadConsolidated()
        var valuesByProvider: [AIProvider: String] = [:]

        for provider in allowedProviders {
            let key = apiKeyKey(for: provider)
            let apiKey = keyValue(in: consolidated, for: key)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let apiKey, !apiKey.isEmpty else { continue }
            valuesByProvider[provider] = apiKey
        }

        return valuesByProvider
    }
}
