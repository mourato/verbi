import AVFoundation
import Foundation
@testable import VerbiCore
@testable import VerbiCoreDomain
@testable import VerbiCoreInfrastructure
@testable import VerbiCoreUI
import XCTest

@MainActor
final class RemoteIncrementalStopTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try AppSettingsTestIsolationLock.acquire()
        AppSettingsStore.shared.resetToDefaults()
    }

    override func tearDown() async throws {
        AppSettingsStore.shared.resetToDefaults()
        AppSettingsTestIsolationLock.release()
        try await super.tearDown()
    }

    func testTranscribeIncrementalSession_ShortSilentRemoteDictationSkipsTranscriptionAndDeletesCheckpoint() async throws {
        let storage = MockStorageService()
        let transcriptionClient = MockTranscriptionClient()
        let postProcessing = MockPostProcessingService()
        let manager = makeManager(
            transcriptionClient: transcriptionClient,
            postProcessing: postProcessing,
            storage: storage
        )
        let audioURL = try writeWAV(duration: 1.0, amplitude: 0)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let meeting = makeDictationSession(audioURL: audioURL)
        let session = manager.makeTranscriptionSessionSnapshot(meeting)
        let coordinator = makeCoordinator(
            meeting: meeting,
            storage: storage,
            transcriptionClient: transcriptionClient,
            isRemote: true
        )

        try await coordinator.start()
        XCTAssertEqual(storage.mockTranscriptions.count, 1)

        await manager.transcribeIncrementalSession(
            audioURL: audioURL,
            session: session,
            coordinator: coordinator,
            coordinatorKind: .dictation
        )

        XCTAssertEqual(transcriptionClient.transcribeCallCount, 0)
        XCTAssertEqual(transcriptionClient.fileTranscribeCallCount, 0)
        XCTAssertEqual(postProcessing.processTranscriptionCallCount, 0)
        XCTAssertTrue(storage.mockTranscriptions.isEmpty, "Silent short dictation must delete partial checkpoint")
        XCTAssertEqual(manager.meetingState, .idle)
    }

    func testTranscribeIncrementalSession_ShortSpokenRemoteDictationUsesSingleFullFileRequest() async throws {
        let storage = MockStorageService()
        let transcriptionClient = MockTranscriptionClient()
        transcriptionClient.mockText = "ditado curto"
        let postProcessing = MockPostProcessingService()
        let manager = makeManager(
            transcriptionClient: transcriptionClient,
            postProcessing: postProcessing,
            storage: storage
        )
        let audioURL = try writeWAV(duration: 1.5, amplitude: 0.25)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let meeting = makeDictationSession(audioURL: audioURL)
        let session = manager.makeTranscriptionSessionSnapshot(meeting)
        let coordinator = makeCoordinator(
            meeting: meeting,
            storage: storage,
            transcriptionClient: transcriptionClient,
            isRemote: true
        )

        try await coordinator.start()
        await manager.transcribeIncrementalSession(
            audioURL: audioURL,
            session: session,
            coordinator: coordinator,
            coordinatorKind: .dictation
        )

        XCTAssertEqual(transcriptionClient.sampleTranscribeCallCount, 0)
        XCTAssertEqual(transcriptionClient.fileTranscribeCallCount, 1)
        XCTAssertEqual(storage.mockTranscriptions.count, 1)
    }

    func testIsShortSilentDictation_FalseForLocalCoordinatorEvenWhenSilent() async throws {
        let storage = MockStorageService()
        let transcriptionClient = MockTranscriptionClient()
        let manager = makeManager(
            transcriptionClient: transcriptionClient,
            postProcessing: MockPostProcessingService(),
            storage: storage
        )
        let audioURL = try writeWAV(duration: 1.0, amplitude: 0)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let meeting = makeDictationSession(audioURL: audioURL)
        let session = manager.makeTranscriptionSessionSnapshot(meeting)
        let coordinator = makeCoordinator(
            meeting: meeting,
            storage: storage,
            transcriptionClient: transcriptionClient,
            isRemote: false
        )

        let shouldSkip = await manager.isShortSilentDictation(
            audioURL: audioURL,
            session: session,
            coordinator: coordinator
        )
        XCTAssertFalse(shouldSkip, "Short-silence skip must stay scoped to remote dictation")
    }

    private func makeManager(
        transcriptionClient: MockTranscriptionClient,
        postProcessing: MockPostProcessingService,
        storage: MockStorageService
    ) -> RecordingManager {
        let manager = RecordingManager(
            micRecorder: MockAudioRecorder(),
            systemRecorder: MockSystemAudioCapture(),
            transcriptionClient: transcriptionClient,
            postProcessingService: postProcessing,
            storage: storage
        )
        manager.recordingSource = .microphone
        manager.activeTranscriptionConfiguration = DomainTranscriptionRequestConfiguration(
            providerID: TranscriptionProvider.groq.rawValue,
            modelID: TranscriptionProvider.groq.defaultModelID,
            inputLanguageCode: "pt",
            vocabularyHints: nil
        )
        return manager
    }

    private func makeDictationSession(audioURL: URL) -> CaptureSession {
        var session = CaptureSession(
            app: .unknown,
            capturePurpose: .dictation,
            title: "Short Dictation Stop Test",
            audioFilePath: audioURL.path
        )
        session.endTime = Date()
        return session
    }

    private func makeCoordinator(
        meeting: CaptureSession,
        storage: MockStorageService,
        transcriptionClient: MockTranscriptionClient,
        isRemote: Bool
    ) -> IncrementalTranscriptionCoordinator {
        IncrementalTranscriptionCoordinator(
            transcriptionID: meeting.id,
            meeting: meeting,
            inputSource: "microphone",
            storage: storage,
            transcriptionClientBox: RecordingManager.UncheckedTranscriptionServiceBox(transcriptionClient),
            callbacks: .init(
                onPreviewTextChanged: nil,
                onProcessedDurationChanged: { _ in }
            ),
            fallbackLogMessage: "Dictation incremental transcription degraded; full-file fallback required",
            isRemote: isRemote,
            suppressLivePreview: isRemote
        )
    }

    private func writeWAV(duration: Double, amplitude: Float, sampleRate: Double = 16000) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("verbi-stop-test-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let channelData = try XCTUnwrap(buffer.floatChannelData)
        for index in 0 ..< Int(frameCount) {
            let angle = 2 * Double.pi * Double(index) * 220 / sampleRate
            channelData[0][index] = sin(Float(angle)) * amplitude
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}
