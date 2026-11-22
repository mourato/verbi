import Foundation
@testable import VerbiCoreAI
import VerbiCoreDomain
@testable import VerbiCoreInfrastructure
import XCTest

@MainActor
final class TranscriptionClientWarmupTests: XCTestCase {
    private var fakeModelManager: FakeTranscriptionModelManager!

    override func setUp() async throws {
        try await super.setUp()
        try AppSettingsTestIsolationLock.acquire()
        fakeModelManager = FakeTranscriptionModelManager()
    }

    override func tearDown() async throws {
        AppSettingsTestIsolationLock.release()
        try await super.tearDown()
    }

    func testMeetingWarmupSkippedWhenMeetingCapabilityDisabled() async throws {
        let settings = AppSettingsStore.shared
        let originalMeetingEnabled = settings.isMeetingTranscriptionEnabled
        defer { settings.isMeetingTranscriptionEnabled = originalMeetingEnabled }
        settings.isMeetingTranscriptionEnabled = false

        let client = makeTestClient()

        try await client.warmupModel(for: .meeting, configuration: nil)

        XCTAssertTrue(fakeModelManager.loadedASRModelIDs.isEmpty)
        XCTAssertEqual(fakeModelManager.diarizationWarmupCount, 0)
    }

    func testDictationWarmupAllowedWhenMeetingCapabilityDisabled() async throws {
        let settings = AppSettingsStore.shared
        let originalMeetingEnabled = settings.isMeetingTranscriptionEnabled
        defer { settings.isMeetingTranscriptionEnabled = originalMeetingEnabled }
        settings.isMeetingTranscriptionEnabled = false

        let dictationModelID = LocalTranscriptionModel.parakeetTdt06BV3.rawValue
        let configuration = DomainTranscriptionRequestConfiguration(
            providerID: VerbiCoreInfrastructure.TranscriptionProvider.local.rawValue,
            modelID: dictationModelID,
            inputLanguageCode: nil
        )

        let client = makeTestClient()
        try await client.warmupModel(for: .dictation, configuration: configuration)

        XCTAssertEqual(fakeModelManager.loadedASRModelIDs, [dictationModelID])
        XCTAssertEqual(fakeModelManager.diarizationWarmupCount, 0)
    }

    func testDictationWarmupUsesPassedModelIDNotMeetingSelection() async throws {
        let settings = AppSettingsStore.shared
        let originalMeetingModel = settings.meetingTranscriptionLocalModel
        defer { settings.meetingTranscriptionLocalModel = originalMeetingModel }

        settings.meetingTranscriptionLocalModel = .parakeetTdt06BV3

        let dictationModelID = LocalTranscriptionModel.parakeetTdt06BV3.rawValue
        let configuration = DomainTranscriptionRequestConfiguration(
            providerID: VerbiCoreInfrastructure.TranscriptionProvider.local.rawValue,
            modelID: dictationModelID,
            inputLanguageCode: nil
        )

        let client = makeTestClient()
        try await client.warmupModel(for: .dictation, configuration: configuration)

        XCTAssertEqual(fakeModelManager.loadedASRModelIDs, [dictationModelID])
        XCTAssertEqual(fakeModelManager.loadedASRModelIDs.first, settings.resolvedTranscriptionSelection(for: .meeting).selectedModel)
    }

    func testDictationWarmupDoesNotLoadDiarizationEvenWhenMeetingDiarizationEnabled() async throws {
        let settings = AppSettingsStore.shared
        let originalDiarizationEnabled = settings.isDiarizationEnabled
        defer { settings.isDiarizationEnabled = originalDiarizationEnabled }
        settings.isDiarizationEnabled = true

        let configuration = DomainTranscriptionRequestConfiguration(
            providerID: VerbiCoreInfrastructure.TranscriptionProvider.local.rawValue,
            modelID: LocalTranscriptionModel.parakeetTdt06BV3.rawValue,
            inputLanguageCode: nil
        )

        let client = makeTestClient()
        try await client.warmupModel(for: .dictation, configuration: configuration)

        XCTAssertEqual(fakeModelManager.loadedASRModelIDs.count, 1)
        XCTAssertEqual(fakeModelManager.diarizationWarmupCount, 0)
    }

    func testRemoteDictationWarmupDoesNotLoadLocalModelsWhenMeetingsUseParakeet() async throws {
        let settings = AppSettingsStore.shared
        let originalMeetingEnabled = settings.isMeetingTranscriptionEnabled
        let originalMeetingModel = settings.meetingTranscriptionLocalModel
        let originalDiarizationEnabled = settings.isDiarizationEnabled
        defer {
            settings.isMeetingTranscriptionEnabled = originalMeetingEnabled
            settings.meetingTranscriptionLocalModel = originalMeetingModel
            settings.isDiarizationEnabled = originalDiarizationEnabled
        }
        settings.isMeetingTranscriptionEnabled = true
        settings.meetingTranscriptionLocalModel = .parakeetTdt06BV3
        settings.isDiarizationEnabled = true

        let client = makeTestClient()
        let providers: [VerbiCoreInfrastructure.TranscriptionProvider] = [.groq, .elevenLabs]
        for provider in providers {
            let configuration = DomainTranscriptionRequestConfiguration(
                providerID: provider.rawValue,
                modelID: provider.defaultModelID,
                inputLanguageCode: nil
            )

            try await client.warmupModel(for: .dictation, configuration: configuration)

            XCTAssertTrue(fakeModelManager.loadedASRModelIDs.isEmpty, provider.rawValue)
            XCTAssertEqual(fakeModelManager.diarizationWarmupCount, 0, provider.rawValue)
        }
    }

    func testMeetingWarmupLoadsDiarizationWhenEnabled() async throws {
        let settings = AppSettingsStore.shared
        let originalMeetingEnabled = settings.isMeetingTranscriptionEnabled
        let originalDiarizationEnabled = settings.isDiarizationEnabled
        defer {
            settings.isMeetingTranscriptionEnabled = originalMeetingEnabled
            settings.isDiarizationEnabled = originalDiarizationEnabled
        }
        settings.isMeetingTranscriptionEnabled = true
        settings.isDiarizationEnabled = true

        let client = makeTestClient()
        try await client.warmupModel(for: .meeting, configuration: nil)

        XCTAssertEqual(fakeModelManager.loadedASRModelIDs.count, 1)
        XCTAssertEqual(fakeModelManager.diarizationWarmupCount, 1)
    }

    private func makeTestClient() -> TranscriptionClient {
        TranscriptionClient(settingsStore: AppSettingsStore.shared, modelManager: fakeModelManager)
    }
}

@MainActor
private final class FakeTranscriptionModelManager: TranscriptionModelManaging {
    var modelState: VerbiCoreDomain.ModelState = .unloaded
    var loadedASRLocalModelID: String?
    var loadedASRModelIDs: [String] = []
    var diarizationWarmupCount = 0

    func loadModels(for localModelID: String) async {
        await Task.yield()
        loadedASRModelIDs.append(localModelID)
    }

    func loadDiarizationModels() async {
        await Task.yield()
        diarizationWarmupCount += 1
    }
}
