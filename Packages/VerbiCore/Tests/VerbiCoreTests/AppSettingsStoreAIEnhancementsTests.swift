@testable import VerbiCore
import XCTest

@MainActor
final class AppSettingsStoreAIEnhancementsTests: AppSettingsStoreTestCase {
    func testResolvedEnhancementsConfigurationUsesProviderDefaults() {
        settings.enhancementsAISelection = EnhancementsAISelection(
            provider: .google,
            selectedModel: "gemini-2.0-flash",
        )

        let resolved = settings.resolvedEnhancementsAIConfiguration
        XCTAssertEqual(resolved.provider, .google)
        XCTAssertEqual(resolved.baseURL, LLMProvider.google.defaultBaseURL)
        XCTAssertEqual(resolved.selectedModel, "gemini-2.0-flash")
    }

    func testResolvedEnhancementsConfiguration_NormalizesLegacyGoogleModelID() {
        settings.enhancementsAISelection = EnhancementsAISelection(
            provider: .google,
            selectedModel: "models/gemini-2.0-flash-001",
        )

        let resolved = settings.resolvedEnhancementsAIConfiguration
        XCTAssertEqual(resolved.provider, .google)
        XCTAssertEqual(resolved.selectedModel, "gemini-2.0-flash")
    }

    func testResolvedEnhancementsConfigurationUsesAPIBaseURLForCustomProvider() {
        settings.updateAIConfiguration(provider: .custom, baseURL: "https://proxy.example.com/v1", selectedModel: "base")
        settings.enhancementsAISelection = EnhancementsAISelection(
            provider: .custom,
            selectedModel: "custom-model",
        )

        let resolved = settings.resolvedEnhancementsAIConfiguration
        XCTAssertEqual(resolved.provider, .custom)
        XCTAssertEqual(resolved.baseURL, "https://proxy.example.com/v1")
        XCTAssertEqual(resolved.selectedModel, "custom-model")
    }

    func testUpdateEnhancementsProviderClearsSelectedModel() {
        settings.enhancementsAISelection = EnhancementsAISelection(
            provider: .openai,
            selectedModel: "gpt-4o-mini",
        )

        settings.updateEnhancementsProvider(.anthropic)

        XCTAssertEqual(settings.enhancementsAISelection.provider, .anthropic)
        XCTAssertEqual(settings.enhancementsAISelection.selectedModel, "")
    }

    func testEnhancementsInferenceReadinessIssue_MissingModel() {
        settings.enhancementsAISelection = EnhancementsAISelection(
            provider: .openai,
            selectedModel: "   ",
        )

        let issue = settings.enhancementsInferenceReadinessIssue(apiKeyExists: { _ in true })

        XCTAssertEqual(issue, .missingModel)
    }

    func testEnhancementsInferenceReadinessIssue_ReturnsNilWhenConfigurationIsReady() {
        settings.enhancementsAISelection = EnhancementsAISelection(
            provider: .openai,
            selectedModel: "gpt-4o-mini",
        )

        let issue = settings.enhancementsInferenceReadinessIssue(apiKeyExists: { _ in true })

        XCTAssertNil(issue)
    }

    func testEnhancementsInferenceReadinessIssue_UsesRegistrationScopedKeyForSelectedEntry() throws {
        let registration = settings.addEnhancementsProviderRegistration(
            provider: .custom,
            displayName: "Proxy",
            baseURLOverride: "https://proxy.example/v1",
        )
        let registrationID = try XCTUnwrap(registration?.id)

        settings.updateEnhancementsSelection(
            registrationID: registrationID,
            model: "custom-model",
            for: .dictation,
        )

        let issue = settings.enhancementsInferenceReadinessIssue(
            for: .dictation,
            apiKeyExists: { _ in false },
            registrationAPIKeyExists: { $0 == registrationID },
        )

        XCTAssertNil(issue)
    }

    func testIsEnhancementsRegistrationSelected_ReturnsFalseForInactiveRegistration() throws {
        let registration = try XCTUnwrap(settings.addEnhancementsProviderRegistration(provider: .groq))
        settings.enhancementsAISelection = EnhancementsAISelection(provider: .openai, selectedModel: "")
        settings.enhancementsDictationAISelection = EnhancementsAISelection(provider: .google, selectedModel: "")

        XCTAssertFalse(settings.isEnhancementsRegistrationSelected(registration, for: .meeting))
        XCTAssertFalse(settings.isEnhancementsRegistrationSelected(registration, for: .dictation))
    }

