import Foundation
@testable import VerbiCore
import XCTest

@MainActor
final class MeetingQuestionDictationServiceTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await RecordingExclusivityCoordinator.shared.endAssistant()
        await RecordingExclusivityCoordinator.shared.endRecording()
    }

    override func tearDown() async throws {
        await RecordingExclusivityCoordinator.shared.endAssistant()
        await RecordingExclusivityCoordinator.shared.endRecording()
        try await super.tearDown()
    }

    func testToggleDictationStartsAndStopsWithTranscribedText() async {
        let recorder = MockMeetingQuestionRecorder()
        let transcriber = MockMeetingQuestionTranscriber()
        transcriber.nextResponse = TranscriptionResponse(
            text: "What are the action items?",
            segments: [],
            language: "en",
            durationSeconds: 2,
            model: "mock-model",
            processedAt: Date().ISO8601Format(),
            confidenceScore: 0.9,
        )

        let service = MeetingQuestionDictationService(recorder: recorder, transcriber: transcriber)

        let startResult = await service.toggleDictation()
        XCTAssertNil(startResult)
        XCTAssertEqual(service.state, .recording)
        XCTAssertTrue(recorder.didStart)

        let finalText = await service.toggleDictation()
        XCTAssertEqual(finalText, "What are the action items?")
        XCTAssertEqual(service.state, .idle)
        XCTAssertTrue(recorder.didStop)
        XCTAssertNil(service.errorMessage)
    }

    func testToggleDictationShowsBusyErrorWhenAnotherRecordingIsActive() async {
        let recorder = MockMeetingQuestionRecorder()
        let transcriber = MockMeetingQuestionTranscriber()
        let service = MeetingQuestionDictationService(recorder: recorder, transcriber: transcriber)

        _ = await RecordingExclusivityCoordinator.shared.beginRecording()

        _ = await service.toggleDictation()

        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.errorMessage, "transcription.qa.dictation.error.busy".localized)
        XCTAssertFalse(recorder.didStart)
    }

    func testToggleDictationShowsTranscriptionError() async {
        let recorder = MockMeetingQuestionRecorder()
        let transcriber = MockMeetingQuestionTranscriber()
        transcriber.nextError = NSError(domain: "test", code: 1)

        let service = MeetingQuestionDictationService(recorder: recorder, transcriber: transcriber)

        _ = await service.toggleDictation()
        let finalText = await service.toggleDictation()

        XCTAssertNil(finalText)
        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.errorMessage, "transcription.qa.dictation.error.transcription".localized)
    }

    func testToggleDictationShowsPermissionError() async {
        let recorder = MockMeetingQuestionRecorder()
        recorder.permissionGranted = false
        let transcriber = MockMeetingQuestionTranscriber()

        let service = MeetingQuestionDictationService(recorder: recorder, transcriber: transcriber)

        _ = await service.toggleDictation()

        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.errorMessage, "transcription.qa.dictation.error.microphone_permission".localized)
    }
}

@MainActor
private final class MockMeetingQuestionRecorder: MeetingQuestionDictationRecording {
    var permissionGranted = true
    var didStart = false
    var didStop = false
    var nextStartError: Error?

    private var recordingURL: URL?

    func startQuestionDictationRecording(to outputURL: URL) async throws {
        if let nextStartError {
            throw nextStartError
        }
        didStart = true
        recordingURL = outputURL
    }

    func stopQuestionDictationRecording() async -> URL? {
        didStop = true
        return recordingURL
    }

    func hasPermission() async -> Bool {
        permissionGranted
    }

    func requestPermission() async {}
}

@MainActor
private final class MockMeetingQuestionTranscriber: MeetingQuestionDictationTranscribing {
    var nextResponse = TranscriptionResponse(
        text: "",
        segments: [],
        language: "en",
        durationSeconds: 0,
        model: "",
        processedAt: Date().ISO8601Format(),
        confidenceScore: nil,
    )
    var nextError: Error?

    func transcribeQuestionDictation(audioURL _: URL) async throws -> TranscriptionResponse {
        if let nextError {
            throw nextError
        }
        return nextResponse
    }
}
