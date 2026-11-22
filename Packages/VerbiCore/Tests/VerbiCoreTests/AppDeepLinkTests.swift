import VerbiCore
import XCTest

final class AppDeepLinkTests: XCTestCase {
    private var scheme: String {
        AppDeepLink.scheme
    }

    private var otherBuildScheme: String {
        scheme == "verbi" ? "verbi-dev" : "verbi"
    }

    private func parse(_ raw: String) throws -> AppDeepLink? {
        try AppDeepLink(url: XCTUnwrap(URL(string: raw)))
    }

    func testParse_WithHostStyleURL_ReturnsAction() throws {
        XCTAssertEqual(try parse("\(scheme)://dictation"), .dictation)
        XCTAssertEqual(try parse("\(scheme)://meeting"), .meeting)
        XCTAssertEqual(try parse("\(scheme)://assistant"), .assistant)
        XCTAssertEqual(try parse("\(scheme)://history"), .history)
        XCTAssertEqual(try parse("\(scheme)://settings"), .settings)
    }

    func testParse_WithPathStyleURL_ReturnsAction() throws {
        XCTAssertEqual(try parse("\(scheme):///dictation"), .dictation)
        XCTAssertEqual(try parse("\(scheme):///settings/"), .settings)
    }

    func testParse_IsCaseInsensitiveForSchemeAndAction() throws {
        XCTAssertEqual(try parse("\(scheme.capitalized)://Dictation"), .dictation)
        XCTAssertEqual(try parse("\(scheme.uppercased()):///HISTORY"), .history)
    }

    func testParse_WithUnknownActionOrScheme_ReturnsNil() throws {
        XCTAssertNil(try parse("\(scheme)://unknown"))
        XCTAssertNil(try parse("https://dictation"))
        XCTAssertNil(try parse("raycast://dictation"))
        XCTAssertNil(
            try parse("\(otherBuildScheme)://dictation"),
            "A build must ignore the other build configuration's scheme"
        )
    }

    func testURL_RoundTripsThroughParser() throws {
        for link in AppDeepLink.allCases {
            XCTAssertEqual(try parse("\(scheme)://\(link.rawValue)"), link)
        }
    }
}
