@testable import MeetingAssistantCore
import XCTest

final class RecordingExclusivityCoordinatorTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await RecordingExclusivityCoordinator.shared.endAssistant()
        await RecordingExclusivityCoordinator.shared.endRecording()
    }

    override func tearDown() async throws {
        await RecordingExclusivityCoordinator.shared.endAssistant()
        await RecordingExclusivityCoordinator.shared.endRecording()
        try await super.tearDown()
    }

    func testBlockingModeRejectsCrossModeActivation() async {
        _ = await RecordingExclusivityCoordinator.shared.beginRecording(mode: .dictation)

        let blockedMeeting = await RecordingExclusivityCoordinator.shared.blockingMode(for: .meeting)
        let blockedAssistant = await RecordingExclusivityCoordinator.shared.blockingMode(for: .assistant)
        let blockedDictation = await RecordingExclusivityCoordinator.shared.blockingMode(for: .dictation)

        XCTAssertEqual(blockedMeeting, .dictation)
        XCTAssertEqual(blockedAssistant, .dictation)
        XCTAssertNil(blockedDictation)
    }

    func testBeginAssistantFailsWhileRecordingModeIsActive() async {
        _ = await RecordingExclusivityCoordinator.shared.beginRecording(mode: .meeting)

        let didBeginAssistant = await RecordingExclusivityCoordinator.shared.beginAssistant()
        let activeMode = await RecordingExclusivityCoordinator.shared.activeModeSnapshot()

        XCTAssertFalse(didBeginAssistant)
        XCTAssertEqual(activeMode, .meeting)
    }

    func testBeginRecordingRejectsAssistantMode() async {
        let didBeginAssistant = await RecordingExclusivityCoordinator.shared.beginRecording(mode: .assistant)
        let activeMode = await RecordingExclusivityCoordinator.shared.activeModeSnapshot()

        XCTAssertFalse(didBeginAssistant)
        XCTAssertNil(activeMode)
    }
}
