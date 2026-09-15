import Foundation
import MeetingAssistantCoreCommon
import Security

public enum KeychainManager {
    // MARK: - Constants

    static let serviceIdentifier = AppIdentity.keychainServiceIdentifier
    static let legacyServiceIdentifiers = AppIdentity.legacyKeychainServiceIdentifiers
    static let providerRegistrationAccountPrefix = "ai_api_key_registration_"
    private static let consolidatedAccount = "prisma_consolidated_api_keys_v1"
    private static let legacyConsolidatedAccount = "prisma_consolidated_api_keys"
    private static let legacyConsolidatedMigrationKey = "keychain.legacy_consolidated_api_keys.migrated"

    // MARK: - Cache

    private static let cacheLock = NSRecursiveLock()
    private nonisolated(unsafe) static var _consolidatedCache: ConsolidatedAPIKeys?
    private nonisolated(unsafe) static var testingConsolidatedStore: ConsolidatedAPIKeys?

    public static func invalidateCache() {
        cacheLock.withLock {
            _consolidatedCache = nil
            if AppIdentity.isRunningTests {
                testingConsolidatedStore = nil
            }
        }
    }

    // MARK: - Keys

    /// Known keys for Keychain storage.
    public enum Key: String, CaseIterable {
        case aiAPIKey = "ai_api_key"
        case aiAPIKeyOpenAI = "ai_api_key_openai"
        case aiAPIKeyAnthropic = "ai_api_key_anthropic"
        case aiAPIKeyGroq = "ai_api_key_groq"
        case aiAPIKeyGoogle = "ai_api_key_google"
        case aiAPIKeyCustom = "ai_api_key_custom"
        case transcriptionAPIKeyElevenLabs = "transcription_api_key_elevenlabs"
    }

    // MARK: - Consolidated Storage Model

    struct ConsolidatedAPIKeys: Codable, Equatable {
        static let currentVersion = 1

        var version: Int = Self.currentVersion
        var providerKeys: [String: String] = [:]
        var transcriptionKeys: [String: String] = [:]
        var registrationKeys: [String: String] = [:]
        var legacyUnifiedKey: String?

        enum CodingKeys: String, CodingKey {
            case version
            case providerKeys
            case transcriptionKeys
            case registrationKeys
            case legacyUnifiedKey
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
            providerKeys = try container.decodeIfPresent([String: String].self, forKey: .providerKeys) ?? [:]
            transcriptionKeys = try container.decodeIfPresent([String: String].self, forKey: .transcriptionKeys) ?? [:]
            registrationKeys = try container.decodeIfPresent([String: String].self, forKey: .registrationKeys) ?? [:]
            legacyUnifiedKey = try container.decodeIfPresent(String.self, forKey: .legacyUnifiedKey)
        }
    }

    // MARK: - Errors

