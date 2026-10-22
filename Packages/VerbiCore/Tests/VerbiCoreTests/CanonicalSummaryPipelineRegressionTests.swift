import Foundation
@testable import VerbiCoreAI
import VerbiCoreDomain
import XCTest

final class CanonicalSummaryPipelineRegressionTests: XCTestCase {
    func testParserAcceptsGeneratedAtWithoutTimezone() throws {
        let json = """
        {
          "schemaVersion": 2,
          "generatedAt": "2026-07-14T15:01:00",
          "title": "Planning Sync",
          "summary": "The team aligned on next steps.",
          "keyPoints": ["Ship fallback fix"],
          "decisions": [],
          "actionItems": [],
          "openQuestions": [],
          "trustFlags": {
            "isGroundedInTranscript": true,
            "containsSpeculation": false,
            "isHumanReviewed": false,
            "confidenceScore": 0.8
          }
        }
        """

        let summary = try CanonicalSummaryResponseParser().parse(from: json)
        XCTAssertEqual(summary.title, "Planning Sync")
        XCTAssertEqual(summary.summary, "The team aligned on next steps.")
        XCTAssertFalse(TranscriptionDisplayText.looksLikeCanonicalSummaryJSON(summary.summary))
    }

    func testDeterministicFallbackNeverPersistsRawJSON() {
        let rawJSON = """
        {
          "schemaVersion": 1,
          "generatedAt": "2026-07-14T15:01:00",
          "title": "Broken",
          "summary": "Should not surface"
        }
        """
        let transcript = "We decided to postpone the launch by one week."
        let result = DeterministicSummaryFallbackBuilder().build(
            providerOutput: rawJSON,
            transcription: transcript,
        )

        XCTAssertEqual(result.outputState, .deterministicFallback)
        XCTAssertFalse(TranscriptionDisplayText.looksLikeCanonicalSummaryJSON(result.processedText))
        XCTAssertFalse(TranscriptionDisplayText.looksLikeCanonicalSummaryJSON(result.canonicalSummary.summary))
        XCTAssertTrue(result.canonicalSummary.summary.contains("postpone"))
    }

    func testDisplayTextPrefersProcessedContentOverCanonicalSummaryJSON() {
        let canonical = CanonicalSummary(
            title: "Broken",
            summary: """
            {
              "schemaVersion": 1,
              "generatedAt": "2026-07-14T15:01:00",
              "summary": "hidden"
            }
            """,
        )
        let display = TranscriptionDisplayText.preferredSummary(
            processedContent: "Clean rendered summary\n\n## Key Points\n- One",
            canonicalSummary: canonical,
            text: "raw transcript",
            emptyFallback: "empty",
        )
        XCTAssertEqual(display, "Clean rendered summary\n\n## Key Points\n- One")
    }
}
