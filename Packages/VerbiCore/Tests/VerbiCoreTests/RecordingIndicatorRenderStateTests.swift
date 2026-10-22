@testable import VerbiCore
import XCTest

final class RecordingIndicatorRenderStateTests: XCTestCase {
    func testProcessingSnapshotUsesStepLocalizationKeys() {
        let snapshot = RecordingIndicatorProcessingSnapshot(
            step: .capturingContext,
            progressPercent: 37,
        )

        XCTAssertEqual(snapshot.step.localizedTitleKey, "recording_indicator.processing.step.capturing_context")
        XCTAssertEqual(snapshot.progressPercent, 37)
    }

    func testFromLegacy_WithoutMeetingType_CreatesDictationKind() {
        let state = RecordingIndicatorRenderState.fromLegacy(mode: .recording, meetingType: nil)

        XCTAssertEqual(state.mode, .recording)
        XCTAssertEqual(state.kind, .dictation)
        XCTAssertNil(state.meetingType)
    }

    func testFromLegacy_WithMeetingType_CreatesMeetingKind() {
        let state = RecordingIndicatorRenderState.fromLegacy(mode: .processing, meetingType: .standup)

        XCTAssertEqual(state.mode, .processing)
        XCTAssertEqual(state.kind, .meeting)
        XCTAssertEqual(state.meetingType, .standup)
    }

    func testWithMode_PreservesKindAndMeetingType() {
        let initial = RecordingIndicatorRenderState(mode: .starting, kind: .meeting, meetingType: .planning)

        let updated = initial.with(mode: .recording)

        XCTAssertEqual(updated.mode, .recording)
        XCTAssertEqual(updated.kind, .meeting)
        XCTAssertEqual(updated.meetingType, .planning)
    }

    func testWithMode_PreservesAssistantKind() {
        let initial = RecordingIndicatorRenderState(mode: .starting, kind: .assistant)

        let updated = initial.with(mode: .processing)

        XCTAssertEqual(updated.mode, .processing)
        XCTAssertEqual(updated.kind, .assistant)
        XCTAssertNil(updated.assistantIntegrationID)
    }

    func testWithMode_PreservesAssistantIntegrationIdentifier() {
        let integrationID = UUID()
        let initial = RecordingIndicatorRenderState(
            mode: .recording,
            kind: .assistantIntegration,
            assistantIntegrationID: integrationID,
        )

        let updated = initial.with(mode: .processing)

        XCTAssertEqual(updated.mode, .processing)
        XCTAssertEqual(updated.kind, .assistantIntegration)
        XCTAssertEqual(updated.assistantIntegrationID, integrationID)
    }

    func testForRecordingSource_MicrophoneAlwaysCreatesDictationKind() {
        let state = RecordingIndicatorRenderState.forRecordingSource(
            mode: .recording,
            recordingSource: .microphone,
            meetingType: .standup,
        )

        XCTAssertEqual(state.kind, .dictation)
        XCTAssertNil(state.meetingType)
    }

    func testForRecordingSource_AllCreatesMeetingKind() {
        let state = RecordingIndicatorRenderState.forRecordingSource(
            mode: .processing,
            recordingSource: .all,
            meetingType: .planning,
        )

        XCTAssertEqual(state.kind, .meeting)
        XCTAssertEqual(state.meetingType, .planning)
    }

    @MainActor
    func testProcessingStateStoreResetClearsCurrentSnapshot() {
        let store = RecordingIndicatorProcessingStateStore()
        let snapshot = RecordingIndicatorProcessingSnapshot(step: .interpretingCommand)

        store.update(snapshot: snapshot)
        XCTAssertEqual(store.currentSnapshot, snapshot)

        store.reset()
        XCTAssertNil(store.currentSnapshot)
    }
}
