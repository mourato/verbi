@testable import VerbiCore
import Foundation

final class MockKeychainProvider: KeychainProvider, @unchecked Sendable {
    private var values: [KeychainManager.Key: String] = [:]
    private var registrationValues: [UUID: String] = [:]
    private(set) var retrieveAPIKeyCallCount = 0
    private(set) var retrieveAPIKeysCallCount = 0
    private(set) var existsAPIKeyCallCount = 0

    func store(_ value: String, for key: KeychainManager.Key) throws {
        values[key] = value
    }

    func retrieve(for key: KeychainManager.Key) throws -> String? {
        values[key]
    }

    func delete(for key: KeychainManager.Key) throws {
        values.removeValue(forKey: key)
    }

    func exists(for key: KeychainManager.Key) -> Bool {
        values[key] != nil
    }

    func retrieveAPIKey(for provider: LLMProvider) throws -> String? {
        retrieveAPIKeyCallCount += 1
        let providerKey = KeychainManager.apiKeyKey(for: provider)
        if let value = values[providerKey], !value.isEmpty {
            return value
        }

        if let legacyValue = values[.aiAPIKey], !legacyValue.isEmpty {
            values[providerKey] = legacyValue
            values.removeValue(forKey: .aiAPIKey)
            return legacyValue
        }

        return nil
    }

    func retrieveAPIKeys(for providers: [LLMProvider]) throws -> [LLMProvider: String] {
        retrieveAPIKeysCallCount += 1
        return providers.reduce(into: [LLMProvider: String]()) { result, provider in
            let key = KeychainManager.apiKeyKey(for: provider)
            guard let value = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty
            else {
                return
            }
            result[provider] = value
        }
    }

    func existsAPIKey(for provider: LLMProvider) -> Bool {
        existsAPIKeyCallCount += 1
        let providerKey = KeychainManager.apiKeyKey(for: provider)
        return values[providerKey] != nil || values[.aiAPIKey] != nil
    }

    func storeAPIKey(_ value: String, for registrationID: UUID) throws {
        registrationValues[registrationID] = value
    }

    func retrieveAPIKey(for registrationID: UUID) throws -> String? {
        registrationValues[registrationID]
    }

    func retrieveAPIKeys(for registrationIDs: [UUID]) throws -> [UUID: String] {
        registrationIDs.reduce(into: [UUID: String]()) { result, registrationID in
            guard let value = registrationValues[registrationID]?.trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty
            else {
                return
            }
            result[registrationID] = value
        }
    }

    func existsAPIKey(for registrationID: UUID) -> Bool {
        registrationValues[registrationID] != nil
    }

    func deleteAPIKey(for registrationID: UUID) throws {
        registrationValues.removeValue(forKey: registrationID)
    }
}

final class MockLLMService: LLMService, @unchecked Sendable {
    var fetchModelsResult: [LLMModel] = []
    var fetchModelsResultsByProvider: [LLMProvider: [LLMModel]] = [:]
    var fetchModelsError: Error?
    var verifyConnectionResult = true
    var validateURLResult = URL(string: "https://api.openai.com/v1")

    private(set) var fetchCallCount = 0
    private(set) var lastFetchedAPIKey: String?
    private(set) var lastFetchedProvider: LLMProvider?
    private(set) var lastVerifyConnectionAPIKey: String?

    func validateURL(_ urlString: String) -> URL? {
        validateURLResult
    }

    func fetchAvailableModels(baseURL: URL, apiKey: String, provider: LLMProvider) async throws -> [LLMModel] {
        await Task.yield()
        fetchCallCount += 1
        lastFetchedAPIKey = apiKey
        lastFetchedProvider = provider
        if let fetchModelsError {
            throw fetchModelsError
        }
        if let providerModels = fetchModelsResultsByProvider[provider] {
            return providerModels
        }
        return fetchModelsResult
    }

    func verifyConnection(baseURL: URL, apiKey: String, provider: LLMProvider) async throws -> Bool {
        await Task.yield()
        lastVerifyConnectionAPIKey = apiKey
        return verifyConnectionResult
    }
}

extension LLMModel {
    static func fixture(id: String) -> LLMModel? {
        let payload = #"{"id":"\#(id)"}"#
        guard let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LLMModel.self, from: data)
    }
}
