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
        XCTAssertTrue(support.partiallySentTerms.isEmpty)
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

    func testPromptSupport_ReportsPartiallySentTermSeparatelyFromUsedAndSkipped() {
        let prefixTerm = String(repeating: "y", count: 793)
        let support = VocabularyRecognitionSupport(
            parameter: .prompt,
            snapshot: snapshot([prefixTerm, "Z,Zzz"])
        )

        XCTAssertEqual(support.usedTerms, [prefixTerm])
        XCTAssertEqual(support.partiallySentTerms, ["Z,Zzz"])
        XCTAssertTrue(support.skippedTerms.isEmpty)
        XCTAssertEqual(support.usedCount, 1)
        XCTAssertEqual(support.partiallySentCount, 1)
        XCTAssertEqual(support.skippedCount, 0)
    }

    func testPromptSupport_CountsAddUpToAllSavedTermsWithPartialCuts() {
        let prefixTerm = String(repeating: "y", count: 786)
        let support = VocabularyRecognitionSupport(
            parameter: .prompt,
            snapshot: snapshot(["alpha", prefixTerm, "Z,Zzz", "Zzzy"])
        )

        XCTAssertEqual(support.usedTerms, ["alpha", prefixTerm])
        XCTAssertEqual(support.partiallySentTerms, ["Z,Zzz"])
        XCTAssertEqual(support.skippedTerms, ["Zzzy"])
        XCTAssertEqual(
            support.usedCount + support.partiallySentCount + support.skippedCount,
            4
        )
    }

    func testPromptSupport_DoesNotReusePartialFragmentForLaterTerm() {
        let prefixTerm = String(repeating: "y", count: 793)
        let support = VocabularyRecognitionSupport(
            parameter: .prompt,
            snapshot: snapshot([prefixTerm, "Z,Zzz", "Z,Zzzz"])
        )

        XCTAssertEqual(support.usedTerms, [prefixTerm])
        XCTAssertEqual(support.partiallySentTerms, ["Z,Zzz"])
        XCTAssertEqual(support.skippedTerms, ["Z,Zzzz"])
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
        XCTAssertTrue(support.partiallySentTerms.isEmpty)
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
        XCTAssertEqual(TranscriptionProvider.local.vocabularyHelper, .none)
        XCTAssertEqual(TranscriptionProvider.groq.vocabularyHelper, .prompt)
        XCTAssertEqual(TranscriptionProvider.openai.vocabularyHelper, .prompt)
        XCTAssertEqual(TranscriptionProvider.elevenLabs.vocabularyHelper, .keyterms)
    }

    func testProviderHints_SelectingKeepsOnlyTheMappedParameterField() {
        let hints = VocabularyProviderHints(
            groqPrompt: "SwiftUI, Metal",
            elevenLabsKeyterms: ["FictionalHQ"]
        )

        XCTAssertEqual(
            hints.selecting(parameter: .prompt),
            VocabularyProviderHints(groqPrompt: "SwiftUI, Metal", elevenLabsKeyterms: [])
        )
        XCTAssertEqual(
            hints.selecting(parameter: .keyterms),
            VocabularyProviderHints(groqPrompt: nil, elevenLabsKeyterms: ["FictionalHQ"])
        )
        XCTAssertNil(hints.selecting(parameter: .none))
    }
}
