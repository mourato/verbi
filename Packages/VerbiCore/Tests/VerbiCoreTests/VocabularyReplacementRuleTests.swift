@testable import VerbiCore
import XCTest

final class VocabularyReplacementRuleTests: XCTestCase {
    func testNormalizedVariants_TrimsDeduplicatesAndDropsEmptyEntries() {
        let variants = VocabularyReplacementRule.normalizedVariants(
            from: " raycast, reycast , , recast, Raycast ",
        )

        XCTAssertEqual(variants, ["raycast", "reycast", "recast"])
    }

    func testApply_WhenRuleHasMultipleVariants_ReplacesAllMatches() {
        let output = VocabularyReplacementRule.apply(
            rules: [
                VocabularyReplacementRule(find: "raycast, reycast, recast", replace: "Raycast"),
            ],
            to: "Raycast works better than reycast, and recast too.",
        )

        XCTAssertEqual(output, "Raycast works better than Raycast, and Raycast too.")
    }

    func testApply_WhenVariantsContainSpaces_RemainsWholeWordAndCaseInsensitive() {
        let output = VocabularyReplacementRule.apply(
            rules: [
                VocabularyReplacementRule(find: "eleven labs, elevan labs, elaven labs", replace: "ElevenLabs"),
            ],
            to: "ELEVEN LABS is not the same as eleven labsy, but elevan labs should match.",
        )

        XCTAssertEqual(output, "ElevenLabs is not the same as eleven labsy, but ElevenLabs should match.")
    }

    func testApply_WhenReplacementIsEmpty_RemovesAllMatchedVariants() {
        let output = VocabularyReplacementRule.apply(
            rules: [
                VocabularyReplacementRule(find: "um, uh", replace: ""),
            ],
            to: "um I think uh this works",
        )

        XCTAssertEqual(output, " I think  this works")
    }

    // MARK: - Edge case tests for preserved substitution semantics

    func testApply_EmptyRulesLeavesTextUnchanged() {
        let output = VocabularyReplacementRule.apply(
            rules: [],
            to: "the quick brown fox",
        )

        XCTAssertEqual(output, "the quick brown fox")
    }

    func testApply_SimpleExactMatch() {
        let output = VocabularyReplacementRule.apply(
            rules: [VocabularyReplacementRule(find: "macos", replace: "macOS")],
            to: "I love macos for development",
        )

        XCTAssertEqual(output, "I love macOS for development")
    }

    func testApply_CaseInsensitiveReplacement() {
        let output = VocabularyReplacementRule.apply(
            rules: [VocabularyReplacementRule(find: "prisma", replace: "Prisma")],
            to: "PRISMA is great and prisma works well",
        )

        XCTAssertEqual(output, "Prisma is great and Prisma works well")
    }

    func testApply_WholeWordBoundary_DoesNotMatchSubstring() {
        let output = VocabularyReplacementRule.apply(
            rules: [VocabularyReplacementRule(find: "code", replace: "Code")],
            to: "decode and code are different",
        )

        // "code" in "decode" has no word boundary before it ("e" is a word char, "c" is a word char)
        // so \bcode\b does not match "decode".
        XCTAssertEqual(output, "decode and Code are different")
    }

    func testApply_LiteralDollarSignInFindAndReplace() {
        let output = VocabularyReplacementRule.apply(
            rules: [VocabularyReplacementRule(find: "cost", replace: "$5.00")],
            to: "The total cost is",
        )

        // The replacement $5.00 should be treated as literal text, not a regex backreference
        XCTAssertEqual(output, "The total $5.00 is")
    }

    func testApply_LiteralBackslashInReplacement() {
        let output = VocabularyReplacementRule.apply(
            rules: [VocabularyReplacementRule(find: "path", replace: "/usr/local/bin")],
            to: "the default path is",
        )

        XCTAssertEqual(output, "the default /usr/local/bin is")
    }

    func testApply_LiteralDollarAndBackslashCombined() {
        let output = VocabularyReplacementRule.apply(
            rules: [VocabularyReplacementRule(find: "var", replace: "$VAR \\escaped")],
            to: "the var is set",
        )

        XCTAssertEqual(output, "the $VAR \\escaped is set")
    }

    func testApply_PunctuationAroundFind_RespectsBoundary() {
        let output = VocabularyReplacementRule.apply(
            rules: [VocabularyReplacementRule(find: "hello", replace: "hi")],
            to: "hello, hello! \"hello\" (hello) hello.",
        )

        XCTAssertEqual(output, "hi, hi! \"hi\" (hi) hi.")
    }

    func testApply_MultipleRulesAppliedInOrder() {
        let output = VocabularyReplacementRule.apply(
            rules: [
                VocabularyReplacementRule(find: "macos", replace: "macOS"),
                VocabularyReplacementRule(find: "macOS", replace: "MacOS"),
            ],
            to: "I use macos every day",
        )

        // First rule: macos -> macOS. Second rule: macOS -> MacOS.
        XCTAssertEqual(output, "I use MacOS every day")
    }

