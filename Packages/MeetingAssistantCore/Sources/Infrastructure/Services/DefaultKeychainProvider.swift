import Foundation
import MeetingAssistantCoreCommon
import Security

public struct DefaultKeychainProvider: KeychainProvider {
    public init() {}
    public func store(_ value: String, for key: KeychainManager.Key) throws {
        try KeychainManager.store(value, for: key)
    }

    public func retrieve(for key: KeychainManager.Key) throws -> String? {
        try KeychainManager.retrieve(for: key)
    }

    public func delete(for key: KeychainManager.Key) throws {
        try KeychainManager.delete(for: key)
    }

    public func exists(for key: KeychainManager.Key) -> Bool {
        KeychainManager.exists(for: key)
    }

    public func retrieveAPIKey(for provider: LLMProvider) throws -> String? {
        try KeychainManager.retrieveAPIKey(for: provider)
    }

    public func retrieveAPIKeys(for providers: [LLMProvider]) throws -> [LLMProvider: String] {
        try KeychainManager.retrieveAPIKeys(for: providers)
    }

    public func existsAPIKey(for provider: LLMProvider) -> Bool {
        KeychainManager.existsAPIKey(for: provider)
    }

    public func storeAPIKey(_ value: String, for registrationID: UUID) throws {
        try KeychainManager.storeAPIKey(value, for: registrationID)
    }

    public func retrieveAPIKey(for registrationID: UUID) throws -> String? {
        try KeychainManager.retrieveAPIKey(for: registrationID)
    }

    public func retrieveAPIKeys(for registrationIDs: [UUID]) throws -> [UUID: String] {
        try KeychainManager.retrieveAPIKeys(for: registrationIDs)
    }

    public func existsAPIKey(for registrationID: UUID) -> Bool {
        KeychainManager.existsAPIKey(for: registrationID)
    }

    public func deleteAPIKey(for registrationID: UUID) throws {
        try KeychainManager.deleteAPIKey(for: registrationID)
    }

    public func storeTranscriptionAPIKey(_ value: String, for provider: TranscriptionProvider) throws {
        try KeychainManager.storeTranscriptionAPIKey(value, for: provider)
    }

    public func retrieveTranscriptionAPIKey(for provider: TranscriptionProvider) throws -> String? {
        try KeychainManager.retrieveTranscriptionAPIKey(for: provider)
    }

    public func existsTranscriptionAPIKey(for provider: TranscriptionProvider) -> Bool {
        KeychainManager.existsTranscriptionAPIKey(for: provider)
    }

    public func deleteTranscriptionAPIKey(for provider: TranscriptionProvider) throws {
        try KeychainManager.deleteTranscriptionAPIKey(for: provider)
    }
}