    /// Errors that can occur during Keychain operations.
    public enum KeychainError: LocalizedError {
        case unableToConvertToData
        case unableToConvertFromData
        case itemNotFound
        case unexpectedStatus(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .unableToConvertToData:
                "Unable to convert string to data"
            case .unableToConvertFromData:
                "Unable to convert data to string"
            case .itemNotFound:
                "Item not found in Keychain"
            case let .unexpectedStatus(status):
                "Keychain error: \(status)"
            }
        }
    }

    // MARK: - Consolidated Storage

    static func loadConsolidated() throws -> ConsolidatedAPIKeys {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cache = _consolidatedCache {
            return cache
        }

        if AppIdentity.isRunningTests {
            let store = testingConsolidatedStore ?? ConsolidatedAPIKeys()
            testingConsolidatedStore = store
            _consolidatedCache = store
            return store
        }

        do {
            if let existing = try retrieveConsolidatedBlob() {
                let migrated = try migrateLegacyConsolidatedBlobIfNeeded(into: existing)
                if migrated.version != ConsolidatedAPIKeys.currentVersion {
                    AppLogger.warning(
                        "Consolidated API keys version mismatch: \(migrated.version) != \(ConsolidatedAPIKeys.currentVersion)",
                        category: .security
                    )
                }
                _consolidatedCache = migrated
                return migrated
            }
        } catch {
            AppLogger.error(
                "Failed to decode consolidated API keys blob, will re-migrate",
                category: .security,
                error: error
            )
        }

        let migrated = try migrateToConsolidated()
        _consolidatedCache = migrated
        return migrated
    }

    private static func migrateLegacyConsolidatedBlobIfNeeded(
        into current: ConsolidatedAPIKeys
    ) throws -> ConsolidatedAPIKeys {
        guard !UserDefaults.standard.bool(forKey: legacyConsolidatedMigrationKey) else {
            return current
        }

        let legacy: ConsolidatedAPIKeys?
        do {
            legacy = try retrieveConsolidatedBlob(account: legacyConsolidatedAccount)
        } catch {
            AppLogger.error(
                "Failed to decode legacy consolidated API keys blob",
                category: .security,
                error: error
            )
            return current
        }

        guard let legacy else {
            UserDefaults.standard.set(true, forKey: legacyConsolidatedMigrationKey)
            return current
        }

        let merged = Self.mergeMissingValues(from: legacy, into: current)
        if merged != current {
            try saveConsolidated(merged)
            guard let persisted = try retrieveConsolidatedBlob(), persisted == merged else {
                throw KeychainError.unexpectedStatus(errSecDecode)
            }
        }

        UserDefaults.standard.set(true, forKey: legacyConsolidatedMigrationKey)
        AppLogger.info(
            "Recovered legacy consolidated API keys",
            category: .security,
            extra: [
                "providerCount": String(merged.providerKeys.count),
                "transcriptionCount": String(merged.transcriptionKeys.count),
                "registrationCount": String(merged.registrationKeys.count)
            ]
        )
        return merged
    }

    static func mergeMissingValues(
        from legacy: ConsolidatedAPIKeys,
        into current: ConsolidatedAPIKeys
    ) -> ConsolidatedAPIKeys {
        var merged = current
        for (key, value) in legacy.providerKeys where merged.providerKeys[key] == nil {
            merged.providerKeys[key] = value
        }
        for (key, value) in legacy.transcriptionKeys where merged.transcriptionKeys[key] == nil {
            merged.transcriptionKeys[key] = value
        }
        for (key, value) in legacy.registrationKeys where merged.registrationKeys[key] == nil {
            merged.registrationKeys[key] = value
        }
        if merged.legacyUnifiedKey == nil {
            merged.legacyUnifiedKey = legacy.legacyUnifiedKey
        }
        return merged
    }

    private static func saveConsolidated(_ keys: ConsolidatedAPIKeys) throws {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if AppIdentity.isRunningTests {
            testingConsolidatedStore = keys
            _consolidatedCache = keys
            return
        }

        let data = try JSONEncoder().encode(keys)
        try storeConsolidatedBlob(data)
        _consolidatedCache = keys
    }

    @discardableResult
    static func mutateConsolidated(
        _ mutation: (inout ConsolidatedAPIKeys) throws -> Bool
    ) throws -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        var consolidated = try loadConsolidated()
        let shouldSave = try mutation(&consolidated)
        guard shouldSave else { return false }

        try saveConsolidated(consolidated)
        return true
    }

    private static func retrieveConsolidatedBlob(account: String = consolidatedAccount) throws -> ConsolidatedAPIKeys? {
        var query = baseQuery(account: account, serviceIdentifier: serviceIdentifier)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let keys = try? JSONDecoder().decode(ConsolidatedAPIKeys.self, from: data)
            else {
                throw KeychainError.unableToConvertFromData
            }
            return keys
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private static func storeConsolidatedBlob(_ data: Data) throws {
        let query = baseQuery(account: consolidatedAccount, serviceIdentifier: serviceIdentifier)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            AppLogger.debug("Updated consolidated API keys blob", category: .security)
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecDuplicateItem {
                AppLogger.warning(
                    "Consolidated API keys add hit duplicate item; retrying update",
                    category: .security
                )
                let retryStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
                guard retryStatus == errSecSuccess else {
                    AppLogger.error(
                        "Failed to retry consolidated API keys update: \(retryStatus)",
                        category: .security
                    )
                    throw KeychainError.unexpectedStatus(retryStatus)
                }
                AppLogger.debug("Updated consolidated API keys blob after duplicate add", category: .security)
                return
            }

            guard addStatus == errSecSuccess else {
                AppLogger.error(
                    "Failed to add consolidated API keys blob: \(addStatus)",
                    category: .security
                )
                throw KeychainError.unexpectedStatus(addStatus)
            }
            AppLogger.debug("Added consolidated API keys blob", category: .security)
        default:
            AppLogger.error(
                "Failed to update consolidated API keys blob: \(updateStatus)",
                category: .security
            )
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    private static func migrateToConsolidated() throws -> ConsolidatedAPIKeys {
        var keys = ConsolidatedAPIKeys()
        let allServices = [serviceIdentifier] + legacyServiceIdentifiers

        do {
            if let legacy = try retrieveConsolidatedBlob(account: legacyConsolidatedAccount) {
                keys = Self.mergeMissingValues(from: legacy, into: keys)
            }
        } catch {
            AppLogger.error(
                "Failed to decode legacy consolidated API keys blob during migration",
                category: .security,
                error: error
            )
        }

        for provider in AIProvider.allCases {
            let key = apiKeyKey(for: provider)
            for serviceId in allServices {
                guard let value = try retrieve(account: key.rawValue, serviceIdentifier: serviceId),
                      !value.isEmpty
                else { continue }
                if keys.providerKeys[provider.rawValue] == nil {
                    keys.providerKeys[provider.rawValue] = value
                }
                break
            }
        }

        for serviceId in allServices {
            guard let value = try retrieve(account: Key.transcriptionAPIKeyElevenLabs.rawValue, serviceIdentifier: serviceId),
                  !value.isEmpty
            else { continue }
            if keys.transcriptionKeys[TranscriptionProvider.elevenLabs.rawValue] == nil {
                keys.transcriptionKeys[TranscriptionProvider.elevenLabs.rawValue] = value
            }
            break
        }

        for serviceId in allServices {
            if let legacyValue = try retrieve(account: Key.aiAPIKey.rawValue, serviceIdentifier: serviceId),
               !legacyValue.isEmpty
            {
                if keys.legacyUnifiedKey == nil {
                    keys.legacyUnifiedKey = legacyValue
                }
                break
            }
        }

        let hasData = !keys.providerKeys.isEmpty || !keys.transcriptionKeys.isEmpty || keys.legacyUnifiedKey != nil
        if hasData {
            try saveConsolidated(keys)
            UserDefaults.standard.set(true, forKey: legacyConsolidatedMigrationKey)

            // Best-effort cleanup: old individual keys are no longer needed,
            // but failures don't affect correctness since loadConsolidated
            // will find them on fallback and re-migrate.
            let keysToDelete = Key.allCases.filter { $0 != .aiAPIKey }
            for key in keysToDelete {
                for serviceId in allServices {
                    try? delete(account: key.rawValue, serviceIdentifier: serviceId)
                }
            }
        }

        return keys
    }

    static func keyValue(in consolidated: ConsolidatedAPIKeys, for key: Key) -> String? {
        switch key {
        case .aiAPIKey:
            consolidated.legacyUnifiedKey
        case .aiAPIKeyOpenAI:
            consolidated.providerKeys[AIProvider.openai.rawValue]
        case .aiAPIKeyAnthropic:
            consolidated.providerKeys[AIProvider.anthropic.rawValue]
        case .aiAPIKeyGroq:
            consolidated.providerKeys[AIProvider.groq.rawValue]
        case .aiAPIKeyGoogle:
            consolidated.providerKeys[AIProvider.google.rawValue]
        case .aiAPIKeyCustom:
            consolidated.providerKeys[AIProvider.custom.rawValue]
        case .transcriptionAPIKeyElevenLabs:
            consolidated.transcriptionKeys[TranscriptionProvider.elevenLabs.rawValue]
        }
    }

    static func setValue(_ value: String?, in consolidated: inout ConsolidatedAPIKeys, for key: Key) {
        switch key {
        case .aiAPIKey:
            consolidated.legacyUnifiedKey = value
        case .aiAPIKeyOpenAI:
            consolidated.providerKeys[AIProvider.openai.rawValue] = value
        case .aiAPIKeyAnthropic:
            consolidated.providerKeys[AIProvider.anthropic.rawValue] = value
        case .aiAPIKeyGroq:
            consolidated.providerKeys[AIProvider.groq.rawValue] = value
        case .aiAPIKeyGoogle:
            consolidated.providerKeys[AIProvider.google.rawValue] = value
        case .aiAPIKeyCustom:
            consolidated.providerKeys[AIProvider.custom.rawValue] = value
        case .transcriptionAPIKeyElevenLabs:
            consolidated.transcriptionKeys[TranscriptionProvider.elevenLabs.rawValue] = value
        }
    }

    private static func retrieve(for key: Key, serviceIdentifier: String) throws -> String? {
        try retrieve(account: key.rawValue, serviceIdentifier: serviceIdentifier)
    }

    static func retrieve(account: String, serviceIdentifier: String) throws -> String? {
        var query = baseQuery(account: account, serviceIdentifier: serviceIdentifier)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8)
            else {
                throw KeychainError.unableToConvertFromData
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private static func delete(for key: Key, serviceIdentifier: String) throws {
        try delete(account: key.rawValue, serviceIdentifier: serviceIdentifier)
    }

    static func delete(account: String, serviceIdentifier: String) throws {
        let query = baseQuery(account: account, serviceIdentifier: serviceIdentifier)
        let status = SecItemDelete(query as CFDictionary)

        // Treat "not found" as success (nothing to delete)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private static func exists(for key: Key, serviceIdentifier: String) -> Bool {
        exists(account: key.rawValue, serviceIdentifier: serviceIdentifier)
    }

    static func exists(account: String, serviceIdentifier: String) -> Bool {
        var query = baseQuery(account: account, serviceIdentifier: serviceIdentifier)
        query[kSecReturnData as String] = false
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func baseQuery(for key: Key, serviceIdentifier: String) -> [String: Any] {
        baseQuery(account: key.rawValue, serviceIdentifier: serviceIdentifier)
    }

    private static func baseQuery(account: String, serviceIdentifier: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account
        ]
    }
}
