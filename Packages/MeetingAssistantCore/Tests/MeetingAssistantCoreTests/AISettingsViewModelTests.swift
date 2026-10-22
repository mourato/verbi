@testable import MeetingAssistantCore
import XCTest

@MainActor
final class AISettingsViewModelTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        settings = .shared
        settings.resetToDefaults()
        settings.updateAIConfiguration(
            provider: .openai,
            baseURL: LLMProvider.openai.defaultBaseURL,
            selectedModel: "",
        )
        settings.enhancementsAISelection = EnhancementsAISelection(
            provider: .openai,
            selectedModel: "",
        )
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
    }

    func testInitWithDeferredBootstrap_DoesNotReadKeychainOrFetchModels() async throws {
        let keychain = MockKeychainProvider()
        let llmService = MockLLMService()
        try keychain.store("sk-saved", for: KeychainManager.apiKeyKey(for: .openai))

        _ = AISettingsViewModel(
            settings: settings,
            keychain: keychain,
            llmService: llmService,
            credentialBootstrapPolicy: .deferredUserAction,
        )

        await Task.yield()

        XCTAssertEqual(llmService.fetchCallCount, 0)
        XCTAssertEqual(keychain.existsAPIKeyCallCount, 0)
        XCTAssertEqual(keychain.retrieveAPIKeyCallCount, 0)
        XCTAssertEqual(keychain.retrieveAPIKeysCallCount, 0)
    }

    func testRefreshModelsManually_TriggersFetchAndStoresLastRefreshStatus() async throws {
        let keychain = MockKeychainProvider()
        let llmService = MockLLMService()
        try? keychain.store("sk-saved", for: KeychainManager.apiKeyKey(for: .openai))
        llmService.fetchModelsResult = try [XCTUnwrap(LLMModel.fixture(id: "gpt-4o"))]

        let viewModel = AISettingsViewModel(settings: settings, keychain: keychain, llmService: llmService)

        await Task.yield()
        let previousFetchCount = llmService.fetchCallCount

        let refreshTask = viewModel.refreshModelsManually()
        await refreshTask.value

        XCTAssertGreaterThan(llmService.fetchCallCount, previousFetchCount)
        XCTAssertEqual(llmService.lastFetchedAPIKey, "sk-saved")
        XCTAssertEqual(viewModel.availableModels.map(\.id), ["gpt-4o"])
        XCTAssertTrue(viewModel.lastModelsRefreshSucceeded)
        XCTAssertNotNil(viewModel.lastModelsRefreshAt)
        XCTAssertNotNil(viewModel.modelsRefreshSummary)
    }

    func testRefreshModelsManually_OnFailureStoresErrorRefreshStatus() async {
        let keychain = MockKeychainProvider()
        let llmService = MockLLMService()
        try? keychain.store("sk-saved", for: KeychainManager.apiKeyKey(for: .openai))
        llmService.fetchModelsError = URLError(.timedOut)

        let viewModel = AISettingsViewModel(settings: settings, keychain: keychain, llmService: llmService)

        let refreshTask = viewModel.refreshModelsManually()
        await refreshTask.value

        XCTAssertFalse(viewModel.lastModelsRefreshSucceeded)
        XCTAssertNotNil(viewModel.lastModelsRefreshAt)
        XCTAssertEqual(viewModel.lastModelsRefreshResultText, "settings.ai.models.fetch_failed".localized)
        XCTAssertNotNil(viewModel.modelsFetchError)
    }

    func testTestAPIConnection_OnSuccessClearsPlaintextFromMemory() async {
        let keychain = MockKeychainProvider()
        let llmService = MockLLMService()
        llmService.testConnectionResult = true

        let viewModel = AISettingsViewModel(settings: settings, keychain: keychain, llmService: llmService)
        viewModel.apiKeyText = "sk-secret-value"

        let connectionTask = viewModel.testAPIConnection()
        await connectionTask.value

        XCTAssertEqual(llmService.lastConnectionTestAPIKey, "sk-secret-value")
        XCTAssertTrue(viewModel.isKeySaved)
        XCTAssertEqual(viewModel.apiKeyText, "")
        XCTAssertEqual(try keychain.retrieveAPIKey(for: .openai), "sk-secret-value")
    }

    func testTestAPIConnection_OnFailureStillClearsPlaintextFromMemory() async {
        let keychain = MockKeychainProvider()
        let llmService = MockLLMService()
        llmService.testConnectionResult = false

        let viewModel = AISettingsViewModel(settings: settings, keychain: keychain, llmService: llmService)
        viewModel.apiKeyText = "sk-failure-value"

        let connectionTask = viewModel.testAPIConnection()
        await connectionTask.value

        XCTAssertEqual(llmService.lastConnectionTestAPIKey, "sk-failure-value")
        XCTAssertFalse(viewModel.isKeySaved)
        XCTAssertEqual(viewModel.apiKeyText, "")
        guard case .failure = viewModel.connectionStatus else {
            XCTFail("Expected failure connection status")
            return
        }
    }

    func testSaveAPIKeyWithoutVerification_PersistsKeyAndMarksSaved() throws {
        let keychain = MockKeychainProvider()
        let viewModel = AISettingsViewModel(
            settings: settings,
            keychain: keychain,
            llmService: MockLLMService(),
            credentialBootstrapPolicy: .deferredUserAction,
        )
        viewModel.apiKeyText = "sk-custom-save-only"

        XCTAssertTrue(viewModel.saveAPIKeyWithoutVerification())
        XCTAssertEqual(try keychain.retrieveAPIKey(for: .openai), "sk-custom-save-only")
        XCTAssertTrue(viewModel.isKeySaved)
        XCTAssertEqual(viewModel.connectionStatus, .saved)
        XCTAssertEqual(viewModel.apiKeyText, "")
    }

    func testTestAPIConnection_UsesSavedKeyWhenNoPendingInput() async {
        let keychain = MockKeychainProvider()
        let llmService = MockLLMService()
        try? keychain.store("sk-existing", for: KeychainManager.apiKeyKey(for: .openai))
        llmService.testConnectionResult = true

        let viewModel = AISettingsViewModel(
            settings: settings,
            keychain: keychain,
            llmService: llmService,
            credentialBootstrapPolicy: .deferredUserAction,
        )

        await viewModel.testAPIConnection().value

        XCTAssertEqual(llmService.lastConnectionTestAPIKey, "sk-existing")
        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertTrue(viewModel.isKeySaved)
    }

    func testCustomProvider_UsesManualModelWithoutFetchingCatalog() async throws {
        settings.updateAIConfiguration(
            provider: .custom,
            baseURL: "https://custom.example/v1",
            selectedModel: "manual-chat-model",
        )
        let keychain = MockKeychainProvider()
        try keychain.store("sk-custom", for: KeychainManager.apiKeyKey(for: .custom))
        let llmService = MockLLMService()

        let viewModel = AISettingsViewModel(
            settings: settings,
            keychain: keychain,
            llmService: llmService,
        )

        await Task.yield()

        XCTAssertEqual(llmService.fetchCallCount, 0)
        XCTAssertEqual(viewModel.modelCatalogStatus, .unavailable)
        XCTAssertEqual(settings.aiConfiguration.selectedModel, "manual-chat-model")
        XCTAssertEqual(viewModel.connectionStatus, .saved)
    }

    func testCustomEnhancementsProvider_UsesManualModelWithoutFetchingCatalog() async throws {
        settings.updateAIConfiguration(
            provider: .custom,
            baseURL: "https://custom.example/v1",
            selectedModel: "manual-chat-model",
        )
        settings.enhancementsAISelection = EnhancementsAISelection(
            provider: .custom,
            selectedModel: "manual-chat-model",
        )
        let keychain = MockKeychainProvider()
        try keychain.store("sk-custom", for: KeychainManager.apiKeyKey(for: .custom))
        let llmService = MockLLMService()
        let viewModel = AISettingsViewModel(
            settings: settings,
            keychain: keychain,
            llmService: llmService,
        )

        await viewModel.fetchEnhancementsAvailableModels(provider: .custom)

        XCTAssertEqual(llmService.fetchCallCount, 0)
        XCTAssertEqual(viewModel.enhancementsModelCatalogStatus, .unavailable)
    }

    func testProviderChange_ClearsTransientAPIKeyInput() async {
        let keychain = MockKeychainProvider()
        let llmService = MockLLMService()

        let viewModel = AISettingsViewModel(settings: settings, keychain: keychain, llmService: llmService)
        viewModel.apiKeyText = "sk-temporary"

        settings.updateAIConfiguration(
            provider: .anthropic,
            baseURL: LLMProvider.anthropic.defaultBaseURL,
            selectedModel: "",
        )
        await Task.yield()

        XCTAssertEqual(viewModel.apiKeyText, "")
    }

    func testRefreshEnhancementsModels_UsesEnhancementsProvider() async throws {
        let keychain = MockKeychainProvider()
        let llmService = MockLLMService()
        try keychain.store("sk-google", for: KeychainManager.apiKeyKey(for: .google))
        llmService.fetchModelsResult = try [XCTUnwrap(LLMModel.fixture(id: "gemini-2.0-flash"))]

        settings.enhancementsAISelection = EnhancementsAISelection(
            provider: .google,
            selectedModel: "",
        )

        let viewModel = AISettingsViewModel(settings: settings, keychain: keychain, llmService: llmService)
        viewModel.refreshEnhancementsProviderCredentialState()
        let refreshTask = viewModel.refreshEnhancementsModelsManually()
        await refreshTask.value

        XCTAssertEqual(llmService.lastFetchedProvider, .google)
        XCTAssertEqual(viewModel.enhancementsAvailableModels.map(\.id), ["gemini-2.0-flash"])
    }

    func testUpdatingEnhancementsSelection_DoesNotChangeDefaultAPISelection() {
        settings.updateAIConfiguration(
            provider: .openai,
            baseURL: LLMProvider.openai.defaultBaseURL,
            selectedModel: "gpt-4o-mini",
        )

        settings.updateEnhancementsProvider(.anthropic)
        settings.updateEnhancementsSelectedModel("claude-3-7-sonnet")

        XCTAssertEqual(settings.aiConfiguration.selectedModel, "gpt-4o-mini")
        XCTAssertEqual(settings.enhancementsAISelection.provider, .anthropic)
        XCTAssertEqual(settings.enhancementsAISelection.selectedModel, "claude-3-7-sonnet")
    }

    func testPrepareEnhancementsProvider_UpdatesActiveProviderWithoutMutatingMeetingSelection() {
        settings.enhancementsAISelection = EnhancementsAISelection(
            provider: .openai,
            selectedModel: "gpt-4o-mini",
        )

        let viewModel = AISettingsViewModel(settings: settings, keychain: MockKeychainProvider(), llmService: MockLLMService())

        viewModel.prepareEnhancementsProvider(.anthropic)

        XCTAssertEqual(viewModel.activeEnhancementsProvider, .anthropic)
        XCTAssertEqual(settings.enhancementsAISelection.provider, .openai)
        XCTAssertEqual(settings.enhancementsAISelection.selectedModel, "gpt-4o-mini")
    }

    func testTestEnhancementsAPIConnection_OnSuccessPersistsProviderKey() async throws {
        let keychain = MockKeychainProvider()
        let llmService = MockLLMService()
        llmService.testConnectionResult = true
        settings.enhancementsAISelection = EnhancementsAISelection(
            provider: .openai,
            selectedModel: "gpt-4o-mini",
        )

        let viewModel = AISettingsViewModel(settings: settings, keychain: keychain, llmService: llmService)
        viewModel.enhancementsAPIKeyText = "sk-enhancements"

        let task = viewModel.testEnhancementsAPIConnection()
        await task.value

        XCTAssertEqual(try keychain.retrieveAPIKey(for: .openai), "sk-enhancements")
        XCTAssertEqual(viewModel.enhancementsConnectionStatus, .success)
        XCTAssertTrue(viewModel.isEnhancementsProviderKeySaved)
        XCTAssertEqual(viewModel.enhancementsAPIKeyText, "")
        XCTAssertEqual(llmService.lastConnectionTestAPIKey, "sk-enhancements")
    }

    func testSaveEnhancementsAPIKey_BuiltInRegistrationPersistsProviderKey() throws {
        let keychain = MockKeychainProvider()
        let registration = try XCTUnwrap(settings.addEnhancementsProviderRegistration(provider: .groq))
        let viewModel = AISettingsViewModel(
            settings: settings,
            keychain: keychain,
            llmService: MockLLMService(),
            credentialBootstrapPolicy: .deferredUserAction,
        )

        XCTAssertTrue(
            viewModel.saveEnhancementsAPIKey(
                "sk-groq-shared",
                registrationID: registration.id,
                provider: .groq,
            ),
        )

        XCTAssertEqual(try keychain.retrieveAPIKey(for: .groq), "sk-groq-shared")
        XCTAssertNil(try keychain.retrieveAPIKey(for: registration.id))
        XCTAssertTrue(viewModel.hasSavedEnhancementsAPIKey(for: registration.id, provider: .groq))
    }

    func testRemoveEnhancementsAPIKey_BuiltInRegistrationRemovesProviderKey() throws {
        let keychain = MockKeychainProvider()
        let registration = try XCTUnwrap(settings.addEnhancementsProviderRegistration(provider: .groq))
        try keychain.store("sk-groq-shared", for: KeychainManager.apiKeyKey(for: .groq))
        try keychain.storeAPIKey("sk-stale-registration", for: registration.id)

        let viewModel = AISettingsViewModel(
            settings: settings,
            keychain: keychain,
            llmService: MockLLMService(),
            credentialBootstrapPolicy: .deferredUserAction,
        )

        viewModel.removeEnhancementsAPIKey(registrationID: registration.id, provider: .groq)

        XCTAssertNil(try keychain.retrieveAPIKey(for: .groq))
        XCTAssertNil(try keychain.retrieveAPIKey(for: registration.id))
        XCTAssertFalse(viewModel.hasSavedEnhancementsAPIKey(for: registration.id, provider: .groq))
    }

    func testRefreshEnhancementsProviderModels_UsesOnlyProvidersWithSavedKey() async throws {
        let keychain = MockKeychainProvider()
        let llmService = MockLLMService()
        try keychain.store("sk-openai", for: KeychainManager.apiKeyKey(for: .openai))
        try keychain.store("sk-google", for: KeychainManager.apiKeyKey(for: .google))
        llmService.fetchModelsResultsByProvider = try [
            .openai: [XCTUnwrap(LLMModel.fixture(id: "gpt-4o-mini"))],
            .google: [XCTUnwrap(LLMModel.fixture(id: "gemini-2.0-flash"))],
        ]

        let viewModel = AISettingsViewModel(
            settings: settings,
            keychain: keychain,
            llmService: llmService,
            credentialBootstrapPolicy: .deferredUserAction,
        )

        let task = viewModel.refreshEnhancementsProviderModelsManually()
        await task.value

        XCTAssertEqual(keychain.retrieveAPIKeysCallCount, 1)
        XCTAssertEqual(keychain.retrieveAPIKeyCallCount, 1) // One migration probe for active provider.
        XCTAssertTrue(
            viewModel.enhancementsProviderModels.contains(
                where: { $0.provider == .openai && $0.modelID == "gpt-4o-mini" },
            ),
        )
        XCTAssertTrue(
            viewModel.enhancementsProviderModels.contains(
                where: { $0.provider == .google && $0.modelID == "gemini-2.0-flash" },
            ),
        )
        XCTAssertFalse(
            viewModel.enhancementsProviderModels.contains(
                where: { $0.provider == .anthropic },
            ),
        )
    }

    func testRefreshEnhancementsProviderModels_BuiltInRegistrationIgnoresStaleRegistrationKey() async throws {
        let keychain = MockKeychainProvider()
        let llmService = MockLLMService()
        let registration = try XCTUnwrap(settings.addEnhancementsProviderRegistration(provider: .groq))
        try keychain.store("sk-groq-provider", for: KeychainManager.apiKeyKey(for: .groq))
        try keychain.storeAPIKey("sk-stale-registration", for: registration.id)
        llmService.fetchModelsResultsByProvider = try [
            .groq: [XCTUnwrap(LLMModel.fixture(id: "llama-3.3-70b-versatile"))],
        ]

        let viewModel = AISettingsViewModel(
            settings: settings,
            keychain: keychain,
            llmService: llmService,
            credentialBootstrapPolicy: .deferredUserAction,
        )

        let task = viewModel.refreshEnhancementsProviderModelsManually()
        await task.value

        XCTAssertEqual(llmService.lastFetchedAPIKey, "sk-groq-provider")
        XCTAssertTrue(
            viewModel.enhancementsProviderModels.contains(
                where: { $0.provider == .groq && $0.registrationID == registration.id },
            ),
        )
    }

    func testRefreshEnhancementsProviderModels_MigratesLegacyKeyBeforeBatch() async throws {
        let keychain = MockKeychainProvider()
        let llmService = MockLLMService()
        try keychain.store("sk-legacy-openai", for: .aiAPIKey)
        llmService.fetchModelsResultsByProvider = try [
            .openai: [XCTUnwrap(LLMModel.fixture(id: "gpt-4.1-mini"))],
        ]

        let viewModel = AISettingsViewModel(
            settings: settings,
            keychain: keychain,
            llmService: llmService,
            credentialBootstrapPolicy: .deferredUserAction,
        )

        let task = viewModel.refreshEnhancementsProviderModelsManually()
        await task.value

        XCTAssertNil(try keychain.retrieve(for: .aiAPIKey))
        XCTAssertEqual(try keychain.retrieve(for: .aiAPIKeyOpenAI), "sk-legacy-openai")
        XCTAssertEqual(keychain.retrieveAPIKeyCallCount, 1)
        XCTAssertEqual(keychain.retrieveAPIKeysCallCount, 1)
        XCTAssertTrue(
            viewModel.enhancementsProviderModels.contains(
                where: { $0.provider == .openai && $0.modelID == "gpt-4.1-mini" },
            ),
        )
    }
}

