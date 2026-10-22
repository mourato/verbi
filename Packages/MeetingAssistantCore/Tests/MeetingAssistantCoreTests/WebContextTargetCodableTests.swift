@testable import MeetingAssistantCore
import XCTest

final class WebContextTargetCodableTests: XCTestCase {
    func testDecodingLegacyPayload_UsesBackwardCompatibleDefaults() throws {
        let id = UUID()
        let legacyJSON = """
        {
          "id": "\(id.uuidString)",
          "displayName": "Google Meet",
          "urlPatterns": ["meet.google.com"],
          "browserBundleIdentifiers": ["com.google.Chrome"]
        }
        """

        let decoded = try JSONDecoder().decode(DictationWebContext.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.displayName, "Google Meet")
        XCTAssertEqual(decoded.urlPatterns, ["meet.google.com"])
        XCTAssertEqual(decoded.browserBundleIdentifiers, ["com.google.Chrome"])
        XCTAssertTrue(decoded.forceMarkdownOutput)
        XCTAssertEqual(decoded.outputLanguage, .original)
        XCTAssertFalse(decoded.autoStartMeetingRecording)
        XCTAssertNil(decoded.customPromptInstructions)
    }

    func testDecodingPayloadWithNewFields_PreservesValues() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "displayName": "Zoom",
          "urlPatterns": ["zoom.us/j"],
          "browserBundleIdentifiers": ["com.apple.Safari"],
          "forceMarkdownOutput": false,
          "outputLanguage": "french",
          "autoStartMeetingRecording": true,
          "customPromptInstructions": "Always answer in lowercase."
        }
        """

        let decoded = try JSONDecoder().decode(DictationWebContext.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.displayName, "Zoom")
        XCTAssertEqual(decoded.urlPatterns, ["zoom.us/j"])
        XCTAssertEqual(decoded.browserBundleIdentifiers, ["com.apple.Safari"])
        XCTAssertFalse(decoded.forceMarkdownOutput)
        XCTAssertEqual(decoded.outputLanguage, .french)
        XCTAssertTrue(decoded.autoStartMeetingRecording)
        XCTAssertEqual(decoded.customPromptInstructions, "Always answer in lowercase.")
    }
}
