import Foundation
@testable import VerbiCore
import XCTest

final class ShortcutHoldOrToggleTests: XCTestCase {
    private let holdThreshold: TimeInterval = 0.5

    @MainActor
    func testHoldOrToggleShortPressStartsOnly() {
        let engine = ShortcutExecutionEngine(holdThreshold: holdThreshold)
        let pressStart = Date()

        let downActions = engine.handleHoldOrToggleDown(isRecording: false, referenceDate: pressStart)
        let upActions = engine.handleHoldOrToggleUp(
            referenceDate: pressStart.addingTimeInterval(holdThreshold - 0.1),
        )

        XCTAssertEqual(downActions, [.start])
        XCTAssertEqual(upActions, [])
    }

    @MainActor
    func testHoldOrToggleLongPressStartsThenStopsOnUp() {
        let engine = ShortcutExecutionEngine(holdThreshold: holdThreshold)
        let pressStart = Date()

        let downActions = engine.handleHoldOrToggleDown(isRecording: false, referenceDate: pressStart)
        let upActions = engine.handleHoldOrToggleUp(
            referenceDate: pressStart.addingTimeInterval(holdThreshold),
        )

        XCTAssertEqual(downActions, [.start])
        XCTAssertEqual(upActions, [.stop])
    }

    @MainActor
    func testHoldOrToggleDownWhileRecordingStopsWithoutRestartOnUp() {
        let engine = ShortcutExecutionEngine(holdThreshold: holdThreshold)
        let pressStart = Date()

        let downActions = engine.handleHoldOrToggleDown(isRecording: true, referenceDate: pressStart)
        let upActions = engine.handleHoldOrToggleUp(
            referenceDate: pressStart.addingTimeInterval(holdThreshold + 1),
        )

        XCTAssertEqual(downActions, [.stop])
        XCTAssertEqual(upActions, [])
    }

    @MainActor
    func testHoldOrToggleResetClearsStrandedPressState() {
        let engine = ShortcutExecutionEngine(holdThreshold: holdThreshold)
        let pressStart = Date()

        _ = engine.handleHoldOrToggleDown(isRecording: false, referenceDate: pressStart)
        engine.reset()

        let upActions = engine.handleHoldOrToggleUp(
            referenceDate: pressStart.addingTimeInterval(holdThreshold + 1),
        )

        XCTAssertEqual(upActions, [])
    }
}
