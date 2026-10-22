import Foundation
@testable import VerbiCore
@testable import VerbiCoreDomain
import XCTest

final class PostProcessingFailureTests: XCTestCase {
    func testSkippedPostProcessingPersistsFailureReason() async throws {
        let speechRecognitionClient = VerbiCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()
        let postProcessingRepository = VerbiCoreDomain.MacroMockPostProcessingRepository()
        let failureReason = "Post-processing was not performed: an API key is missing."
        var persistedTranscription: CaptureArtifactEntity?

        speechRecognitionClient.transcribeHandler = { _, _ in
            DomainTranscriptionResponse(
                text: "Raw transcript",
                language: "en",
                durationSeconds: 1.0,
                model: "test-model",
                processedAt: "now",
            )
        }
        storageRepository.saveTranscriptionHandler = { persistedTranscription = $0 }

        let useCase = TranscribeAudioUseCase(
            speechRecognitionClient: speechRecognitionClient,
            transcriptionStorageRepository: storageRepository,
            postProcessingRepository: postProcessingRepository,
        )
        let transcription = try await useCase.execute(
            audioURL: URL(fileURLWithPath: "/tmp/test.wav"),
            meeting: CaptureSessionEntity(app: .googleMeet),
            applyPostProcessing: false,
            postProcessingFailureReason: failureReason,
        )

        XCTAssertEqual(transcription.postProcessingFailureReason, failureReason)
        XCTAssertEqual(persistedTranscription?.postProcessingFailureReason, failureReason)
        XCTAssertNil(transcription.processedContent)
        XCTAssertEqual(postProcessingRepository.processTranscriptionStructured_5Calls.count, 0)
    }
}
