import Combine
import Foundation
@testable import VerbiCore
@testable import VerbiCoreAudio
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

        _ = await RecordingExclusivityCoordinator.shared.beginRecording(mode: .meeting)

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

    func testUnexpectedRecorderStopSurfacesStopError() async {
        let recorder = MockMeetingQuestionRecorder()
        let transcriber = MockMeetingQuestionTranscriber()
        let service = MeetingQuestionDictationService(recorder: recorder, transcriber: transcriber)

        _ = await service.toggleDictation()
        XCTAssertEqual(service.state, .recording)

        recorder.recorderDidStop.send(false)
        await waitUntil(timeout: .seconds(5), message: "Question dictation should surface the recorder failure.") {
            service.state == .idle
        }

        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.errorMessage, "transcription.qa.dictation.error.stop_failed".localized)
        XCTAssertTrue(recorder.didStop)
    }

    func testValidationExhaustionSurfacesStopError() async throws {
        let fake = try FakeMicrophoneCaptureSession()
        let recorder = DictationRecorder(microphoneCaptureFactory: { onBuffer, onFailure in
            fake.setCallbacks(onBuffer: onBuffer, onFailure: onFailure)
            return fake
        })
        recorder.microphonePermissionValidator = {}
        recorder.validationInterval = 3600
        defer { _ = await recorder.stopRecording() }

        let service = MeetingQuestionDictationService(
            recorder: FakeSessionQuestionRecorder(recorder: recorder),
            transcriber: MockMeetingQuestionTranscriber()
        )

        _ = await service.toggleDictation()
        XCTAssertEqual(service.state, .recording)

        let url = try XCTUnwrap(recorder.currentRecordingURL)
        let firstSessionID = try XCTUnwrap(recorder.activeValidationSessionID)
        await recorder.handleValidationTimeout(url: url, source: .microphone, retryCount: 0, sessionID: firstSessionID)
        let secondSessionID = try XCTUnwrap(recorder.activeValidationSessionID)
        await recorder.handleValidationTimeout(url: url, source: .microphone, retryCount: 1, sessionID: secondSessionID)

        await waitUntil(timeout: .seconds(5), message: "Question dictation should surface the recorder failure.") {
            service.state == .idle
        }

        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.errorMessage, "transcription.qa.dictation.error.stop_failed".localized)
        XCTAssertFalse(recorder.isRecording)
        let canBeginAgain = await RecordingExclusivityCoordinator.shared.beginAssistant()
        XCTAssertTrue(canBeginAgain)
        await RecordingExclusivityCoordinator.shared.endAssistant()
    }
}

@MainActor
private final class FakeSessionQuestionRecorder: MeetingQuestionDictationRecording {
    private let recorder: DictationRecorder

    init(recorder: DictationRecorder) {
        self.recorder = recorder
    }

    var isRecordingPublisher: AnyPublisher<Bool, Never> {
        recorder.isRecordingPublisher
    }

    func startQuestionDictationRecording(to outputURL: URL) async throws {
        try await recorder.startQuestionDictationRecording(to: outputURL)
    }

    func stopQuestionDictationRecording() async -> URL? {
        await recorder.stopQuestionDictationRecording()
    }

    func hasPermission() async -> Bool {
        await MainActor.run { recorder.hasPermission() }
    }

    func requestPermission() async {
        await recorder.requestPermission()
    }
}

@MainActor
private final class MockMeetingQuestionRecorder: MeetingQuestionDictationRecording {
    var permissionGranted = true
    var didStart = false
    var didStop = false
    var nextStartError: Error?
    let recorderDidStop = PassthroughSubject<Bool, Never>()

    var isRecordingPublisher: AnyPublisher<Bool, Never> {
        recorderDidStop.eraseToAnyPublisher()
    }

    private var recordingURL: URL?

    func startQuestionDictationRecording(to outputURL: URL) async throws {
        await Task.yield()
        if let nextStartError {
            throw nextStartError
        }
        didStart = true
        recordingURL = outputURL
    }

    func stopQuestionDictationRecording() async -> URL? {
        await Task.yield()
        didStop = true
        return recordingURL
    }

    func hasPermission() async -> Bool {
        await Task.yield()
        return permissionGranted
    }

    func requestPermission() async {
        await Task.yield()
    }
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
