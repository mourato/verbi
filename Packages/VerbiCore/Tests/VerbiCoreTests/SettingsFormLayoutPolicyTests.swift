@testable import VerbiCore
import XCTest

final class SettingsFormLayoutPolicyTests: XCTestCase {
    func testNarrowWidthUsesAvailableWidthMinusOuterGutters() {
        XCTAssertEqual(SettingsFormLayoutPolicy.contentWidth(availableWidth: 600), 560)
    }

    func testStandardWidthUsesAvailableWidthMinusOuterGutters() {
        XCTAssertEqual(SettingsFormLayoutPolicy.contentWidth(availableWidth: 900), 860)
    }

    func testWideWidthUsesAvailableWidthMinusOuterGuttersWithoutMaximum() {
        XCTAssertEqual(SettingsFormLayoutPolicy.contentWidth(availableWidth: 1_200), 1_160)
    }

    func testDeclaredOuterGutterIsAppliedOnBothSides() {
        XCTAssertEqual(
            SettingsFormLayoutPolicy.contentWidth(availableWidth: 900, outerGutter: 32),
            836,
        )
    }

    func testNonPositiveAvailableWidthReturnsZero() {
        XCTAssertEqual(SettingsFormLayoutPolicy.contentWidth(availableWidth: 0), 0)
        XCTAssertEqual(SettingsFormLayoutPolicy.contentWidth(availableWidth: -100), 0)
    }
}
