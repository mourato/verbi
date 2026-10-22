@testable import VerbiCore
import XCTest

final class InputSanitizationTests: XCTestCase {
    func testSanitizeFilename() {
        XCTAssertEqual(InputSanitizer.sanitizeFilename("test..doc"), "test__doc")
        XCTAssertEqual(InputSanitizer.sanitizeFilename("my/cool/file.txt"), "my_cool_file_txt")
        XCTAssertEqual(InputSanitizer.sanitizeFilename("   space   "), "space")
        XCTAssertEqual(InputSanitizer.sanitizeFilename("../../../etc/passwd"), "_________etc_passwd")
    }

    func testValidatePathComponent() {
        XCTAssertNoThrow(try InputSanitizer.validatePathComponent("safe_file"))
        XCTAssertThrowsError(try InputSanitizer.validatePathComponent("..")) { error in
            XCTAssertTrue(error.localizedDescription.contains("Unsafe path component"))
        }
        XCTAssertThrowsError(try InputSanitizer.validatePathComponent("path/traversal"))
    }
}
