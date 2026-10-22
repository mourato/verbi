@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreInfrastructure
@testable import MeetingAssistantCoreUI
import XCTest

@MainActor
final class ServiceSettingsViewModelTests: XCTestCase {
    private var settings: AppSettingsStore!
    private var mockKeychain: TestTranscriptionKeychainProvider!

    override func setUp() async throws {
        try await super.setUp()
        settings = .shared
        settings.resetToDefaults()
        mockKeychain = TestTranscriptionKeychainProvider()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        mockKeychain = nil
        settings = nil
        try await super.tearDown()
    }

    func testCatalogModelsListsCuratedLocalAndCloudTranscriptionModels() {
        let viewModel = ServiceSettingsViewModel(
            settings: settings,
            keychain: mockKeychain
        )

        let ids = viewModel.catalogModels.map(\.id)
        XCTAssertEqual(
            ids,
            [
                "local:parakeet-tdt-0.6b-v3-coreml",
                "groq:whisper-large-v3-turbo",
                "groq:whisper-large-v3",
                "elevenLabs:scribe_v2",
                "openai:gpt-4o-transcribe",
                "openai:gpt-4o-mini-transcribe"
            ]
        )
    }

    func testCatalogOmitsLegacyScribeV1() {
        let viewModel = ServiceSettingsViewModel(
            settings: settings,
            keychain: mockKeychain
        )

        XCTAssertFalse(viewModel.catalogModels.contains { $0.id == "elevenLabs:scribe_v1" })
        XCTAssertTrue(viewModel.catalogModels.contains { $0.id == "elevenLabs:scribe_v2" })
    }

    func testCatalogMarksSharedGroqAndOpenAICredentials() throws {
        let viewModel = ServiceSettingsViewModel(
            settings: settings,
            keychain: mockKeychain
        )

        for provider in [TranscriptionProvider.groq, .openai] {
            let entries = viewModel.catalogModels.filter { $0.provider == provider }
            XCTAssertFalse(entries.isEmpty)
            XCTAssertTrue(entries.allSatisfy(\.usesSharedCredential))
        }

        let localEntry = try XCTUnwrap(viewModel.catalogModels.first { $0.provider == .local })
        XCTAssertFalse(localEntry.usesSharedCredential)

        let elevenLabsEntries = viewModel.catalogModels.filter { $0.provider == .elevenLabs }
        XCTAssertFalse(elevenLabsEntries.isEmpty)
        XCTAssertTrue(elevenLabsEntries.allSatisfy { !$0.usesSharedCredential })
    }

    func testCatalogModelsReflectRequiresKeyBadgeAndProviderReadiness() throws {
        let viewModel = ServiceSettingsViewModel(
            settings: settings,
            keychain: mockKeychain
        )

        let localEntry = try XCTUnwrap(viewModel.catalogModels.first { $0.provider == .local })
        XCTAssertTrue(localEntry.isLocal)
        XCTAssertFalse(localEntry.requiresAPIKey)
        XCTAssertFalse(localEntry.showsRequiresKeyBadge)

        let openAIEntriesBefore = viewModel.catalogModels.filter { $0.provider == .openai }
        XCTAssertEqual(openAIEntriesBefore.count, 2)
        XCTAssertTrue(openAIEntriesBefore.allSatisfy(\.requiresAPIKey))
        XCTAssertTrue(openAIEntriesBefore.allSatisfy(\.showsRequiresKeyBadge))

        viewModel.saveTranscriptionAPIKey("sk-openai-test", for: .openai)

        let openAIEntriesAfterSave = viewModel.catalogModels.filter { $0.provider == .openai }
        XCTAssertTrue(openAIEntriesAfterSave.allSatisfy(\.isProviderReady))
        XCTAssertTrue(openAIEntriesAfterSave.allSatisfy { !$0.showsRequiresKeyBadge })

        let groqEntries = viewModel.catalogModels.filter { $0.provider == .groq }
        XCTAssertTrue(groqEntries.allSatisfy(\.showsRequiresKeyBadge))

        viewModel.removeTranscriptionAPIKey(for: .openai)

        let openAIEntriesAfterRemove = viewModel.catalogModels.filter { $0.provider == .openai }
        XCTAssertTrue(openAIEntriesAfterRemove.allSatisfy(\.showsRequiresKeyBadge))
    }

