import Foundation
@testable import VerbiCoreUI
import XCTest

final class MeetingNotesEditorThemeResolverTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testAvailableThemeNamesIgnoresNonCSSFiles() throws {
        let themesDirectory = MeetingNotesEditorThemeResolver.themesDirectory(appSupportRoot: tempDirectory)
        try FileManager.default.createDirectory(at: themesDirectory, withIntermediateDirectories: true)
        try "# body {}".write(to: themesDirectory.appendingPathComponent("dark.css"), atomically: true, encoding: .utf8)
        try "nope".write(to: themesDirectory.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)

        let names = MeetingNotesEditorThemeResolver.availableThemeNames(appSupportRoot: tempDirectory)

        XCTAssertEqual(names, ["dark"])
    }

    func testCSSForThemeNameLoadsMatchingFile() throws {
        let themesDirectory = MeetingNotesEditorThemeResolver.themesDirectory(appSupportRoot: tempDirectory)
        try FileManager.default.createDirectory(at: themesDirectory, withIntermediateDirectories: true)
        let css = ":root { --accent: hotpink; }"
        try css.write(to: themesDirectory.appendingPathComponent("accent.css"), atomically: true, encoding: .utf8)

        let resolved = MeetingNotesEditorThemeResolver.css(forThemeName: "accent", appSupportRoot: tempDirectory)

        XCTAssertEqual(resolved, css)
    }

    func testCSSForEmptyThemeNameReturnsEmptyString() {
        XCTAssertEqual(
            MeetingNotesEditorThemeResolver.css(forThemeName: "", appSupportRoot: tempDirectory),
            "",
        )
    }
}