    func testIsEnhancementsRegistrationSelected_ReturnsTrueForExplicitRegistrationSelection() throws {
        let registration = try XCTUnwrap(settings.addEnhancementsProviderRegistration(provider: .groq))
        settings.updateEnhancementsSelection(registrationID: registration.id, model: "   ", for: .meeting)

        XCTAssertTrue(settings.isEnhancementsRegistrationSelected(registration, for: .meeting))
        XCTAssertFalse(settings.isEnhancementsRegistrationSelected(registration, for: .dictation))
    }

    func testBackfillEnhancementsSelectionModels_FillsMeetingSelectionFromLegacyConfiguration() {
        settings.updateAIConfiguration(
            provider: .openai,
            baseURL: LLMProvider.openai.defaultBaseURL,
            selectedModel: "gpt-4o-mini",
        )
        settings.enhancementsAISelection = EnhancementsAISelection(provider: .openai, selectedModel: " ")
        settings.enhancementsProviderSelectedModels = [:]

        settings.backfillEnhancementsSelectionModelsIfNeeded()

        XCTAssertEqual(settings.enhancementsAISelection.selectedModel, "gpt-4o-mini")
        XCTAssertEqual(settings.enhancementsProviderSelectedModels[LLMProvider.openai.rawValue], "gpt-4o-mini")
    }

    func testBackfillEnhancementsSelectionModels_FillsDictationSelectionFromProviderStoredModel() {
        settings.enhancementsDictationAISelection = EnhancementsAISelection(provider: .anthropic, selectedModel: "")
        settings.enhancementsProviderSelectedModels = [LLMProvider.anthropic.rawValue: "claude-3-7-sonnet"]

        settings.backfillEnhancementsSelectionModelsIfNeeded()

        XCTAssertEqual(settings.enhancementsDictationAISelection.selectedModel, "claude-3-7-sonnet")
    }

    func testBackfillEnhancementsSelectionModels_AssistantUsesBackfilledDictationSelection() {
        settings.enhancementsDictationAISelection = EnhancementsAISelection(provider: .openai, selectedModel: "")
        settings.enhancementsProviderSelectedModels = [LLMProvider.openai.rawValue: "gpt-4.1-mini"]

        settings.backfillEnhancementsSelectionModelsIfNeeded()

        let assistantConfiguration = settings.resolvedEnhancementsAIConfiguration(for: .assistant)
        XCTAssertEqual(assistantConfiguration.provider, .openai)
        XCTAssertEqual(assistantConfiguration.selectedModel, "gpt-4.1-mini")
    }

    func testBackfillEnhancementsSelectionModels_DoesNotOverrideExistingSelection() {
        settings.enhancementsAISelection = EnhancementsAISelection(
            provider: .openai,
            selectedModel: "gpt-4.1-mini",
        )
        settings.enhancementsProviderSelectedModels = [LLMProvider.openai.rawValue: "gpt-4o-mini"]

        settings.backfillEnhancementsSelectionModelsIfNeeded()

        XCTAssertEqual(settings.enhancementsAISelection.selectedModel, "gpt-4.1-mini")
        XCTAssertEqual(settings.enhancementsProviderSelectedModels[LLMProvider.openai.rawValue], "gpt-4.1-mini")
    }

    func testBackfillEnhancementsSelectionModels_DoesNotFillWhenNoValidLegacySourceExists() {
        settings.updateAIConfiguration(
            provider: .openai,
            baseURL: LLMProvider.openai.defaultBaseURL,
            selectedModel: "   ",
        )
        settings.enhancementsAISelection = EnhancementsAISelection(provider: .google, selectedModel: " ")
        settings.enhancementsProviderSelectedModels = [:]

        settings.backfillEnhancementsSelectionModelsIfNeeded()

        XCTAssertEqual(settings.enhancementsAISelection.selectedModel, "")
        XCTAssertNil(settings.enhancementsProviderSelectedModels[LLMProvider.google.rawValue])
    }

    func testBackfillEnhancementsSelectionModels_NormalizesLegacyGoogleModelID() {
        settings.updateAIConfiguration(
            provider: .google,
            baseURL: LLMProvider.google.defaultBaseURL,
            selectedModel: "models/gemini-2.0-flash-001",
        )
        settings.enhancementsAISelection = EnhancementsAISelection(provider: .google, selectedModel: "")
        settings.enhancementsProviderSelectedModels = [:]

        settings.backfillEnhancementsSelectionModelsIfNeeded()

        XCTAssertEqual(settings.enhancementsAISelection.selectedModel, "gemini-2.0-flash")
        XCTAssertEqual(settings.enhancementsProviderSelectedModels[LLMProvider.google.rawValue], "gemini-2.0-flash")
    }