    func testCatalogModelsTrackActiveDictationAndMeetingUsage() throws {
        settings.isMeetingTranscriptionEnabled = true
        settings.updateMeetingTranscriptionLocalModel(.parakeetTdt06BV3)
        settings.updateTranscriptionDictationProvider(.openai)
        settings.updateTranscriptionDictationModel("gpt-4o-mini-transcribe")

        let viewModel = ServiceSettingsViewModel(
            settings: settings,
            keychain: mockKeychain
        )

        let parakeet = try XCTUnwrap(
            viewModel.catalogModels.first { $0.id == "local:parakeet-tdt-0.6b-v3-coreml" }
        )
        XCTAssertTrue(parakeet.isUsedForMeetings)
        // Dictation provider/model changes leave the independently persisted
        // default style untouched, so Parakeet still reports dictation usage
        // via that style alongside the active OpenAI dictation selection.
        XCTAssertTrue(parakeet.isUsedForDictation)
        XCTAssertTrue(parakeet.isInUse)

        let openAIMini = try XCTUnwrap(
            viewModel.catalogModels.first { $0.id == "openai:gpt-4o-mini-transcribe" }
        )
        XCTAssertTrue(openAIMini.isUsedForDictation)
        XCTAssertFalse(openAIMini.isUsedForMeetings)
        XCTAssertTrue(openAIMini.isInUse)

        let openAIDefault = try XCTUnwrap(
            viewModel.catalogModels.first { $0.id == "openai:gpt-4o-transcribe" }
        )
        XCTAssertFalse(openAIDefault.isInUse)
    }

    func testSelectAndDismissCatalogModelUpdatesDrawerSelection() throws {
        let viewModel = ServiceSettingsViewModel(
            settings: settings,
            keychain: mockKeychain
        )

        XCTAssertNil(viewModel.selectedCatalogModel)

        let target = try XCTUnwrap(viewModel.catalogModels.first { $0.id == "groq:whisper-large-v3-turbo" })
        viewModel.selectCatalogModel(target)

        XCTAssertEqual(viewModel.selectedCatalogModelID, target.id)
        XCTAssertEqual(viewModel.selectedCatalogModel, target)

        viewModel.dismissSelectedCatalogModel()

        XCTAssertNil(viewModel.selectedCatalogModelID)
        XCTAssertNil(viewModel.selectedCatalogModel)
    }

    func testModelDisplayName_IsScopedToHostingProvider() {
        let scribeName = "settings.service.transcription_provider.model_option.elevenlabs.scribe_v2".localized
        XCTAssertEqual(TranscriptionProvider.elevenLabs.displayName(forModelID: "scribe_v2"), scribeName)
        XCTAssertEqual(TranscriptionProvider.openai.displayName(forModelID: "scribe_v2"), "scribe_v2")
        XCTAssertEqual(TranscriptionProvider.groq.displayName(forModelID: "gpt-4o-transcribe"), "gpt-4o-transcribe")
        XCTAssertEqual(TranscriptionProvider.local.displayName(forModelID: "unknown-local"), "unknown-local")
    }

    func testModelIdentity_PrefersFamilyBrandAndBadgesDistinctHost() {
        let groqWhisper = ModelBrand.identity(for: TranscriptionProvider.groq, modelID: "whisper-large-v3")
        XCTAssertEqual(groqWhisper.brand, .openai)
        XCTAssertEqual(groqWhisper.host, .groq)

        let openAIModel = ModelBrand.identity(for: TranscriptionProvider.openai, modelID: "gpt-4o-transcribe")
        XCTAssertEqual(openAIModel.brand, .openai)
        XCTAssertNil(openAIModel.host)

        let localUnknown = ModelBrand.identity(for: TranscriptionProvider.local, modelID: "mystery")
        XCTAssertNil(localUnknown.brand)
        XCTAssertNil(localUnknown.host)

        let groqLlama = ModelBrand.identity(for: LLMProvider.groq, modelID: "llama-3.3-70b")
        XCTAssertEqual(groqLlama.brand, .groq)
        XCTAssertNil(groqLlama.host)

        XCTAssertEqual(ModelBrand.identity(for: LLMProvider.custom, modelID: "claude-sonnet-4").brand, .anthropic)
        XCTAssertEqual(ModelBrand.identity(for: LLMProvider.openai, modelID: "gemini-2.5-pro").host, .openai)
    }

    func testDictationModelPickerSelectsProviderAndModelThroughExistingSetters() throws {
        let viewModel = ServiceSettingsViewModel(
            settings: settings,
            keychain: mockKeychain
        )

        let options = viewModel.dictationModelPickerOptions
        XCTAssertEqual(options.map(\.id), viewModel.catalogModels.map(\.id))
        XCTAssertEqual(options.filter(\.isSelected).map(\.id), ["local:parakeet-tdt-0.6b-v3-coreml"])
        XCTAssertEqual(options.first { $0.id == "openai:gpt-4o-transcribe" }?.status, .requiresKey)

        let mini = try XCTUnwrap(options.first { $0.id == "openai:gpt-4o-mini-transcribe" })
        viewModel.selectDictationModel(mini.value)

        XCTAssertEqual(
            settings.transcriptionDictationSelection,
            TranscriptionProviderSelection(provider: .openai, selectedModel: "gpt-4o-mini-transcribe")
        )
        XCTAssertEqual(viewModel.dictationModelPickerOptions.filter(\.isSelected).map(\.id), [mini.id])
    }
}
