import Foundation
@testable import VerbiCore
@testable import VerbiCoreCommon
@testable import VerbiCoreDomain
@testable import VerbiCoreInfrastructure
@testable import VerbiCoreUI
import XCTest

/// End-to-end retry attempt coverage that needs to mutate shared state while
/// the attempt is running. It owns a manager wired to a gated transcription
/// client, so the shared test mocks stay free of test-only control surfaces.
@MainActor
final class RetryVocabularyAttemptTests: XCTestCase {
    private var manager: RecordingManager!
    private var transcription: GatedTranscriptionClient!
    private var storage: MockStorageService!
    private var userDefaults: UserDefaults!
    private var suiteName: String!
    private var markdownRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        try AppSettingsTestIsolationLock.acquire()
        AppSettingsStore.shared.resetToDefaults()
        AppSettingsStore.shared.postProcessingEnabled = false

        let transcription = GatedTranscriptionClient()
        let storage = MockStorageService()
        let calendarService = MockCalendarEventService()
        let suiteName = "RetryVocabularyAttemptTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let markdownRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("retry-vocabulary-attempts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: markdownRoot, withIntermediateDirectories: true)

        self.transcription = transcription
        self.storage = storage
        self.userDefaults = userDefaults
        self.suiteName = suiteName
        self.markdownRoot = markdownRoot

        manager = RecordingManager(
            micRecorder: MockAudioRecorder(),
            systemRecorder: MockAudioRecorder(),
            transcriptionClient: transcription,
            postProcessingService: MockPostProcessingService(),
            calendarEventService: calendarService,
            audioSilenceCompactor: MockAudioSilenceCompactor(),
            storage: storage,
            activeAppContextProvider: MockActiveAppContextProvider(),
            captureContextResolver: MockCaptureContextResolver(),
            meetingNotesRichTextStore: MeetingNotesRichTextStore(userDefaults: userDefaults),
            meetingNotesMarkdownStore: MeetingNotesMarkdownDocumentStore(
                userDefaults: userDefaults,
                rootDirectoryURL: markdownRoot,
                writesAsynchronously: false
            ),
            calendarIntegrationService: MeetingCalendarIntegrationService(
                calendarEventService: calendarService,
                ignoredEventIdentifiers: { [] }
            ),
            apiKeyExists: { _ in true },
            transcriptionAPIKeyExists: { _ in true },
            isLocalRetryModelReady: { _ in true }
        )
    }

    override func tearDown() async throws {
        await manager?.reset()
        await RecordingExclusivityCoordinator.shared.endRecording()
        await RecordingExclusivityCoordinator.shared.endAssistant()
        manager = nil
        transcription = nil
        storage = nil
        if let suiteName {
            userDefaults?.removePersistentDomain(forName: suiteName)
        }
        if let markdownRoot {
            try? FileManager.default.removeItem(at: markdownRoot)
        }
        userDefaults = nil
        suiteName = nil
        markdownRoot = nil
        AppSettingsStore.shared.resetToDefaults()
        AppSettingsTestIsolationLock.release()
        try await super.tearDown()
    }

    func testRetryWithCurrentDictionaryFreezesVocabularyAtAttemptStart() async throws {
        let settings = AppSettingsStore.shared
        settings.vocabularyTerms = [VocabularyTerm(term: "BeforeStart", definition: "Before start")]
        settings.vocabularyReplacementRules = [VocabularyReplacementRule(find: "alpha", replace: "before")]

        let audioURL = try makeAudioFile()
        let artifact = makeArtifact(audioURL: audioURL, vocabularySnapshot: .empty)
        transcription.mockText = "alpha"
        transcription.gate = {
            await MainActor.run {
                AppSettingsStore.shared.vocabularyTerms = [VocabularyTerm(term: "DuringRun", definition: "During run")]
                AppSettingsStore.shared.vocabularyReplacementRules = [
                    VocabularyReplacementRule(find: "alpha", replace: "during")
                ]
            }
        }

        await manager.retryTranscription(for: artifact, vocabularyIntent: .currentDictionary)

        let saved = try XCTUnwrap(storage.savedTranscriptions.last)
        XCTAssertEqual(saved.text, "before")
        XCTAssertEqual(saved.executionProvenance?.vocabularySource, .currentDictionary)
        XCTAssertEqual(saved.executionProvenance?.vocabularySnapshot.terms.map(\.term), ["BeforeStart"])
    }

    func testRetryCancellationPreservesArtifactAndRecordsFailedAttempt() async throws {
        let audioURL = try makeAudioFile()
        let artifact = makeArtifact(audioURL: audioURL, vocabularySnapshot: .empty, text: "Original text")

        let started = expectation(description: "transcription started")
        let (suspension, suspensionContinuation) = AsyncStream<Void>.makeStream()
        defer { suspensionContinuation.finish() }
        transcription.gate = {
            started.fulfill()
            for await _ in suspension {}
            if Task.isCancelled {
                throw CancellationError()
            }
        }

        let task = Task {
            await manager.retryTranscription(for: artifact, vocabularyIntent: .currentDictionary)
        }
        await fulfillment(of: [started], timeout: 5)
        task.cancel()
        await task.value

        XCTAssertTrue(storage.savedTranscriptions.isEmpty)
        XCTAssertEqual(artifact.text, "Original text")
        XCTAssertFalse(manager.isTranscribing)
        let failedAttempt = try XCTUnwrap(
            storage.savedModelPerformanceAttempts.last { $0.attemptKind == .retry }
        )
        XCTAssertEqual(failedAttempt.status, .failed)
        XCTAssertEqual(failedAttempt.executionProvenance?.vocabularySource, .currentDictionary)
    }

    // MARK: - Helpers

    private func makeArtifact(
        audioURL: URL,
        vocabularySnapshot: VocabularySnapshot?,
        text: String = "Existing"
    ) -> CaptureArtifact {
        let modelID = LocalTranscriptionModel.parakeetTdt06BV3.rawValue
        let provenance = vocabularySnapshot.map { snapshot in
            ExecutionProvenance(
                transcriptionRequest: DomainTranscriptionRequestConfiguration(
                    providerID: TranscriptionProvider.local.rawValue,
                    modelID: modelID,
                    inputLanguageCode: "en"
                ),
                vocabularySnapshot: snapshot,
                transcriptionModelIdentity: TranscriptionProvider.local.modelPerformanceIdentity(modelID: modelID)
            )
        }
        return CaptureArtifact(
            meeting: CaptureSession(app: .zoom, capturePurpose: .meeting, audioFilePath: audioURL.path),
            text: text,
            rawText: text,
            language: "en",
            modelName: modelID,
            executionProvenance: provenance
        )
    }

    private func makeAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try Data(repeating: 0, count: 256).write(to: url)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

/// Test-local client whose asynchronous work can be paused or mutated by the
/// owning test. It inherits the standard recording behavior from the shared
/// mock.
private final class GatedTranscriptionClient: MockTranscriptionClient {
    var gate: (@Sendable () async throws -> Void)?

    override func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> TranscriptionResponse {
        try await gate?()
        return try await super.transcribe(audioURL: audioURL, onProgress: onProgress)
    }
}
