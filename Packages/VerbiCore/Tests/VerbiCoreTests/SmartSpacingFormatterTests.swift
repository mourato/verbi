@testable import VerbiCore
import XCTest

final class SmartSpacingFormatterTests: XCTestCase {
    func testFormat_AddsLeadingSpaceWhenPreviousCharacterIsLetter() {
        let result = SmartSpacingFormatter.format(
            dictatedText: "friend",
            cursorContext: CursorTextContext(
                previousCharacter: "o",
                nextCharacter: nil,
                isEmptyDocument: false,
                support: .supported,
            ),
        )

        XCTAssertEqual(result, " friend")
    }

    func testFormat_AddsTrailingSpaceWhenNextCharacterIsLetter() {
        let result = SmartSpacingFormatter.format(
            dictatedText: "Hi there",
            cursorContext: CursorTextContext(
                previousCharacter: nil,
                nextCharacter: "H",
                isEmptyDocument: false,
                support: .supported,
            ),
        )

        XCTAssertEqual(result, "Hi there ")
    }

    func testFormat_LowercasesAndAddsLeadingSpaceMidSentence() {
        let result = SmartSpacingFormatter.format(
            dictatedText: "Store today",
            cursorContext: CursorTextContext(
                previousCharacter: "e",
                nextCharacter: nil,
                isEmptyDocument: false,
                support: .supported,
            ),
        )

        XCTAssertEqual(result, " store today")
    }

    func testFormat_DoesNotLowercaseAfterSentenceTerminator() {
        let result = SmartSpacingFormatter.format(
            dictatedText: "Store today",
            cursorContext: CursorTextContext(
                previousCharacter: ".",
                nextCharacter: nil,
                isEmptyDocument: false,
                support: .supported,
            ),
        )

        XCTAssertEqual(result, " Store today")
    }

    func testFormat_AddsLeadingSpaceAfterPeriod() {
        let result = SmartSpacingFormatter.format(
            dictatedText: "Store today",
            cursorContext: CursorTextContext(
                previousCharacter: ".",
                nextCharacter: nil,
                isEmptyDocument: false,
                support: .supported,
            ),
        )

        XCTAssertEqual(result, " Store today")
    }

    func testFormat_AddsLeadingSpaceAfterExclamationMark() {
        let result = SmartSpacingFormatter.format(
            dictatedText: "Store today",
            cursorContext: CursorTextContext(
                previousCharacter: "!",
                nextCharacter: nil,
                isEmptyDocument: false,
                support: .supported,
            ),
        )

        XCTAssertEqual(result, " Store today")
    }

    func testFormat_AddsLeadingSpaceAfterQuestionMark() {
        let result = SmartSpacingFormatter.format(
            dictatedText: "Store today",
            cursorContext: CursorTextContext(
                previousCharacter: "?",
                nextCharacter: nil,
                isEmptyDocument: false,
                support: .supported,
            ),
        )

        XCTAssertEqual(result, " Store today")
    }

    func testFormat_DoesNotDuplicateLeadingSpaceAfterSentenceTerminator() {
        let result = SmartSpacingFormatter.format(
            dictatedText: " Store today",
            cursorContext: CursorTextContext(
                previousCharacter: ".",
                nextCharacter: nil,
                isEmptyDocument: false,
                support: .supported,
            ),
        )

        XCTAssertEqual(result, " Store today")
    }

    func testFormat_DoesNotChangeEmptyDocument() {
        let result = SmartSpacingFormatter.format(
            dictatedText: "Hello",
            cursorContext: CursorTextContext(
                previousCharacter: nil,
                nextCharacter: nil,
                isEmptyDocument: true,
                support: .supported,
            ),
        )

        XCTAssertEqual(result, "Hello")
    }

    func testFormat_AppendsTrailingSpaceWhenPermissionDenied() {
        let result = SmartSpacingFormatter.format(
            dictatedText: "Hello",
            cursorContext: CursorTextContext(
                previousCharacter: nil,
                nextCharacter: nil,
                isEmptyDocument: false,
                support: .permissionDenied,
            ),
        )

        XCTAssertEqual(result, "Hello ")
    }

    func testFormat_DoesNotChangeUnsupportedContext() {
        let result = SmartSpacingFormatter.format(
            dictatedText: "Hello",
            cursorContext: CursorTextContext(
                previousCharacter: nil,
                nextCharacter: nil,
                isEmptyDocument: false,
                support: .unsupported,
            ),
        )

        XCTAssertEqual(result, "Hello")
    }
}
