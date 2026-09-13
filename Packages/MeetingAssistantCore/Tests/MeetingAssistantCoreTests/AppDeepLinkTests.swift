import MeetingAssistantCore
import XCTest

final class AppDeepLinkTests: XCTestCase {
    func testParse_WithHostStyleURL_ReturnsAction() {
        XCTAssertEqual(AppDeepLink(url: URL(string: "verbi://dictation")!), .dictation)
        XCTAssertEqual(AppDeepLink(url: URL(string: "verbi://meeting")!), .meeting)
        XCTAssertEqual(AppDeepLink(url: URL(string: "verbi://assistant")!), .assistant)
        XCTAssertEqual(AppDeepLink(url: URL(string: "verbi://history")!), .history)
        XCTAssertEqual(AppDeepLink(url: URL(string: "verbi://settings")!), .settings)
    }

    func testParse_WithPathStyleURL_ReturnsAction() {
        XCTAssertEqual(AppDeepLink(url: URL(string: "verbi:///dictation")!), .dictation)
        XCTAssertEqual(AppDeepLink(url: URL(string: "verbi:///settings/")!), .settings)
    }

    func testParse_IsCaseInsensitiveForSchemeAndAction() {
        XCTAssertEqual(AppDeepLink(url: URL(string: "Verbi://Dictation")!), .dictation)
        XCTAssertEqual(AppDeepLink(url: URL(string: "VERBI:///HISTORY")!), .history)
    }

    func testParse_WithUnknownActionOrScheme_ReturnsNil() {
        XCTAssertNil(AppDeepLink(url: URL(string: "verbi://unknown")!))
        XCTAssertNil(AppDeepLink(url: URL(string: "https://dictation")!))
        XCTAssertNil(AppDeepLink(url: URL(string: "raycast://dictation")!))
    }

    func testURL_RoundTripsThroughParser() {
        for link in AppDeepLink.allCases {
            XCTAssertEqual(AppDeepLink(url: link.url), link)
        }
    }
}
