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
                "openai:gpt-4o-mini-transcribe",
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
}
