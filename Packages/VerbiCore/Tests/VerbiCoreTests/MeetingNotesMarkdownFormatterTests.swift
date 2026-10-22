import AppKit
@testable import VerbiCoreUI
import XCTest

final class MeetingNotesMarkdownFormatterTests: XCTestCase {
    func testAttributedStringForEditing_RoundTripsHeadingListAndLink() {
        let formatter = MeetingNotesMarkdownFormatter()
        let markdown = """
        # Project Update

        - First item
        - Second item

        [OpenAI](https://openai.com)
        """

        let attributed = formatter.attributedStringForEditing(from: markdown)
        let roundTripped = formatter.markdownForPersistence(from: attributed)
        let fullRange = NSRange(location: 0, length: attributed.length)
        var hasLink = false
        attributed.enumerateAttribute(.link, in: fullRange, options: []) { value, _, stop in
            if value != nil {
                hasLink = true
                stop.pointee = true
            }
        }

        XCTAssertTrue(hasLink)
        XCTAssertTrue(roundTripped.contains("Project Update"))
        XCTAssertTrue(roundTripped.contains("First item"))
        XCTAssertTrue(roundTripped.contains("OpenAI"))
    }

    func testAttributedStringForEditing_FallsBackToPlainTextWhenParserFails() {
        enum ParserError: Error {
            case forcedFailure
        }

        let formatter = MeetingNotesMarkdownFormatter(
            parser: { _, _ in
                throw ParserError.forcedFailure
            },
        )
        let markdown = "# Keep this as plain text"

        let attributed = formatter.attributedStringForEditing(from: markdown)

        XCTAssertEqual(attributed.string, markdown)
    }

    func testMarkdownForPersistence_ConvertsEditorMarkersAndHeadingLevels() {
        let formatter = MeetingNotesMarkdownFormatter()
        let text = "☐ Open\n☑ Done\n• Bullet\n3. Ordered\nHeading Six"
        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 16), range: fullRange)

        let headingRange = (text as NSString).range(of: "Heading Six")
        attributed.addAttribute(.meetingNotesHeadingLevel, value: 6, range: headingRange)
        attributed.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 18), range: headingRange)

        let markdown = formatter.markdownForPersistence(from: attributed)

        XCTAssertTrue(markdown.contains("- [ ] Open"))
        XCTAssertTrue(markdown.contains("- [x] Done"))
        XCTAssertTrue(markdown.contains("- Bullet"))
        XCTAssertTrue(markdown.contains("3. Ordered"))
        XCTAssertTrue(markdown.contains("######"))
        XCTAssertTrue(markdown.contains("Heading Six"))
    }
}
