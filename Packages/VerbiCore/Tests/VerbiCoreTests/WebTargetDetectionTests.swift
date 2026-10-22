import Foundation
import VerbiCoreDomain
@testable import VerbiCoreInfrastructure
import XCTest

final class WebTargetDetectionTests: XCTestCase {
    private let googleMeetTarget = WebMeetingTarget(
        app: .googleMeet,
        displayName: "Google Meet",
        urlPatterns: ["meet.google.com"],
        browserBundleIdentifiers: ["com.google.Chrome"],
    )

    func testMatchesGoogleMeetHostAndPath() throws {
        let url = try XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij"))

        XCTAssertTrue(WebTargetDetection.urlMatchesPattern(for: url, pattern: "meet.google.com"))
        XCTAssertNotNil(
            WebTargetDetection.matchTarget(
                for: url,
                bundleIdentifier: "com.google.Chrome",
                targets: [googleMeetTarget],
            ),
        )
    }

    func testDoesNotMatchWikipediaPageNamedGoogleMeet() throws {
        let url = try XCTUnwrap(URL(string: "https://pt.wikipedia.org/wiki/Google_Meet"))

        XCTAssertFalse(WebTargetDetection.urlMatchesPattern(for: url, pattern: "meet.google.com"))
        XCTAssertNil(
            WebTargetDetection.matchTarget(
                for: url,
                bundleIdentifier: "com.google.Chrome",
                targets: [googleMeetTarget],
            ),
        )
    }

    func testDoesNotMatchLookalikeHost() throws {
        let url = try XCTUnwrap(URL(string: "https://notmeet.google.com/room"))

        XCTAssertFalse(WebTargetDetection.urlMatchesPattern(for: url, pattern: "meet.google.com"))
    }
}
