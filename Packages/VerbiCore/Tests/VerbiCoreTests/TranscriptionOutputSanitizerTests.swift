@testable import VerbiCore
import XCTest

final class TranscriptionOutputSanitizerTests: XCTestCase {
    func testSanitize_WhenOutputContainsContextBlock_RemovesBlockAndKeepsText() {
        let input = "Clean text\n\n<CONTEXT_METADATA>\n- Active window OCR: leaked\n</CONTEXT_METADATA>"

        let result = TranscriptionOutputSanitizer.sanitize(
            processedContent: input,
            contextMetadata: nil,
        )

        XCTAssertEqual(result.text, "Clean text")
        XCTAssertTrue(result.removedReservedBlocks)
        XCTAssertFalse(result.contextLeakDetected)
    }

    func testSanitize_WhenOutputContainsOnlyContextBlock_ReturnsNilText() {
        let input = "<CONTEXT_METADATA>\n- Active window OCR: leaked\n</CONTEXT_METADATA>"

        let result = TranscriptionOutputSanitizer.sanitize(
            processedContent: input,
            contextMetadata: nil,
        )

        XCTAssertNil(result.text)
        XCTAssertTrue(result.removedReservedBlocks)
        XCTAssertFalse(result.contextLeakDetected)
    }

    func testSanitize_WhenContextMarkerRemains_DetectsLeakage() {
        let input = "CONTEXT_METADATA\n- Active window OCR: leaked"

        let result = TranscriptionOutputSanitizer.sanitize(
            processedContent: input,
            contextMetadata: nil,
        )

        XCTAssertNil(result.text)
        XCTAssertFalse(result.removedReservedBlocks)
        XCTAssertTrue(result.contextLeakDetected)
    }

    func testExtractContextMetadata_WhenMergedInputContainsBlock_ReturnsContextBody() {
        let mergedInput = """
        dictation content

        <CONTEXT_METADATA>
        - Active app: Visual Studio Code
        - Focused text: Build log
        </CONTEXT_METADATA>
        """

        let extracted = TranscriptionOutputSanitizer.extractContextMetadata(fromPromptInput: mergedInput)

        XCTAssertEqual(
            extracted,
            "- Active app: Visual Studio Code\n- Focused text: Build log",
        )
    }

    func testStripPromptMetadata_WhenMergedInputContainsReservedBlocks_KeepsOnlyTranscriptText() {
        let mergedInput = """
        Esse aqui e um exemplo do output de um ditado rapido.

        <CONTEXT_METADATA>
        - Active app: Visual Studio Code
        </CONTEXT_METADATA>
        """

        let stripped = TranscriptionOutputSanitizer.stripPromptMetadata(from: mergedInput)

        XCTAssertEqual(stripped, "Esse aqui e um exemplo do output de um ditado rapido.")
    }
}
