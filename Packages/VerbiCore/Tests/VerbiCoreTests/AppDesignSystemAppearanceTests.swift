import AppKit
@testable import VerbiCoreUI
import XCTest

final class AppDesignSystemAppearanceTests: XCTestCase {
    func testIsDarkAppearanceRecognizesAquaVariants() throws {
        XCTAssertFalse(try AppDesignSystem.Colors.isDarkAppearance(XCTUnwrap(NSAppearance(named: .aqua))))
        XCTAssertTrue(try AppDesignSystem.Colors.isDarkAppearance(XCTUnwrap(NSAppearance(named: .darkAqua))))
    }

    func testResolveColorRunsProviderInsideRequestedAppearance() throws {
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))

        let darkResolved = AppDesignSystem.Colors.resolveColor(in: darkAppearance) {
            AppDesignSystem.Colors.isDarkAppearance(NSAppearance.currentDrawing())
                ? NSColor.black
                : NSColor.white
        }

        let lightResolved = AppDesignSystem.Colors.resolveColor(in: lightAppearance) {
            AppDesignSystem.Colors.isDarkAppearance(NSAppearance.currentDrawing())
                ? NSColor.black
                : NSColor.white
        }

        XCTAssertEqual(darkResolved, NSColor.black)
        XCTAssertEqual(lightResolved, NSColor.white)
    }
}
