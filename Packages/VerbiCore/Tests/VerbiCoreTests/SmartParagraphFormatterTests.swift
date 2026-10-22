@testable import VerbiCore
import XCTest

final class SmartParagraphFormatterTests: XCTestCase {
    func testFormat_LeavesShortTextUnchanged() {
        let text = "Quick note. All done."

        XCTAssertEqual(SmartParagraphFormatter.format(dictatedText: text), text)
    }

    func testFormat_BreaksAfterFourSubstantialSentences() {
        let text = [
            "We reviewed the roadmap and captured all launch blockers.",
            "The design team confirmed the new sidebar and toolbar direction.",
            "Engineering agreed to finish the migration before the beta cutoff.",
            "Support prepared the updated macros for customer rollout questions.",
            "Marketing will publish the announcement once the release build is ready.",
        ].joined(separator: " ")

        let expected = [
            "We reviewed the roadmap and captured all launch blockers. The design team confirmed the new sidebar and toolbar direction. Engineering agreed to finish the migration before the beta cutoff. Support prepared the updated macros for customer rollout questions.",
            "Marketing will publish the announcement once the release build is ready.",
        ].joined(separator: "\n\n")

        XCTAssertEqual(SmartParagraphFormatter.format(dictatedText: text), expected)
    }

    func testFormat_IgnoresShortInterjectionsForSentenceCap() {
        let text = [
            "Yes.",
            "OK.",
            "We reviewed the roadmap and captured all launch blockers.",
            "The design team confirmed the new sidebar and toolbar direction.",
            "Engineering agreed to finish the migration before the beta cutoff.",
            "Support prepared the updated macros for customer rollout questions.",
            "Marketing will publish the announcement once the release build is ready.",
        ].joined(separator: " ")

        let expected = [
            "Yes. OK. We reviewed the roadmap and captured all launch blockers. The design team confirmed the new sidebar and toolbar direction. Engineering agreed to finish the migration before the beta cutoff. Support prepared the updated macros for customer rollout questions.",
            "Marketing will publish the announcement once the release build is ready.",
        ].joined(separator: "\n\n")

        XCTAssertEqual(SmartParagraphFormatter.format(dictatedText: text), expected)
    }

    func testFormat_BreaksAfterWordThresholdAtSentenceBoundary() {
        let text = [
            "Alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima.",
            "Mike november oscar papa quebec romeo sierra tango uniform victor whiskey xray.",
            "Yankee zulu alpha bravo charlie delta echo foxtrot golf hotel india juliet.",
            "Kilo lima mike november oscar papa quebec romeo sierra tango uniform victor.",
            "Whiskey xray yankee zulu alpha bravo charlie delta echo foxtrot golf hotel.",
        ].joined(separator: " ")

        let expected = [
            "Alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima. Mike november oscar papa quebec romeo sierra tango uniform victor whiskey xray. Yankee zulu alpha bravo charlie delta echo foxtrot golf hotel india juliet. Kilo lima mike november oscar papa quebec romeo sierra tango uniform victor.",
            "Whiskey xray yankee zulu alpha bravo charlie delta echo foxtrot golf hotel.",
        ].joined(separator: "\n\n")

        XCTAssertEqual(SmartParagraphFormatter.format(dictatedText: text), expected)
    }

    func testFormat_PreservesStructuredText() {
        let text = "- First item\n- Second item\n- Third item"

        XCTAssertEqual(SmartParagraphFormatter.format(dictatedText: text), text)
    }
}
