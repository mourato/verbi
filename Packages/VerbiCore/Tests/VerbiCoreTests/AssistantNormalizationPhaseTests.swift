@testable import VerbiCoreUI
import XCTest

@MainActor
final class AssistantNormalizationPhaseTests: XCTestCase {
    private let phase = AssistantNormalizationPhase()

    // MARK: - applyNormalization

    func testApplyNormalization_AssistantMode_FallsBackToCommand() {
        let result = phase.applyNormalization(
            processedCommand: "  ",
            command: "fallback command",
            executionFlow: .assistantMode,
            sourceText: "source text",
        )
        XCTAssertEqual(result, "fallback command")
    }

    func testApplyNormalization_AssistantMode_FallsBackToSourceText() {
        let result = phase.applyNormalization(
            processedCommand: "  ",
            command: "  ",
            executionFlow: .assistantMode,
            sourceText: "source text",
        )
        XCTAssertEqual(result, "source text")
    }

    func testApplyNormalization_AssistantMode_UsesProcessedCommand() {
        let result = phase.applyNormalization(
            processedCommand: "processed result",
            command: "ignored",
            executionFlow: .assistantMode,
            sourceText: "ignored",
        )
        XCTAssertEqual(result, "processed result")
    }

    func testApplyNormalization_IntegrationDispatch_ReturnsEmptyWhenAllFallbacksFail() {
        let result = phase.applyNormalization(
            processedCommand: "  ",
            command: "original command",
            executionFlow: .integrationDispatch,
            sourceText: "ignored",
        )
        XCTAssertEqual(result, "")
    }

    func testApplyNormalization_IntegrationDispatch_UsesProcessedCommand() {
        let result = phase.applyNormalization(
            processedCommand: "integration output",
            command: "original command",
            executionFlow: .integrationDispatch,
            sourceText: "ignored",
        )
        XCTAssertEqual(result, "integration output")
    }

    // MARK: - normalizedCommand

    func testNormalizedCommand_ReturnsNormalized() {
        let result = phase.normalizedCommand("  hello world  ", fallback: "fallback")
        XCTAssertEqual(result, "hello world")
    }

    func testNormalizedCommand_ReturnsFallbackWhenEmpty() {
        let result = phase.normalizedCommand("  ", fallback: "fallback text")
        XCTAssertEqual(result, "fallback text")
    }

    func testNormalizedCommand_ReturnsFallbackWhenWhitespaceOnly() {
        let result = phase.normalizedCommand("\n\t  \n", fallback: "fallback")
        XCTAssertEqual(result, "fallback")
    }

    // MARK: - requireNonEmptyCommand

    func testRequireNonEmptyCommand_ReturnsNormalized() throws {
        let result = try phase.requireNonEmptyCommand("  valid  ", fallback: nil)
        XCTAssertEqual(result, "valid")
    }

    func testRequireNonEmptyCommand_ThrowsWhenEmptyAndNoFallback() {
        XCTAssertThrowsError(try phase.requireNonEmptyCommand("  ", fallback: nil))
    }

    func testRequireNonEmptyCommand_UsesFallbackWhenMainEmpty() throws {
        let result = try phase.requireNonEmptyCommand("  ", fallback: "fallback text")
        XCTAssertEqual(result, "fallback text")
    }

    func testRequireNonEmptyCommand_ThrowsWhenBothEmpty() {
        XCTAssertThrowsError(try phase.requireNonEmptyCommand("  ", fallback: "  "))
    }

    // MARK: - urlEncoded

    func testUrlEncoded_EncodesSpecialCharacters() {
        let result = phase.urlEncoded("hello world & more")
        XCTAssertEqual(result, "hello%20world%20%26%20more")
    }

    func testUrlEncoded_HandlesPlainText() {
        let result = phase.urlEncoded("simple")
        XCTAssertEqual(result, "simple")
    }

    func testUrlEncoded_HandlesEmptyString() {
        let result = phase.urlEncoded("")
        XCTAssertEqual(result, "")
    }
}
