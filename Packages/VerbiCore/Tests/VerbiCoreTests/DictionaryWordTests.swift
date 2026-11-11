@testable import VerbiCore
@testable import VerbiCoreDomain
import XCTest

/// Proves the unified word projection and the unified hint list.
final class DictionaryWordTests: XCTestCase {
    // MARK: - words(terms:rules:)

    func testTermJoinsGroupWithMatchingDestination() {
        let term = VocabularyTerm(term: "Raycast", definition: "launcher")
        let rule = VocabularyReplacementRule(find: "raycast, reycast", replace: "Raycast")

        let words = DictionaryWord.words(terms: [term], rules: [rule])

        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words.first?.word, "Raycast")
        XCTAssertEqual(words.first?.heardAs, ["raycast", "reycast"])
        XCTAssertEqual(words.first?.termID, term.id)
        XCTAssertEqual(words.first?.groupID, rule.id)
        XCTAssertEqual(words.first?.id, rule.id)
        XCTAssertFalse(words.first?.isTextRemoval == true)
    }

    func testStandaloneTermBecomesWordWithoutVariants() {
        let term = VocabularyTerm(term: "SwiftUI", definition: "")

        let words = DictionaryWord.words(terms: [term], rules: [])

        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words.first?.word, "SwiftUI")
        XCTAssertEqual(words.first?.heardAs, [])
        XCTAssertEqual(words.first?.termID, term.id)
        XCTAssertNil(words.first?.groupID)
        XCTAssertEqual(words.first?.id, term.id)
    }

    func testTermJoinIsCaseSensitiveLikeDestinations() {
        let term = VocabularyTerm(term: "groq", definition: "")
        let rule = VocabularyReplacementRule(find: "groc", replace: "Groq")

        let words = DictionaryWord.words(terms: [term], rules: [rule])

        XCTAssertEqual(words.map(\.word), ["Groq", "groq"])
        XCTAssertEqual(words.first?.heardAs, ["groc"])
        XCTAssertNil(words.first?.termID)
    }

    func testWordsSortAlphabeticallyWithRemovalsLast() throws {
        let rules = [
            VocabularyReplacementRule(find: "hum, uhm", replace: ""),
            VocabularyReplacementRule(find: "swyft you eye", replace: "SwiftUI"),
            VocabularyReplacementRule(find: "groc", replace: "Groq")
        ]

        let words = DictionaryWord.words(terms: [], rules: rules)

        XCTAssertEqual(words.map(\.word), ["Groq", "SwiftUI", ""])
        let removal = try XCTUnwrap(words.last)
        XCTAssertTrue(removal.isTextRemoval)
        XCTAssertEqual(removal.heardAs, ["hum", "uhm"])
    }

    func testRemovalLinesSortByFirstVariant() throws {
        // Legacy data can only hold one removal group (all share destination
        // ""), so multiple removal rules consolidate into one line.
        let rules = [
            VocabularyReplacementRule(find: "uhm", replace: ""),
            VocabularyReplacementRule(find: "hum", replace: "")
        ]

        let words = DictionaryWord.words(terms: [], rules: rules)

        XCTAssertEqual(words.count, 1)
        let removal = try XCTUnwrap(words.first)
        XCTAssertTrue(removal.isTextRemoval)
        XCTAssertEqual(removal.heardAs, ["uhm", "hum"])
    }

    func testEmptyTermSpellingsAreSkipped() {
        let terms = [VocabularyTerm(term: "   ", definition: "")]

        XCTAssertTrue(DictionaryWord.words(terms: terms, rules: []).isEmpty)
    }

    // MARK: - VocabularyTerm.hints(savedTerms:replacementRules:)

    func testHintsUniteSavedTermsAndRuleDestinations() {
        let saved = [VocabularyTerm(term: "SwiftUI", definition: "framework")]
        let rules = [VocabularyReplacementRule(find: "groc", replace: "Groq")]

        let hints = VocabularyTerm.hints(savedTerms: saved, replacementRules: rules)

        XCTAssertEqual(hints.map(\.term), ["Groq", "SwiftUI"])
    }

    func testSavedTermWinsCaseInsensitiveDeduplication() {
        let saved = [VocabularyTerm(term: "groq", definition: "kept")]
        let rules = [VocabularyReplacementRule(find: "groc", replace: "Groq")]

        let hints = VocabularyTerm.hints(savedTerms: saved, replacementRules: rules)

        XCTAssertEqual(hints.count, 1)
        XCTAssertEqual(hints.first?.term, "groq")
        XCTAssertEqual(hints.first?.definition, "kept")
        XCTAssertEqual(hints.first?.id, saved.first?.id)
    }

    func testRemovalDestinationsNeverBecomeHints() {
        let rules = [VocabularyReplacementRule(find: "hum, uhm", replace: "")]

        XCTAssertTrue(VocabularyTerm.hints(savedTerms: [], replacementRules: rules).isEmpty)
    }

    func testDerivedHintsCarryDeterministicGroupIDs() {
        let rule = VocabularyReplacementRule(find: "groc", replace: "Groq")
        let rules = [rule]

        let first = VocabularyTerm.hints(savedTerms: [], replacementRules: rules)
        let second = VocabularyTerm.hints(savedTerms: [], replacementRules: rules)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.first?.id, rule.id)
        XCTAssertEqual(first.first?.definition, "")
    }
}
