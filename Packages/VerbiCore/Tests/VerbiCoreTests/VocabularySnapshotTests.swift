@testable import VerbiCoreDomain
import XCTest

final class VocabularySnapshotTests: XCTestCase {
    func testInit_NormalizesAndDedupesTerms() {
        let snapshot = VocabularySnapshot(
            terms: [
                VocabularyTerm(term: "  SwiftUI ", definition: " UI "),
                VocabularyTerm(term: "swiftui", definition: "dup"),
                VocabularyTerm(term: "", definition: "empty"),
                VocabularyTerm(term: "Metal", definition: ""),
            ],
            replacementRules: [
                VocabularyReplacementRule(find: "ay eye", replace: "AI"),
                VocabularyReplacementRule(find: "  ", replace: "x"),
            ],
        )

        XCTAssertEqual(snapshot.terms.map(\.term), ["Metal", "SwiftUI"])
        XCTAssertEqual(snapshot.terms[1].definition, "UI")
        XCTAssertEqual(snapshot.replacementRules.count, 1)
        XCTAssertEqual(snapshot.replacementRules[0].find, "ay eye")
    }

    func testEmpty_HasNoHintsOrContext() {
        XCTAssertTrue(VocabularySnapshot.empty.providerHints.isEmpty)
        XCTAssertNil(VocabularySnapshot.empty.projectedGroqPrompt())
        XCTAssertTrue(VocabularySnapshot.empty.projectedElevenLabsKeyterms().isEmpty)
        XCTAssertNil(VocabularySnapshot.empty.postProcessingContext)
        XCTAssertEqual(VocabularySnapshot.empty.prependToContext("base"), "base")
    }

    func testProjectedGroqPrompt_RespectsCharacterBudgetWithWholeTermsOnly() {
        let snapshot = VocabularySnapshot(
            terms: [
                VocabularyTerm(term: "alpha", definition: ""),
                VocabularyTerm(term: "beta", definition: ""),
                VocabularyTerm(term: "gamma", definition: ""),
            ],
            replacementRules: [],
        )

        // "alpha, beta" = 11 chars; adding ", gamma" would exceed budget 12.
        let prompt = snapshot.projectedGroqPrompt(maxCharacters: 12)
        XCTAssertEqual(prompt, "alpha, beta")
    }

    func testProjectedElevenLabsKeyterms_SkipsLongAndUnsupportedCharacters() {
        let longTerm = String(repeating: "a", count: 51)
        let snapshot = VocabularySnapshot(
            terms: [
                VocabularyTerm(term: "SwiftUI", definition: "ignored definition"),
                VocabularyTerm(term: longTerm, definition: ""),
                VocabularyTerm(term: "bad<term>", definition: ""),
                VocabularyTerm(term: "CoreML", definition: ""),
            ],
            replacementRules: [],
        )

        XCTAssertEqual(
            snapshot.projectedElevenLabsKeyterms(maxTerms: 1_000, maxCharactersPerTerm: 50),
            ["CoreML", "SwiftUI"],
        )
        XCTAssertEqual(
            snapshot.projectedElevenLabsKeyterms(maxTerms: 1, maxCharactersPerTerm: 50),
            ["CoreML"],
        )
    }

    func testProviderHints_OmitDefinitionsAndPopulateBothProjections() {
        let snapshot = VocabularySnapshot(
            terms: [VocabularyTerm(term: "Prisma", definition: "should not appear in hints")],
            replacementRules: [],
        )
        let hints = snapshot.providerHints
        XCTAssertEqual(hints.groqPrompt, "Prisma")
        XCTAssertEqual(hints.elevenLabsKeyterms, ["Prisma"])
        XCTAssertFalse(hints.groqPrompt?.contains("should not appear") == true)
    }

    func testPostProcessingContext_EscapesQuotesControlCharsAndDelimiterTags() throws {
        let snapshot = VocabularySnapshot(
            terms: [
                VocabularyTerm(term: "say \"hello\"\u{0007}<VOCABULARY>world</VOCABULARY>", definition: ""),
            ],
            replacementRules: [],
        )

        let context = try XCTUnwrap(snapshot.postProcessingContext)
        XCTAssertTrue(context.contains("\\\"hello\\\""))
        XCTAssertFalse(context.contains("\u{0007}"))
        // Injected delimiter tags are neutralized inside the term payload.
        XCTAssertFalse(context.contains("world</VOCABULARY>"))
        XCTAssertFalse(context.contains("<VOCABULARY>world"))
        // Outer wrapper delimiters remain exactly once each.
        XCTAssertEqual(context.components(separatedBy: "<VOCABULARY>").count - 1, 1)
        XCTAssertEqual(context.components(separatedBy: "</VOCABULARY>").count - 1, 1)
    }

    func testWireLimitHelpers_CapPromptAndKeyterms() {
        let long = String(repeating: "a", count: 51)
        let prompt = VocabularyProviderHints.capGroqPrompt("alpha, beta, gamma", maxCharacters: 12)
        XCTAssertEqual(prompt, "alpha, beta")

        let keyterms = VocabularyProviderHints.capElevenLabsKeyterms(
            ["SwiftUI", long, "bad<term>", "Metal"],
            maxTerms: 10,
            maxCharactersPerTerm: 50,
        )
        XCTAssertEqual(keyterms, ["SwiftUI", "Metal"])
    }

    func testPrependToContext_CombinesVocabularyAndBase() throws {
        let snapshot = VocabularySnapshot(
            terms: [VocabularyTerm(term: "Metal", definition: "")],
            replacementRules: [],
        )
        let combined = try XCTUnwrap(snapshot.prependToContext("Meeting notes"))
        XCTAssertTrue(combined.contains("<VOCABULARY>"))
        XCTAssertTrue(combined.contains("Meeting notes"))
        XCTAssertTrue(combined.contains("\n\n"))
    }
}
