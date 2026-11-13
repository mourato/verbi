import Foundation
@testable import VerbiCore
@testable import VerbiCoreDomain
@testable import VerbiCoreInfrastructure
@testable import VerbiCoreUI
import XCTest

/// Verifies the recovery snapshot (S7) is built from AppSettingsStore defaults
/// only and never leaks live session state into a recovered file.
@MainActor
final class RecordingManagerRecoverySnapshotTests: XCTestCase {
    private var manager: RecordingManager?
    private var userDefaults: UserDefaults?
    private var suiteName: String?

    override func setUp() async throws {
        try await super.setUp()
        try AppSettingsTestIsolationLock.acquire()
        AppSettingsStore.shared.resetToDefaults()

        let suiteName = "RecordingManagerRecoverySnapshotTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create test UserDefaults suite")
            return
        }
        self.userDefaults = userDefaults
        self.suiteName = suiteName

        manager = RecordingManager(
            micRecorder: MockAudioRecorder(),
            systemRecorder: MockAudioRecorder(),
            transcriptionClient: MockTranscriptionClient(),
            postProcessingService: MockPostProcessingService(),
            calendarEventService: MockCalendarEventService(),
            audioSilenceCompactor: MockAudioSilenceCompactor(),
            storage: MockStorageService(),
            activeAppContextProvider: MockActiveAppContextProvider(),
            captureContextResolver: MockCaptureContextResolver(),
            meetingNotesRichTextStore: MeetingNotesRichTextStore(userDefaults: userDefaults),
            meetingNotesMarkdownStore: MeetingNotesMarkdownDocumentStore(
                userDefaults: userDefaults,
                rootDirectoryURL: FileManager.default.temporaryDirectory,
                writesAsynchronously: false
            ),
            apiKeyExists: { _ in true },
            transcriptionAPIKeyExists: { _ in true },
            isLocalRetryModelReady: { _ in true }
        )
    }

    override func tearDown() async throws {
        if let manager {
            await manager.reset()
        }
        manager = nil
        if let suiteName {
            userDefaults?.removePersistentDomain(forName: suiteName)
        }
        userDefaults = nil
        suiteName = nil
        AppSettingsStore.shared.resetToDefaults()
        AppSettingsTestIsolationLock.release()
        try await super.tearDown()
    }

    func testRecoverySnapshot_UsesDefaultsNotLiveSession() {
        guard let manager else {
            XCTFail("Missing recording manager")
            return
        }

        let recoveredMeeting = CaptureSession(
            app: .unknown,
            capturePurpose: .dictation,
            title: InterruptedRecordingRecovery.recoveredTitle(),
            startTime: Date(),
            audioFilePath: "/recordings/crash.wav"
        )

        // Pollute every live session input the old snapshot builder reads.
        manager.postProcessingContext = "LIVE-CONTEXT"
        manager.postProcessingContextItems = [
            TranscriptionContextItem(source: .clipboard, text: "LIVE-ITEM")
        ]
        manager.currentMeetingNotesText = "LIVE-NOTES"
        manager.dictationSessionOutputLanguageOverride = .english
        manager.dictationStartBundleIdentifier = "com.live.app"
        manager.dictationStartURL = URL(string: "https://live.example")
        manager.activeTranscriptionConfiguration = DomainTranscriptionRequestConfiguration(
            providerID: "live-provider",
            modelID: "live-model",
            inputLanguageCode: nil
        )
        manager.activeVocabularySnapshot = VocabularySnapshot(
            terms: [VocabularyTerm(term: "live-term", definition: "live")],
            replacementRules: []
        )
        manager.meetingSkippingPostProcessingID = recoveredMeeting.id
        manager.recordingSource = .all
        manager.currentMeeting = CaptureSession(
            app: .manualMeeting,
            capturePurpose: .meeting,
            title: "LIVE-MEETING"
        )

        let snapshot = manager.makeRecoveryTranscriptionSessionSnapshot(recoveredMeeting)

        XCTAssertEqual(snapshot.meeting.id, recoveredMeeting.id)
        XCTAssertEqual(snapshot.kernelMode, .dictation)
        XCTAssertEqual(snapshot.recordingSource, .microphone)
        XCTAssertNil(snapshot.postProcessingContext)
        XCTAssertTrue(snapshot.postProcessingContextItems.isEmpty)
        XCTAssertEqual(snapshot.meetingNotesContent, .empty)
        XCTAssertNil(snapshot.dictationSessionOutputLanguageOverride)
        XCTAssertNil(snapshot.dictationStartBundleIdentifier)
        XCTAssertNil(snapshot.dictationStartURL)
        XCTAssertNil(
            snapshot.transcriptionConfiguration,
            "The live transcription configuration must not leak into recovery"
        )
        XCTAssertEqual(snapshot.vocabularySnapshot, VocabularySnapshot.current(from: .shared))
        XCTAssertFalse(snapshot.skipPostProcessing)
        XCTAssertNotNil(snapshot.useCaseConfig, "Recovery builds its own config from settings")
        XCTAssertNil(snapshot.dictationStyle)
    }
}