    func testUpdateEnhancementsProviderSelectedModel_NormalizesGoogleModelID() {
        settings.updateEnhancementsProviderSelectedModel("models/gemini-2.0-flash-001", for: .google)

        XCTAssertEqual(settings.enhancementsSelectedModel(for: .google), "gemini-2.0-flash")
        XCTAssertEqual(settings.enhancementsProviderSelectedModels[LLMProvider.google.rawValue], "gemini-2.0-flash")
    }

    func testCanAddEnhancementsProviderRegistration_EnforcesBuiltInUniqueness() {
        XCTAssertTrue(settings.canAddEnhancementsProviderRegistration(.openai))

        let registration = settings.addEnhancementsProviderRegistration(provider: .openai)

        XCTAssertNotNil(registration)
        XCTAssertFalse(settings.canAddEnhancementsProviderRegistration(.openai))
    }

    func testMigrateEnhancementsProviderRegistrationAPIKeysIfNeeded_BackfillsBuiltInGroqProviderKey() throws {
        let keychain = DefaultKeychainProvider()
        let registration = EnhancementsProviderRegistration(
            id: UUID(),
            provider: .groq,
            displayName: "Groq",
        )
        settings.enhancementsProviderRegistrations = [registration]

        try? KeychainManager.deleteAPIKey(for: registration.id)
        try? keychain.delete(for: KeychainManager.apiKeyKey(for: .groq))
        defer {
            try? KeychainManager.deleteAPIKey(for: registration.id)
            try? keychain.delete(for: KeychainManager.apiKeyKey(for: .groq))
        }

        try KeychainManager.storeAPIKey("sk-groq-registration", for: registration.id)

        settings.migrateEnhancementsProviderRegistrationAPIKeysIfNeeded()

        XCTAssertEqual(try KeychainManager.retrieveAPIKey(for: .groq), "sk-groq-registration")
        XCTAssertNil(try KeychainManager.retrieveAPIKey(for: registration.id))
    }

    func testAddEnhancementsProviderRegistration_AllowsMultipleCustomEntries() {
        let firstCustom = settings.addEnhancementsProviderRegistration(
            provider: .custom,
            displayName: "Gateway A",
            baseURLOverride: "https://gateway-a.example/v1",
        )
        let secondCustom = settings.addEnhancementsProviderRegistration(
            provider: .custom,
            displayName: "Gateway B",
            baseURLOverride: "https://gateway-b.example/v1",
        )

        XCTAssertNotNil(firstCustom)
        XCTAssertNotNil(secondCustom)
        XCTAssertEqual(settings.enhancementsRegistrations(for: .custom).count, 2)
        XCTAssertNotEqual(firstCustom?.id, secondCustom?.id)
    }

    func testAddEnhancementsProviderRegistration_PersistsCustomIconForCustomProvider() {
        let registration = settings.addEnhancementsProviderRegistration(
            provider: .custom,
            displayName: "Gateway A",
            baseURLOverride: "https://gateway-a.example/v1",
            iconSystemName: "terminal",
        )

        XCTAssertEqual(registration?.iconSystemName, "terminal")
        XCTAssertEqual(settings.enhancementsRegistrations(for: .custom).first?.iconSystemName, "terminal")
    }

    func testUpdateEnhancementsProviderRegistration_ClearsCustomIconForBuiltInProvider() {
        let registration = settings.addEnhancementsProviderRegistration(provider: .openai)
        var updated = registration
        updated?.iconSystemName = "terminal"

        if let updated {
            settings.updateEnhancementsProviderRegistration(updated)
        }

        XCTAssertNil(settings.enhancementsRegistrations(for: .openai).first?.iconSystemName)
    }

    func testRemoveEnhancementsProviderRegistration_ClearsSelectedEntryModel() throws {
        let custom = settings.addEnhancementsProviderRegistration(
            provider: .custom,
            displayName: "Custom Proxy",
            baseURLOverride: "https://proxy.example/v1",
        )
        let customID = try XCTUnwrap(custom?.id)

        settings.updateEnhancementsSelection(
            registrationID: customID,
            model: "custom-model",
            for: .meeting,
        )

        XCTAssertEqual(settings.enhancementsAISelection.registrationID, customID)
        XCTAssertEqual(settings.enhancementsAISelection.selectedModel, "custom-model")

        settings.removeEnhancementsProviderRegistration(id: customID)

        XCTAssertNil(settings.enhancementsAISelection.registrationID)
        XCTAssertEqual(settings.enhancementsAISelection.selectedModel, "")
        XCTAssertTrue(settings.enhancementsRegistrations(for: .custom).isEmpty)
    }
}
