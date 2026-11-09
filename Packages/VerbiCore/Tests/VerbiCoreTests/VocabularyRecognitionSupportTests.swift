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
            snapshot: testSnapshot
        )

        XCTAssertEqual(support.usedTerms, ["CoreML", "SwiftUI"])
        XCTAssertTrue(support.skippedTerms.isEmpty)
        XCTAssertTrue(support.usesRecognitionHints)
    }

    func testPromptSupport_SkipsTermsBeyondBudget() {
        let support = VocabularyRecognitionSupport(
            parameter: .prompt,
            snapshot: snapshot(["alpha", "beta", String(repeating: "g", count: 800)])
        )

        // The first two terms fit; the final term exceeds the remaining wire budget.
        XCTAssertEqual(support.usedTerms, ["alpha", "beta"])
        XCTAssertEqual(support.skippedTerms, [String(repeating: "g", count: 800)])
    }

    func testPromptSupport_CountsCommaContainingSavedTermOnce() {
        let support = VocabularyRecognitionSupport(
            parameter: .prompt,
            snapshot: snapshot(["Acme, Inc", "SwiftUI"])
        )

        XCTAssertEqual(support.usedTerms, ["Acme, Inc", "SwiftUI"])
        XCTAssertEqual(support.usedCount, 2)
        XCTAssertEqual(support.skippedCount, 0)
    }

    func testKeytermsSupport_MatchesWireProjection() {
        let testSnapshot = snapshot(["SwiftUI", "CoreML"])
        let support = VocabularyRecognitionSupport(
            parameter: .keyterms,
            snapshot: testSnapshot
        )

        XCTAssertEqual(support.usedTerms, ["CoreML", "SwiftUI"])
        XCTAssertTrue(support.skippedTerms.isEmpty)
        XCTAssertTrue(support.usesRecognitionHints)
    }

    func testKeytermsSupport_SkipsLongAndUnsupportedCharacters() {
        let longTerm = String(repeating: "a", count: 51)
        let support = VocabularyRecognitionSupport(
            parameter: .keyterms,
            snapshot: snapshot(["SwiftUI", longTerm, "bad<term>", "CoreML"])
        )

        XCTAssertEqual(support.usedTerms, ["CoreML", "SwiftUI"])
        XCTAssertEqual(support.skippedTerms, [longTerm, "bad<term>"])
    }

    func testEmptyVocabulary_HasZeroCounts() {
        let support = VocabularyRecognitionSupport(
            parameter: .prompt,
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
