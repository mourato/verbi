@testable import VerbiCore
import XCTest

final class TranscriptionModelPromptFieldsTests: XCTestCase {
    func testInit_PreservesPostProcessingRequestPrompts() {
        let transcription = CaptureArtifact(
            meeting: CaptureSession(app: .unknown),
            text: "processed",
            rawText: "raw",
            postProcessingRequestSystemPrompt: "system prompt",
            postProcessingRequestUserPrompt: "user prompt",
        )

        XCTAssertEqual(transcription.postProcessingRequestSystemPrompt, "system prompt")
        XCTAssertEqual(transcription.postProcessingRequestUserPrompt, "user prompt")
    }
}
