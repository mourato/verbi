import Foundation
@testable import VerbiCore
import XCTest

@MainActor
final class ContextAwarenessServiceTests: XCTestCase {
    func testIsCaptureBlocked_ReturnsTrueForDefaultSensitiveBundleID() {
        let blocked = ContextAwarenessPrivacy.isCaptureBlocked(
            bundleIdentifier: "com.1password.1password",
            excludedBundleIDs: [],
        )

        XCTAssertTrue(blocked)
    }

    func testIsCaptureBlocked_ReturnsTrueForCustomExcludedBundleID() {
        let blocked = ContextAwarenessPrivacy.isCaptureBlocked(
            bundleIdentifier: "com.example.secureapp",
            excludedBundleIDs: ["com.example.secureapp"],
        )

        XCTAssertTrue(blocked)
    }

    func testIsCaptureBlocked_ReturnsFalseForRegularBundleID() {
        let blocked = ContextAwarenessPrivacy.isCaptureBlocked(
            bundleIdentifier: "com.apple.safari",
            excludedBundleIDs: [],
        )

        XCTAssertFalse(blocked)
    }

    func testRedactSensitiveText_RedactsEmailURLSecretAndLongNumber() {
        let input = """
        Contact me at user@example.com.
        See https://example.com/path.
        Token: sk_abcdefghijklmnopqrstuvwxyz123456.
        Card: 4111 1111 1111 1111.
        """

        let output = ContextAwarenessPrivacy.redactSensitiveText(input)

        XCTAssertEqual(output?.contains("user@example.com"), false)
        XCTAssertEqual(output?.contains("https://example.com/path"), false)
        XCTAssertEqual(output?.contains("sk_abcdefghijklmnopqrstuvwxyz123456"), false)
        XCTAssertEqual(output?.contains("4111 1111 1111 1111"), false)

        XCTAssertEqual(output?.contains("[REDACTED_EMAIL]"), true)
        XCTAssertEqual(output?.contains("[REDACTED_URL]"), true)
        XCTAssertEqual(output?.contains("[REDACTED_SECRET]"), true)
        XCTAssertEqual(output?.contains("[REDACTED_NUMBER]"), true)
    }

    func testMakePostProcessingContextUsesTypedBlocksForEachSource() {
        let service = ContextAwarenessService()
        let context = service.makePostProcessingContext(
            from: ContextAwarenessSnapshot(
                activeAppName: "Safari",
                activeWindowTitle: "OpenAI",
                activeAccessibilityText: "Focused text",
                clipboardText: "Clipboard text",
                activeWindowOCRText: "Visible text",
            ),
        )

        XCTAssertTrue(context?.contains("<ACTIVE_APP>\nSafari\n</ACTIVE_APP>") == true)
        XCTAssertTrue(context?.contains("<WINDOW_TITLE>\nOpenAI\n</WINDOW_TITLE>") == true)
        XCTAssertTrue(context?.contains("<FOCUSED_UI_TEXT>\nFocused text\n</FOCUSED_UI_TEXT>") == true)
        XCTAssertTrue(context?.contains("<CLIPBOARD_CONTEXT>\nClipboard text\n</CLIPBOARD_CONTEXT>") == true)
        XCTAssertTrue(context?.contains("<WINDOW_OCR_CONTEXT>\nVisible text\n</WINDOW_OCR_CONTEXT>") == true)
        XCTAssertFalse(context?.contains("- Clipboard text:") == true)
    }
}
