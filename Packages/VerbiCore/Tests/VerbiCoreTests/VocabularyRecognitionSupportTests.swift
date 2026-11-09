@testable import VerbiCoreDomain
import VerbiCoreInfrastructure
import XCTest

final class VocabularyRecognitionSupportTests: XCTestCase {
    private func snapshot(_ terms: [String]) -> VocabularySnapshot {
        VocabularySnapshot(
            terms: terms.map { VocabularyTerm(term: $0, definition: "") },
            replacementRules: []
        )
    }

    func testLocalReceivesNoHints_AllTermsSkipped() {
        let support = VocabularyRecognitionSupport(
            parameter: .none,
            modelID: "parakeet-tdt-0.6b-v3",
            snapshot: snapshot(["SwiftUI", "CoreML"])
        )

        XCTAssertTrue(support.usesRecognitionHints == false)
        XCTAssertTrue(support.usedTerms.isEmpty)
        XCTAssertEqual(support.skippedTerms, ["CoreML", "SwiftUI"])
        XCTAssertEqual(support.usedCount, 0)
        XCTAssertEqual(support.skippedCount, 2)
    }

    func testPromptSupport_MatchesWireProjection() {
        let testSnapshot = snapshot(["SwiftUI", "CoreML"])
        let support = VocabularyRecognitionSupport(
            parameter: .prompt,
            modelID: "gpt-4o-transcribe",
            snapshot: testSnapshot
        )

        // Independent oracle: the boundary projection itself.
        XCTAssertEqual(support.usedTerms, testSnapshot.projectedGroqPrompt()?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
        XCTAssertTrue(support.skippedTerms.isEmpty)
        XCTAssertTrue(support.usesRecognitionHints)
    }

    func testPromptSupport_SkipsTermsBeyondBudget() {
        let support = VocabularyRecognitionSupport(
            parameter: .prompt,
            modelID: "whisper-large-v3-turbo",
            snapshot: snapshot(["alpha", "beta", "gamma"]),
            promptMaxCharacters: 12
        )

        // "alpha, beta" fits in 12 characters; "gamma" does not.
        XCTAssertEqual(support.usedTerms, ["alpha", "beta"])
        XCTAssertEqual(support.skippedTerms, ["gamma"])
    }

    func testKeytermsSupport_MatchesWireProjection() {
        let testSnapshot = snapshot(["SwiftUI", "CoreML"])
        let support = VocabularyRecognitionSupport(
            parameter: .keyterms,
            modelID: "scribe_v2",
            snapshot: testSnapshot
        )

        XCTAssertEqual(support.usedTerms, testSnapshot.projectedElevenLabsKeyterms())
        XCTAssertTrue(support.skippedTerms.isEmpty)
        XCTAssertTrue(support.usesRecognitionHints)
    }

    func testKeytermsSupport_SkipsLongAndUnsupportedCharacters() {
        let longTerm = String(repeating: "a", count: 51)
        let support = VocabularyRecognitionSupport(
            parameter: .keyterms,
            modelID: "scribe_v2",
            snapshot: snapshot(["SwiftUI", longTerm, "bad<term>", "CoreML"])
        )

        XCTAssertEqual(support.usedTerms, ["CoreML", "SwiftUI"])
        XCTAssertEqual(support.skippedTerms, [longTerm, "bad<term>"])
    }

    func testEmptyVocabulary_HasZeroCounts() {
        let support = VocabularyRecognitionSupport(
            parameter: .prompt,
            modelID: "gpt-4o-transcribe",
            snapshot: .empty
        )

        XCTAssertTrue(support.usedTerms.isEmpty)
        XCTAssertTrue(support.skippedTerms.isEmpty)
        XCTAssertEqual(support.usedCount, 0)
        XCTAssertEqual(support.skippedCount, 0)
    }

    func testProviderVocabularyHelper_MatchesAdapters() {
        // Mapping must mirror the routing in TranscriptionClient:
        // Groq/OpenAI whisper-compatible prompt, ElevenLabs keyterms, local none.
        XCTAssertEqual(TranscriptionProvider.local.vocabularyHelper, .none)
        XCTAssertEqual(TranscriptionProvider.groq.vocabularyHelper, .prompt)
        XCTAssertEqual(TranscriptionProvider.openai.vocabularyHelper, .prompt)
        XCTAssertEqual(TranscriptionProvider.elevenLabs.vocabularyHelper, .keyterms)
    }
}
