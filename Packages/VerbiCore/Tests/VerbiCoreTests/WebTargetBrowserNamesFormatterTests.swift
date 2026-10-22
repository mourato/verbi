@testable import VerbiCoreUI
import XCTest

final class WebTargetBrowserNamesFormatterTests: XCTestCase {
    func testFormattedNames_UsesFallbackWhenPrimaryListIsEmpty() {
        let result = WebTargetBrowserNamesFormatter.formattedNames(
            bundleIdentifiers: [],
            fallbackBundleIdentifiers: ["com.google.Chrome"],
            localizedListKey: "settings.markdown_targets.websites.browsers",
        )

        XCTAssertTrue(result.contains("Google Chrome"))
    }

    func testFormattedNames_SortsDisplayNamesAlphabetically() {
        let result = WebTargetBrowserNamesFormatter.formattedNames(
            bundleIdentifiers: ["com.apple.Safari", "com.google.Chrome"],
            fallbackBundleIdentifiers: [],
            localizedListKey: "settings.markdown_targets.websites.browsers",
        )

        let chromeRange = result.range(of: "Google Chrome")
        let safariRange = result.range(of: "Safari")

        XCTAssertNotNil(chromeRange)
        XCTAssertNotNil(safariRange)

        if let chromeRange, let safariRange {
            XCTAssertLessThan(chromeRange.lowerBound, safariRange.lowerBound)
        }
    }

    func testFormattedNames_ReturnsEmptyMessageWhenBothListsAreEmpty() {
        let result = WebTargetBrowserNamesFormatter.formattedNames(
            bundleIdentifiers: [],
            fallbackBundleIdentifiers: [],
            localizedListKey: "settings.markdown_targets.websites.browsers",
        )

        XCTAssertEqual(result, "settings.web_targets.browsers.empty".localized)
    }
}
