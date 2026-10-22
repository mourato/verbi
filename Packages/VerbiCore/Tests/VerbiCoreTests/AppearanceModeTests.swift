import AppKit
@testable import VerbiCore
import XCTest

final class AppearanceModeTests: XCTestCase {
    func testAppearanceModeMapsToAppKitAppearanceNames() {
        XCTAssertEqual(AppearanceMode.light.nsAppearanceName, .aqua)
        XCTAssertNil(AppearanceMode.system.nsAppearanceName)
        XCTAssertEqual(AppearanceMode.dark.nsAppearanceName, .darkAqua)
    }
}