private final class MockKeychainProvider: KeychainProvider, @unchecked Sendable {
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

private final class MockLLMService: LLMService, @unchecked Sendable {
    var fetchModelsResult: [LLMModel] = []
    var fetchModelsResultsByProvider: [LLMProvider: [LLMModel]] = [:]
    var fetchModelsError: Error?
    var testConnectionResult = true
    var validateURLResult = URL(string: "https://api.openai.com/v1")

    private(set) var fetchCallCount = 0
    private(set) var lastFetchedAPIKey: String?
    private(set) var lastFetchedProvider: LLMProvider?
    private(set) var lastConnectionTestAPIKey: String?

    func validateURL(_ urlString: String) -> URL? {
        validateURLResult
    }

    func fetchAvailableModels(baseURL: URL, apiKey: String, provider: LLMProvider) async throws -> [LLMModel] {
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

    // test-hygiene: allow no-assertion protocol implementation in test mock, not a test
    func testConnection(baseURL: URL, apiKey: String, provider: LLMProvider) async throws -> Bool {
        lastConnectionTestAPIKey = apiKey
        return testConnectionResult
    }
}

private extension LLMModel {
    static func fixture(id: String) -> LLMModel? {
        let payload = #"{"id":"\#(id)"}"#
        guard let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LLMModel.self, from: data)
    }
}
