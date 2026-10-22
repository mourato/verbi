@testable import VerbiCore
import XCTest

final class BrowserProviderRegistryTests: XCTestCase {
    func testDefaultProviders_IncludeKnownBrowsersAndExcludeFirefox() {
        let providers = BrowserProviderRegistry.defaultProviders()

        XCTAssertNotNil(providers["com.apple.safari"])
        XCTAssertNotNil(providers["com.google.chrome"])
        XCTAssertNotNil(providers["com.microsoft.edgemac"])
        XCTAssertNil(providers["org.mozilla.firefox"])
    }

    func testIsLikelyBrowserBundleIdentifier_DetectsChromiumAndFirefox() {
        XCTAssertTrue(BrowserProviderRegistry.isLikelyBrowserBundleIdentifier("com.example.superchromium"))
        XCTAssertTrue(BrowserProviderRegistry.isLikelyBrowserBundleIdentifier("org.mozilla.firefox"))
        XCTAssertFalse(BrowserProviderRegistry.isLikelyBrowserBundleIdentifier("com.microsoft.VSCode"))
    }

    func testProvider_ForFirefoxBundleIdentifier_ReturnsNil() {
        let provider = BrowserProviderRegistry.provider(for: "org.mozilla.firefox")

        XCTAssertNil(provider)
    }
}
