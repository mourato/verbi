// DomainLayerTests - Testes unitários para os casos de uso do domínio
// Usando MacroMocks (@GenerateMock) para mocks

@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreDomain
import XCTest

final class DomainLayerTests: XCTestCase {
    var mockRecordingRepo: MeetingAssistantCoreDomain.MacroMockRecordingRepository?
    var mockAudioFileRepo: MeetingAssistantCoreDomain.MacroMockAudioFileRepository?
    var mockMeetingRepo: MeetingAssistantCoreDomain.MacroMockMeetingRepository?
    var mockTranscriptionRepo: MeetingAssistantCoreDomain.MacroMockSpeechRecognitionClient?
    var mockTranscriptionStorageRepo: MeetingAssistantCoreDomain.MacroMockTranscriptionStorageRepository?
    var mockPostProcessingRepo: MeetingAssistantCoreDomain.MacroMockPostProcessingRepository?

    override func setUp() {
        super.setUp()
        mockRecordingRepo = MeetingAssistantCoreDomain.MacroMockRecordingRepository()
        mockAudioFileRepo = MeetingAssistantCoreDomain.MacroMockAudioFileRepository()
        mockMeetingRepo = MeetingAssistantCoreDomain.MacroMockMeetingRepository()
        mockTranscriptionRepo = MeetingAssistantCoreDomain.MacroMockSpeechRecognitionClient()
        mockTranscriptionStorageRepo = MeetingAssistantCoreDomain.MacroMockTranscriptionStorageRepository()
        mockPostProcessingRepo = MeetingAssistantCoreDomain.MacroMockPostProcessingRepository()
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

    // MARK: - StartRecordingUseCase Tests

    func testStartRecordingSuccess() async throws {
        // Given
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
        let meeting = MeetingEntity(app: .googleMeet)
        let expectedURL = URL(fileURLWithPath: "/tmp/test.wav")

        mockRecordingRepo.hasPermissionHandler = { () async -> Bool in true }
        mockRecordingRepo.startRecordingHandler = { _, _ in }
        mockAudioFileRepo.generateAudioFileURLHandler = { _ in expectedURL }
        mockMeetingRepo.updateMeetingHandler = { _ in }

        // When
        let resultURL = try await useCase.execute(for: meeting)

        // Then
        XCTAssertEqual(resultURL, expectedURL)
        XCTAssertEqual(mockRecordingRepo.hasPermissionCallCount, 1)
        XCTAssertEqual(mockRecordingRepo.startRecordingCalls.count, 1)
        XCTAssertEqual(mockRecordingRepo.startRecordingCalls.first?.outputURL, expectedURL)
        XCTAssertEqual(mockRecordingRepo.startRecordingCalls.first?.retryCount, 3)
        XCTAssertEqual(mockMeetingRepo.updateMeetingCalls.count, 1)
    }

    func testStartRecordingPermissionDenied() async {
        // Given
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
        let meeting = MeetingEntity(app: .googleMeet)

        mockRecordingRepo.hasPermissionHandler = { () async -> Bool in false }

        // When/Then
        do {
            _ = try await useCase.execute(for: meeting)
            XCTFail("Should throw permissionDenied")
        } catch RecordingError.permissionDenied {
            // Success
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - TranscribeAudioUseCase Tests

    func testTranscribeAudioSuccess() async throws {
        // Given
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
        let meeting = MeetingEntity(app: .googleMeet)
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

        // When
        let transcription = try await useCase.execute(audioURL: audioURL, meeting: meeting)

        // Then
        XCTAssertEqual(transcription.text, "Hello world")
        XCTAssertEqual(transcription.meeting.id, meeting.id)
        XCTAssertEqual(mockTranscriptionRepo.healthCheckCallCount, 0)
        XCTAssertEqual(mockTranscriptionRepo.transcribeCalls.count, 1)
        XCTAssertEqual(mockTranscriptionRepo.transcribeCalls.first?.audioURL, audioURL)
        XCTAssertEqual(mockTranscriptionStorageRepo.saveTranscriptionCalls.count, 1)
    }
}
