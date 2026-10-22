@testable import VerbiCore
import XCTest

final class DoubleEscapePressDetectorTests: XCTestCase {
    func testSecondPressWithinWindowConfirmsDoublePress() {
        var detector = DoubleEscapePressDetector(interval: 1.0)
        let start = Date(timeIntervalSince1970: 100)

        XCTAssertFalse(detector.registerPress(at: start, token: "assistant"))
        XCTAssertTrue(detector.registerPress(at: start.addingTimeInterval(0.4), token: "assistant"))
    }

    func testSecondPressOutsideWindowStartsNewSequence() {
        var detector = DoubleEscapePressDetector(interval: 0.2)
        let start = Date(timeIntervalSince1970: 200)

        XCTAssertFalse(detector.registerPress(at: start, token: "dictation"))
        XCTAssertFalse(detector.registerPress(at: start.addingTimeInterval(0.5), token: "dictation"))
        XCTAssertTrue(detector.registerPress(at: start.addingTimeInterval(0.6), token: "dictation"))
    }

    func testTokenChangeDoesNotConfirmDoublePress() {
        var detector = DoubleEscapePressDetector(interval: 1.0)
        let start = Date(timeIntervalSince1970: 300)

        XCTAssertFalse(detector.registerPress(at: start, token: "assistant"))
        XCTAssertFalse(detector.registerPress(at: start.addingTimeInterval(0.3), token: "dictation"))
        XCTAssertTrue(detector.registerPress(at: start.addingTimeInterval(0.5), token: "dictation"))
    }

    func testResetClearsPendingState() {
        var detector = DoubleEscapePressDetector(interval: 1.0)
        let start = Date(timeIntervalSince1970: 400)

        XCTAssertFalse(detector.registerPress(at: start, token: "assistant"))
        detector.reset()
        XCTAssertFalse(detector.registerPress(at: start.addingTimeInterval(0.1), token: "assistant"))
    }
}