    func testApply_LongerFindTakesPriority_WhenOverlappingVariantsExist() {
        let output = VocabularyReplacementRule.apply(
            rules: [
                VocabularyReplacementRule(find: "new york city, new york", replace: "NYC"),
            ],
            to: "I live in new york, but new york city is bigger",
        )

        // Longer "new york city" should be tried first (sorted by length descending)
        XCTAssertEqual(output, "I live in NYC, but NYC is bigger")
    }

    func testApply_NonOverlappingRules_AllApplied() {
        let output = VocabularyReplacementRule.apply(
            rules: [
                VocabularyReplacementRule(find: "macos", replace: "macOS"),
                VocabularyReplacementRule(find: "ios", replace: "iOS"),
            ],
            to: "I develop on macos and ios",
        )

        XCTAssertEqual(output, "I develop on macOS and iOS")
    }

    func testApply_EmptyFindVariant_IsIgnored() {
        let output = VocabularyReplacementRule.apply(
            rules: [VocabularyReplacementRule(find: "foo, , bar", replace: "baz")],
            to: "foo and bar are foobar",
        )

        // Empty variant skipped, "foo" and "bar" are separate variants
        XCTAssertEqual(output, "baz and baz are foobar")
    }

    func testApply_NoMatchFound_ReturnsOriginalText() {
        let output = VocabularyReplacementRule.apply(
            rules: [VocabularyReplacementRule(find: "nonexistent", replace: "replaced")],
            to: "this text has no match",
        )

        XCTAssertEqual(output, "this text has no match")
    }

    func testApply_ReplaceWithSameText_DoesNothing() {
        let output = VocabularyReplacementRule.apply(
            rules: [VocabularyReplacementRule(find: "same", replace: "same")],
            to: "this is the same text",
        )

        XCTAssertEqual(output, "this is the same text")
    }

    func testApply_NumberInFind_MatchesCorrectly() {
        let output = VocabularyReplacementRule.apply(
            rules: [VocabularyReplacementRule(find: "2.0, 3.0", replace: "latest")],
            to: "version 2.0 is out, 3.0 is coming",
        )

        XCTAssertEqual(output, "version latest is out, latest is coming")
    }

    func testApply_WithApostrophe_UsesWholeWord() {
        let output = VocabularyReplacementRule.apply(
            rules: [VocabularyReplacementRule(find: "dont", replace: "don't")],
            to: "dont do that, dont's are tricky",
        )

        // "dont" matches whole word in "dont do that" but in "dont's" the apostrophe s
        // is a word boundary after "dont" — so it still matches
        XCTAssertEqual(output, "don't do that, don't's are tricky")
    }

    func testApply_ToSegments_ReplacesTextInEachSegment() {
        struct TestSegment: VocabularyReplaceableSegment, Equatable {
            let id: UUID
            let speaker: String
            let text: String
            let startTime: Double
            let endTime: Double
        }

        let segments: [TestSegment] = [
            TestSegment(
                id: UUID(),
                speaker: "Alice",
                text: "I use macos for work",
                startTime: 0.0,
                endTime: 1.0,
            ),
            TestSegment(
                id: UUID(),
                speaker: "Bob",
                text: "macos is great",
                startTime: 1.0,
                endTime: 2.0,
            ),
        ]

        let result = VocabularyReplacementRule.apply(
            rules: [VocabularyReplacementRule(find: "macos", replace: "macOS")],
            to: segments,
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].text, "I use macOS for work")
        XCTAssertEqual(result[1].text, "macOS is great")
        XCTAssertEqual(result[0].speaker, "Alice")
        XCTAssertEqual(result[1].speaker, "Bob")
    }

    func testApply_ToSegments_WithEmptyRules_TextUnchanged() {
        struct TestSegment: VocabularyReplaceableSegment, Equatable {
            let id: UUID
            let speaker: String
            let text: String
            let startTime: Double
            let endTime: Double
        }

        let segments: [TestSegment] = [
            TestSegment(
                id: UUID(),
                speaker: "Alice",
                text: "hello world",
                startTime: 0.0,
                endTime: 1.0,
            ),
        ]

        let result = VocabularyReplacementRule.apply(rules: [], to: segments)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "hello world")
    }

    func testNormalizedVariants_EmptyInput_ReturnsEmptyArray() {
        let variants = VocabularyReplacementRule.normalizedVariants(from: "")
        XCTAssertTrue(variants.isEmpty)
    }

    func testNormalizedVariants_OnlyCommas_ReturnsEmptyArray() {
        let variants = VocabularyReplacementRule.normalizedVariants(from: ", ,,")
        XCTAssertTrue(variants.isEmpty)
    }

    func testNormalizedVariants_PreservesOrder() {
        let variants = VocabularyReplacementRule.normalizedVariants(from: "zeta, alpha, beta")
        XCTAssertEqual(variants, ["zeta", "alpha", "beta"])
    }

    func testNormalizedVariants_DeduplicatesCaseInsensitivity() {
        let variants = VocabularyReplacementRule.normalizedVariants(from: "Foo, foo, FOO")
        XCTAssertEqual(variants, ["Foo"])
    }
}
