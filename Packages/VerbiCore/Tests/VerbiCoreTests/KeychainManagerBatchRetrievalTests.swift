@testable import VerbiCore
import XCTest

final class KeychainManagerBatchRetrievalTests: XCTestCase {
    override func setUp() {
        super.setUp()
        KeychainManager.invalidateCache()
    }

    func testProviderAPIKey_CanOverwriteExistingConsolidatedValue() throws {
        let keychain = DefaultKeychainProvider()
        let key = KeychainManager.apiKeyKey(for: .groq)

        try? keychain.delete(for: key)
        defer { try? keychain.delete(for: key) }

        try keychain.store("sk-groq-initial", for: key)
        try keychain.store("sk-groq-updated", for: key)

        XCTAssertEqual(try keychain.retrieveAPIKey(for: .groq), "sk-groq-updated")
    }

    func testConcurrentProviderAndRegistrationWritesPreserveBothValues() throws {
        let keychain = DefaultKeychainProvider()
        let key = KeychainManager.apiKeyKey(for: .groq)
        let registrationID = UUID()
        try? keychain.delete(for: key)
        try? KeychainManager.deleteAPIKey(for: registrationID)
        defer {
            try? keychain.delete(for: key)
            try? KeychainManager.deleteAPIKey(for: registrationID)
        }

        let errors = ThreadSafeErrorCollector()
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            do {
                if index == 0 {
                    try DefaultKeychainProvider().store("sk-groq-provider", for: .aiAPIKeyGroq)
                } else {
                    try KeychainManager.storeAPIKey("sk-registration", for: registrationID)
                }
            } catch {
                errors.append(error)
            }
        }
        if let error = errors.first {
            throw error
        }

        XCTAssertEqual(try keychain.retrieveAPIKey(for: .groq), "sk-groq-provider")
        XCTAssertEqual(try KeychainManager.retrieveAPIKey(for: registrationID), "sk-registration")
    }

    func testRegistrationAPIKeyAccount_IsStableLowercaseKey() throws {
        let registrationID = try XCTUnwrap(UUID(uuidString: "9E6F0DB4-7B48-4599-A7C5-47CB7C2F368A"))

        XCTAssertEqual(
            KeychainManager.registrationAPIKeyAccount(for: registrationID),
            "ai_api_key_registration_9e6f0db4-7b48-4599-a7c5-47cb7c2f368a",
        )
    }

    func testTranscriptionAPIKeyKey_UsesSharedGroqKey() {
        XCTAssertEqual(KeychainManager.transcriptionAPIKeyKey(for: .groq), .aiAPIKeyGroq)
    }

    func testTranscriptionAPIKeyKey_UsesElevenLabsTranscriptionKey() {
        XCTAssertEqual(
            KeychainManager.transcriptionAPIKeyKey(for: .elevenLabs),
            .transcriptionAPIKeyElevenLabs,
        )
    }

    func testTranscriptionAPIKeyKey_ReturnsNilForLocalProvider() {
        XCTAssertNil(KeychainManager.transcriptionAPIKeyKey(for: .local))
    }

    func testRegistrationAPIKeys_StoreRetrieveBatchAndDelete() throws {
        let registrationID = UUID()
        let apiKey = "sk-registration-\(registrationID.uuidString)"
        try? KeychainManager.deleteAPIKey(for: registrationID)
        defer { try? KeychainManager.deleteAPIKey(for: registrationID) }

        try KeychainManager.storeAPIKey(apiKey, for: registrationID)

        XCTAssertTrue(KeychainManager.existsAPIKey(for: registrationID))
        XCTAssertEqual(try KeychainManager.retrieveAPIKey(for: registrationID), apiKey)
        XCTAssertEqual(try KeychainManager.retrieveAPIKeys(for: [registrationID]), [registrationID: apiKey])

        try KeychainManager.deleteAPIKey(for: registrationID)

        XCTAssertFalse(KeychainManager.existsAPIKey(for: registrationID))
        XCTAssertNil(try KeychainManager.retrieveAPIKey(for: registrationID))
        XCTAssertEqual(try KeychainManager.retrieveAPIKeys(for: [registrationID]), [:])
    }

    func testRetrieveAPIKeysMap_ReturnsStoredAllowedProviders() throws {
        let keychain = DefaultKeychainProvider()
        let openAIKey = KeychainManager.apiKeyKey(for: .openai)
        let googleKey = KeychainManager.apiKeyKey(for: .google)

        try? keychain.delete(for: openAIKey)
        try? keychain.delete(for: googleKey)
        defer {
            try? keychain.delete(for: openAIKey)
            try? keychain.delete(for: googleKey)
        }

        try keychain.store("sk-openai", for: openAIKey)
        try keychain.store("sk-google", for: googleKey)

        let mapped = try KeychainManager.retrieveAPIKeysMap(allowedProviders: [.openai, .google, .anthropic])

        XCTAssertEqual(mapped[.openai], "sk-openai")
        XCTAssertEqual(mapped[.google], "sk-google")
        XCTAssertNil(mapped[.anthropic])
    }

    func testRetrieveAPIKeysMap_IgnoresProvidersWithoutStoredValues() throws {
        let keychain = DefaultKeychainProvider()
        let anthropicKey = KeychainManager.apiKeyKey(for: .anthropic)

        try? keychain.delete(for: anthropicKey)
        defer { try? keychain.delete(for: anthropicKey) }

        try keychain.store("sk-anthropic", for: anthropicKey)

        let mapped = try KeychainManager.retrieveAPIKeysMap(allowedProviders: [.openai, .anthropic])
        XCTAssertEqual(mapped.count, 1)
        XCTAssertEqual(mapped[.anthropic], "sk-anthropic")
        XCTAssertNil(mapped[.openai])
    }

    func testRetrieveAPIKeysMap_ReturnsEmptyWhenNothingIsStored() throws {
        let keychain = DefaultKeychainProvider()
        let openAIKey = KeychainManager.apiKeyKey(for: .openai)
        let googleKey = KeychainManager.apiKeyKey(for: .google)

        try? keychain.delete(for: openAIKey)
        try? keychain.delete(for: googleKey)

        let mapped = try KeychainManager.retrieveAPIKeysMap(allowedProviders: [.openai, .google])
        XCTAssertTrue(mapped.isEmpty)
    }
}

private final class ThreadSafeErrorCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [Error] = []

    var first: Error? {
        lock.withLock {
            errors.first
        }
    }

    func append(_ error: Error) {
        lock.withLock {
            errors.append(error)
        }
    }
}
