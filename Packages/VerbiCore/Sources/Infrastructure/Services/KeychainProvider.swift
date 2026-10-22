import Foundation
import Security
import VerbiCoreCommon

/// Secure storage for sensitive data using macOS Keychain.
/// Provides type-safe API for storing and retrieving secrets.
public protocol KeychainProvider: Sendable {
    func store(_ value: String, for key: KeychainManager.Key) throws
    func retrieve(for key: KeychainManager.Key) throws -> String?
    func delete(for key: KeychainManager.Key) throws
    func exists(for key: KeychainManager.Key) -> Bool
    func retrieveAPIKey(for provider: LLMProvider) throws -> String?
    func retrieveAPIKeys(for providers: [LLMProvider]) throws -> [LLMProvider: String]
    func existsAPIKey(for provider: LLMProvider) -> Bool
    func storeAPIKey(_ value: String, for registrationID: UUID) throws
    func retrieveAPIKey(for registrationID: UUID) throws -> String?
    func retrieveAPIKeys(for registrationIDs: [UUID]) throws -> [UUID: String]
    func existsAPIKey(for registrationID: UUID) -> Bool
    func deleteAPIKey(for registrationID: UUID) throws
    func storeTranscriptionAPIKey(_ value: String, for provider: TranscriptionProvider) throws
    func retrieveTranscriptionAPIKey(for provider: TranscriptionProvider) throws -> String?
    func existsTranscriptionAPIKey(for provider: TranscriptionProvider) -> Bool
    func deleteTranscriptionAPIKey(for provider: TranscriptionProvider) throws
}

public extension KeychainProvider {
    func retrieveAPIKeys(for providers: [LLMProvider]) throws -> [LLMProvider: String] {
        var valuesByProvider: [LLMProvider: String] = [:]

        for provider in providers {
            guard let apiKey = try retrieveAPIKey(for: provider)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !apiKey.isEmpty
            else {
                continue
            }
            valuesByProvider[provider] = apiKey
        }

        return valuesByProvider
    }

    func storeAPIKey(_ value: String, for registrationID: UUID) throws {
        try KeychainManager.storeAPIKey(value, for: registrationID)
    }

    func retrieveAPIKey(for registrationID: UUID) throws -> String? {
        try KeychainManager.retrieveAPIKey(for: registrationID)
    }

    func retrieveAPIKeys(for registrationIDs: [UUID]) throws -> [UUID: String] {
        try KeychainManager.retrieveAPIKeys(for: registrationIDs)
    }

    func existsAPIKey(for registrationID: UUID) -> Bool {
        KeychainManager.existsAPIKey(for: registrationID)
    }

    func deleteAPIKey(for registrationID: UUID) throws {
        try KeychainManager.deleteAPIKey(for: registrationID)
    }

    func storeTranscriptionAPIKey(_ value: String, for provider: TranscriptionProvider) throws {
        try KeychainManager.storeTranscriptionAPIKey(value, for: provider)
    }

    func retrieveTranscriptionAPIKey(for provider: TranscriptionProvider) throws -> String? {
        try KeychainManager.retrieveTranscriptionAPIKey(for: provider)
    }

    func existsTranscriptionAPIKey(for provider: TranscriptionProvider) -> Bool {
        KeychainManager.existsTranscriptionAPIKey(for: provider)
    }

    func deleteTranscriptionAPIKey(for provider: TranscriptionProvider) throws {
        try KeychainManager.deleteTranscriptionAPIKey(for: provider)
    }
}
