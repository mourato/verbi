import Foundation
@testable import MeetingAssistantCoreAI
@testable import MeetingAssistantCoreInfrastructure
import XCTest

@MainActor
final class LocalModelCompilePrewarmerTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "LocalModelCompilePrewarmerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        try await super.tearDown()
    }

    func testSameFingerprintSkipsLoad() async {
        let models = FakePrewarmModels()
        let prewarmer = makePrewarmer(models: models, settings: FakePrewarmSettings(meetingEnabled: true))

        await prewarmer.runIfNeeded()
        await prewarmer.runIfNeeded()

        XCTAssertEqual(models.asrLoadCount, 1)
        XCTAssertEqual(models.diarizationLoadCount, 1)
    }

    func testChangedFingerprintLoadsUnloadsThenPersists() async {
        let models = FakePrewarmModels()
        let prewarmer = makePrewarmer(models: models, settings: FakePrewarmSettings(meetingEnabled: true))

        await prewarmer.runIfNeeded()

        XCTAssertEqual(models.events, ["loadASR", "loadDiarization", "unloadASR", "unloadDiarization"])
        XCTAssertNotNil(defaults.string(forKey: LocalModelCompilePrewarmer.fingerprintDefaultsKey))
    }

    func testAlreadyResidentModelsAreNotUnloaded() async {
        let models = FakePrewarmModels()
        models.asrResident = true
        models.diarizationResident = true
        let prewarmer = makePrewarmer(models: models, settings: FakePrewarmSettings(meetingEnabled: true))

        await prewarmer.runIfNeeded()

        XCTAssertEqual(models.events, ["loadASR", "loadDiarization"])
        XCTAssertNotNil(defaults.string(forKey: LocalModelCompilePrewarmer.fingerprintDefaultsKey))
    }

    func testLoadFailureDoesNotPersistFingerprint() async {
        let models = FakePrewarmModels()
        models.loadSucceeds = false
        let prewarmer = makePrewarmer(models: models, settings: FakePrewarmSettings(meetingEnabled: true))

        await prewarmer.runIfNeeded()
        XCTAssertNil(defaults.string(forKey: LocalModelCompilePrewarmer.fingerprintDefaultsKey))

        models.loadSucceeds = true
        await prewarmer.runIfNeeded()
        XCTAssertEqual(models.asrLoadCount, 2)
        XCTAssertNotNil(defaults.string(forKey: LocalModelCompilePrewarmer.fingerprintDefaultsKey))
    }

    func testSkipsWhenLowPowerModeEnabled() async {
        let models = FakePrewarmModels()
        let prewarmer = makePrewarmer(
            models: models,
            settings: FakePrewarmSettings(meetingEnabled: true),
            isLowPowerModeEnabled: true
        )

        await prewarmer.runIfNeeded()

        XCTAssertTrue(models.events.isEmpty)
    }

    func testSkipsWhenCaptureIsActive() async {
        let models = FakePrewarmModels()
        let prewarmer = makePrewarmer(
            models: models,
            settings: FakePrewarmSettings(meetingEnabled: true),
            isCaptureActive: true
        )

        await prewarmer.runIfNeeded()

        XCTAssertTrue(models.events.isEmpty)
    }

    func testSkipsWhenSelectedBackendIsNotLocal() async {
        let models = FakePrewarmModels()
        let settings = FakePrewarmSettings(meetingEnabled: false)
        settings.dictationSelection = TranscriptionProviderSelection(provider: .groq, selectedModel: "whisper")
        let prewarmer = makePrewarmer(models: models, settings: settings)

        await prewarmer.runIfNeeded()

        XCTAssertTrue(models.events.isEmpty)
    }

    func testSkipsWhenRequiredModelsAreNotInstalled() async {
        let models = FakePrewarmModels()
        models.asrInstalled = false
        let prewarmer = makePrewarmer(models: models, settings: FakePrewarmSettings(meetingEnabled: true))

        await prewarmer.runIfNeeded()

        XCTAssertTrue(models.events.isEmpty)
    }

    private func makePrewarmer(
        models: FakePrewarmModels,
        settings: FakePrewarmSettings,
        isCaptureActive: Bool = false,
        isLowPowerModeEnabled: Bool = false
    ) -> LocalModelCompilePrewarmer {
        LocalModelCompilePrewarmer(
            models: models,
            settings: settings,
            defaults: defaults,
            isCaptureActive: { isCaptureActive },
            isLowPowerModeEnabled: { isLowPowerModeEnabled },
            operatingSystemVersion: { "Version 15.0 (Build TEST)" }
        )
    }
}

private let testASRModelID = LocalTranscriptionModel.parakeetTdt06BV3.rawValue

@MainActor
private final class FakePrewarmModels: LocalModelPrewarmManaging {
    var modelState: FluidAIModelManager.ModelState = .unloaded
    var asrResident = false
    var diarizationResident = false
    var asrInstalled = true
    var diarizationInstalled = true
    var loadSucceeds = true
    private(set) var events: [String] = []

    var asrLoadCount: Int {
        events.count(where: { $0 == "loadASR" })
    }

    var diarizationLoadCount: Int {
        events.count(where: { $0 == "loadDiarization" })
    }

    var isASRResidentInMemory: Bool {
        asrResident
    }

    var isDiarizationResidentInMemory: Bool {
        diarizationResident
    }

    func isASRModelInstalled(localModelID _: String) -> Bool {
        asrInstalled
    }

    func hasDiarizationModelsOnDisk() -> Bool {
        diarizationInstalled
    }

    func loadModels(for _: String) async {
        events.append("loadASR")
        await Task.yield()
        guard loadSucceeds else {
            modelState = .error
            return
        }
        modelState = .loaded
        asrResident = true
    }

    func loadDiarizationModels() async {
        events.append("loadDiarization")
        await Task.yield()
        if loadSucceeds {
            diarizationResident = true
        }
    }

    @discardableResult
    func unloadASRFromMemoryIfPossible() -> Bool {
        events.append("unloadASR")
        asrResident = false
        modelState = .unloaded
        return true
    }

    @discardableResult
    func unloadDiarizationFromMemoryIfPossible() -> Bool {
        events.append("unloadDiarization")
        diarizationResident = false
        return true
    }
}

@MainActor
private final class FakePrewarmSettings: LocalModelPrewarmSettingsProviding {
    var isMeetingTranscriptionEnabled: Bool
    var isDiarizationEnabled = true
    var meetingSelection = TranscriptionProviderSelection(provider: .local, selectedModel: testASRModelID)
    var dictationSelection = TranscriptionProviderSelection(provider: .local, selectedModel: testASRModelID)

    init(meetingEnabled: Bool) {
        isMeetingTranscriptionEnabled = meetingEnabled
    }

    func resolvedTranscriptionSelection(for mode: TranscriptionExecutionMode) -> TranscriptionProviderSelection {
        mode == .meeting ? meetingSelection : dictationSelection
    }

    func localModelSupportsDiarization(modelID _: String) -> Bool {
        true
    }
}
