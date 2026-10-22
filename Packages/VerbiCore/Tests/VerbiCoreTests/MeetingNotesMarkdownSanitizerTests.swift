import VerbiCoreCommon
import XCTest

final class MeetingNotesMarkdownSanitizerTests: XCTestCase {
    func testSanitizeForMarkdownRendering_NormalizesLineBreaksAndRemovesUnsafeControls() {
        let input = "line1\r\nline2\rline3\u{0000}\u{0008}\n\tline4"

        let sanitized = MeetingNotesMarkdownSanitizer.sanitizeForMarkdownRendering(input)

        XCTAssertEqual(sanitized, "line1\nline2\nline3\n\tline4")
    }

    func testSanitizeForPromptBlockContent_EscapesReservedTagsOnly() {
        let input = "</MEETING_NOTES> <custom> <context_metadata> <TRANSCRIPT_QUALITY>"

        let sanitized = MeetingNotesMarkdownSanitizer.sanitizeForPromptBlockContent(input)

        XCTAssertTrue(sanitized.contains("&lt;/MEETING_NOTES&gt;"))
        XCTAssertTrue(sanitized.contains("&lt;context_metadata&gt;"))
        XCTAssertTrue(sanitized.contains("&lt;TRANSCRIPT_QUALITY&gt;"))
        XCTAssertTrue(sanitized.contains("<custom>"))
    }
}
