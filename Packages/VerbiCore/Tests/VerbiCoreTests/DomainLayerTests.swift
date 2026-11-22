@testable import VerbiCore
@testable import VerbiCoreDomain
import XCTest

final class DomainLayerTests: XCTestCase {
    var mockRecordingRepo: VerbiCoreDomain.MacroMockRecordingRepository?
    var mockAudioFileRepo: VerbiCoreDomain.MacroMockAudioFileRepository?
    var mockMeetingRepo: VerbiCoreDomain.MacroMockMeetingRepository?
    var mockTranscriptionRepo: VerbiCoreDomain.MacroMockSpeechRecognitionClient?
    var mockTranscriptionStorageRepo: VerbiCoreDomain.MacroMockTranscriptionStorageRepository?
    var mockPostProcessingRepo: VerbiCoreDomain.MacroMockPostProcessingRepository?

    override func setUp() {
        super.setUp()
        mockRecordingRepo = VerbiCoreDomain.MacroMockRecordingRepository()
        mockAudioFileRepo = VerbiCoreDomain.MacroMockAudioFileRepository()
        mockMeetingRepo = VerbiCoreDomain.MacroMockMeetingRepository()
        mockTranscriptionRepo = VerbiCoreDomain.MacroMockSpeechRecognitionClient()
        mockTranscriptionStorageRepo = VerbiCoreDomain.MacroMockTranscriptionStorageRepository()
        mockPostProcessingRepo = VerbiCoreDomain.MacroMockPostProcessingRepository()
    }

    override func tearDown() {
        mockRecordingRepo = nil
        mockAudioFileRepo = nil
        mockMeetingRepo = nil
        mockTranscriptionRepo = nil
        mockTranscriptionStorageRepo = nil
        mockPostProcessingRepo = nil
        super.tearDown()
    }

    func testStartRecordingSuccess() async throws {
        guard let mockRecordingRepo,
              let mockAudioFileRepo,
              let mockMeetingRepo
        else {
            return XCTFail("Mocks not initialized")
        }

        let useCase = StartRecordingUseCase(
            recordingRepository: mockRecordingRepo,
            audioFileRepository: mockAudioFileRepo,
            meetingRepository: mockMeetingRepo,
        )
        let meeting = CaptureSessionEntity(app: .googleMeet)
        let expectedURL = URL(fileURLWithPath: "/tmp/test.wav")

        mockRecordingRepo.hasPermissionHandler = { () async -> Bool in true }
        mockRecordingRepo.startRecordingHandler = { _, _ in }
        mockAudioFileRepo.generateAudioFileURLHandler = { expectedURL }
        mockMeetingRepo.updateMeetingHandler = { _ in }

        let resultURL = try await useCase.execute(for: meeting)

        XCTAssertEqual(resultURL, expectedURL)
        XCTAssertEqual(mockRecordingRepo.hasPermissionCallCount, 1)
        XCTAssertEqual(mockRecordingRepo.startRecordingCalls.count, 1)
        XCTAssertEqual(mockRecordingRepo.startRecordingCalls.first?.outputURL, expectedURL)
        XCTAssertEqual(mockRecordingRepo.startRecordingCalls.first?.retryCount, 3)
        XCTAssertEqual(mockMeetingRepo.updateMeetingCalls.count, 1)
    }

    func testStartRecordingPermissionDenied() async {
        guard let mockRecordingRepo,
              let mockAudioFileRepo,
              let mockMeetingRepo
        else {
            return XCTFail("Mocks not initialized")
        }

        let useCase = StartRecordingUseCase(
            recordingRepository: mockRecordingRepo,
            audioFileRepository: mockAudioFileRepo,
            meetingRepository: mockMeetingRepo,
        )
        let meeting = CaptureSessionEntity(app: .googleMeet)

        mockRecordingRepo.hasPermissionHandler = { () async -> Bool in false }

        do {
            _ = try await useCase.execute(for: meeting)
            XCTFail("Should throw permissionDenied")
        } catch RecordingError.permissionDenied {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTranscribeAudioSuccess() async throws {
        guard let mockTranscriptionRepo,
              let mockPostProcessingRepo
        else {
            return XCTFail("Mocks not initialized")
        }
        let mockTranscriptionStorageRepo = makeMacroMockTranscriptionStorageRepository()

        let useCase = TranscribeAudioUseCase(
            speechRecognitionClient: mockTranscriptionRepo,
            transcriptionStorageRepository: mockTranscriptionStorageRepo,
            postProcessingRepository: mockPostProcessingRepo,
        )
        let meeting = CaptureSessionEntity(app: .googleMeet)
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")
        let response = DomainTranscriptionResponse(
            text: "Hello world",
            language: "en",
            durationSeconds: 5.0,
            model: "test-model",
            processedAt: "now",
        )

        mockTranscriptionRepo.transcribeHandler = { _, _ in response }
        mockTranscriptionStorageRepo.saveTranscriptionHandler = { _ in }

        let transcription = try await useCase.execute(audioURL: audioURL, meeting: meeting)

        XCTAssertEqual(transcription.text, "Hello world")
        XCTAssertEqual(transcription.meeting.id, meeting.id)
        XCTAssertEqual(mockTranscriptionRepo.healthCheckCallCount, 0)
        XCTAssertEqual(mockTranscriptionRepo.transcribeCalls.count, 1)
        XCTAssertEqual(mockTranscriptionRepo.transcribeCalls.first?.audioURL, audioURL)
        XCTAssertEqual(mockTranscriptionStorageRepo.saveTranscriptionCalls.count, 1)
    }
}
