import SwiftUI
@testable import VerbiCore
import XCTest

@MainActor
final class PermissionStatusTests: XCTestCase {

    func testPermissionActionType() {
        // Microphone
        let mic = PermissionInfo(type: .microphone, state: .notDetermined)
        XCTAssertEqual(mic.actionType, .request)

        let micDenied = PermissionInfo(type: .microphone, state: .denied)
        XCTAssertEqual(micDenied.actionType, .openSettings)

        // Accessibility
        let access = PermissionInfo(type: .accessibility, state: .notDetermined)
        XCTAssertEqual(access.actionType, .request)

        let accessDenied = PermissionInfo(type: .accessibility, state: .denied)
        XCTAssertEqual(accessDenied.actionType, .request, "Accessibility denied should still prompt Request action")

        // Granted
        let granted = PermissionInfo(type: .microphone, state: .granted)
        XCTAssertEqual(granted.actionType, .none)
    }

    func testPermissionColors() {
        let granted = PermissionInfo(type: .microphone, state: .granted)
        XCTAssertEqual(granted.statusColor, AppDesignSystem.Colors.success)

        let denied = PermissionInfo(type: .microphone, state: .denied)
        XCTAssertEqual(denied.statusColor, AppDesignSystem.Colors.error)

        let notDetermined = PermissionInfo(type: .microphone, state: .notDetermined)
        XCTAssertEqual(notDetermined.statusColor, AppDesignSystem.Colors.warning)
    }
}
