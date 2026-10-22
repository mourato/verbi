@testable import VerbiCore
import XCTest

@MainActor
final class PermissionViewModelTests: XCTestCase {
    private var manager: PermissionStatusManager!

    override func setUp() async throws {
        manager = PermissionStatusManager()
    }

    override func tearDown() async throws {
        manager = nil
    }

    func testReflectsPermissionManagerUpdates() async {
        let viewModel = makeViewModel()

        manager.updateMicrophoneState(.granted)
        manager.updateScreenRecordingState(.denied)
        manager.updateAccessibilityState(.restricted)
        await Task.yield()

        XCTAssertEqual(viewModel.microphoneState, .granted)
        XCTAssertEqual(viewModel.screenState, .denied)
        XCTAssertEqual(viewModel.accessibilityState, .restricted)
        XCTAssertFalse(viewModel.allPermissionsGranted)
    }

    func testStartPeriodicRefreshTriggersImmediateRefresh() {
        let viewModel = makeViewModel()
        let expectation = expectation(description: "refreshAction invoked immediately")
        var refreshCount = 0

        viewModel.startPeriodicRefresh {
            refreshCount += 1
            if refreshCount == 1 {
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 0.3)
        viewModel.stopPeriodicRefresh()
        XCTAssertGreaterThanOrEqual(refreshCount, 1)
    }

    private func makeViewModel() -> PermissionViewModel {
        PermissionViewModel(
            manager: manager,
            requestMicrophone: {},
            requestScreen: {},
            openMicrophoneSettings: {},
            openScreenSettings: {},
            requestAccessibility: {},
            openAccessibilitySettings: {},
        )
    }
}
