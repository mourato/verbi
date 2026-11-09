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

    /// Regression: the request boundary re-applies `capGroqPrompt` to the
    /// joined prompt, which re-splits comma-containing saved terms into
    /// separate fragments. A term followed by a 795-character term must be
    /// reported exactly as the wire sends it: "A,B" survives as "A, B", the
    /// long term no longer fits the 800-character budget, and the summary
    /// must not claim it would be used.
    func testPromptSupport_SummaryMatchesFinalWireSplittingAtBudgetLimit() {
        let longTerm = String(repeating: "x", count: 795)
        let support = VocabularyRecognitionSupport(
            parameter: .prompt,
            snapshot: snapshot(["A,B", longTerm])
        )

        XCTAssertEqual(support.usedTerms, ["A,B"])
        XCTAssertEqual(support.skippedTerms, [longTerm])
        XCTAssertEqual(support.usedCount, 1)
        XCTAssertEqual(support.skippedCount, 1)
    }

    /// Regression: a comma-containing term cut in half by the wire budget is
    /// only partially sent (first fragments only). It must not be counted as
    /// a completely used term. Sorting is case-insensitive alphabetical
    /// (snapshot normalization), so the filler must sort before "Z".
    func testPromptSupport_DoesNotCountPartiallySentTermAsComplete() {
        let prefixTerm = String(repeating: "y", count: 793)
        let support = VocabularyRecognitionSupport(
            parameter: .prompt,
            snapshot: snapshot([prefixTerm, "Z,Zzz"])
        )

        // The wire prompt becomes "<prefix>, Z" — the second fragment of
        // "Z,Zzz" no longer fits, so the term is partially sent and counts
        // as skipped.
        XCTAssertEqual(support.usedTerms, [prefixTerm])
        XCTAssertEqual(support.skippedTerms, ["Z,Zzz"])
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

    func testPromptSupport_ReportsEveryTermAfterBudgetIsExhausted() {
        let longTerm = String(repeating: "b", count: 800)
        let support = VocabularyRecognitionSupport(
            parameter: .prompt,
            snapshot: snapshot(["alpha", longTerm, "charlie"])
        )

        XCTAssertEqual(support.usedTerms, ["alpha"])
        XCTAssertEqual(support.skippedTerms, [longTerm, "charlie"])
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
