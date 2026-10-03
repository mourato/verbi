import AppKit
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreUI
import XCTest

@MainActor
final class FloatingRecordingIndicatorWidthTests: XCTestCase {
    func testFormatRecordingDuration_PreservesDurationDisplay() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        for (seconds, expected) in [(0.0, "00:00"), (65.0, "01:05"), (3661.0, "01:01:01")] {
            XCTAssertEqual(
                RecordingDurationFormatting.formatRecordingDuration(
                    startTime: start,
                    at: start.addingTimeInterval(seconds)
                ),
                expected
            )
        }
        XCTAssertEqual(RecordingDurationFormatting.formatRecordingDuration(startTime: nil, at: start), "00:00")
    }

    func testTimerReservedWidthFitsHourDurationSample() {
        for size in [
            FloatingRecordingIndicatorView.IndicatorSize.mini
        ] {
            let sampleWidth = ceil(
                ("00:00:00" as NSString).size(
                    withAttributes: [.font: FloatingRecordingIndicatorViewUtilities.timerFont(for: size)],
                ).width,
            )

            XCTAssertGreaterThanOrEqual(
                FloatingRecordingIndicatorViewUtilities.timerReservedWidth(for: size),
                sampleWidth,
            )
        }
    }

    func testMeetingTimerDividerWidthContributionMatchesLayoutBudget() {
        let size: FloatingRecordingIndicatorView.IndicatorSize = .mini
        let renderState = RecordingIndicatorRenderState(mode: .recording, kind: .meeting)
        let layoutWithoutTimer = RecordingIndicatorOverlayLayout(
            showsPromptSelector: false,
            showsLanguageSelector: false,
            showsMeetingTimer: false,
        )
        let layoutWithTimer = RecordingIndicatorOverlayLayout(
            showsPromptSelector: false,
            showsLanguageSelector: false,
            showsMeetingTimer: true,
        )

        let widthWithoutTimer = FloatingRecordingIndicatorViewUtilities.mainPillWidth(
            for: size,
            renderState: renderState,
            layout: layoutWithoutTimer,
            expanded: false,
        )
        let widthWithTimer = FloatingRecordingIndicatorViewUtilities.mainPillWidth(
            for: size,
            renderState: renderState,
            layout: layoutWithTimer,
            expanded: false,
        )

        let expectedDelta = FloatingRecordingIndicatorViewUtilities.dividerWidth
            + FloatingRecordingIndicatorViewUtilities.timerReservedWidth(for: size)
            + (FloatingRecordingIndicatorViewUtilities.contentSpacing(for: size) * 2)

        XCTAssertEqual(widthWithTimer - widthWithoutTimer, expectedDelta, accuracy: 0.001)
    }

    func testAutomaticMeetingConfirmationWidthUsesDedicatedBudget() {
        let renderState = RecordingIndicatorRenderState(
            mode: .confirmingAutomaticMeetingStart(
                deadline: Date(timeIntervalSinceReferenceDate: 9),
                duration: 9,
            ),
            kind: .meeting,
        )
        let layout = RecordingIndicatorOverlayLayout(
            showsPromptSelector: false,
            showsLanguageSelector: false,
            showsMeetingTimer: false,
        )

        let width = FloatingRecordingIndicatorViewUtilities.mainPillWidth(
            for: .mini,
            renderState: renderState,
            layout: layout,
            expanded: false,
        )

        XCTAssertEqual(
            width,
            FloatingRecordingIndicatorViewUtilities.confirmationPillWidth(for: .mini),
            accuracy: 0.001,
        )
    }

    func testProcessingClusterWidth_IsIndependentFromRecordingKind() {
        let size: FloatingRecordingIndicatorView.IndicatorSize = .mini
        let processingRenderState = RecordingIndicatorRenderState(mode: .processing, kind: .meeting)
        let dictationProcessingState = RecordingIndicatorRenderState(mode: .processing, kind: .dictation)
        let snapshot = RecordingIndicatorProcessingSnapshot(step: .postProcessing)

        let layout = RecordingIndicatorOverlayLayout(
            showsPromptSelector: false,
            showsLanguageSelector: false,
            showsMeetingTimer: false,
        )

        let processingWidth = FloatingRecordingIndicatorViewUtilities.mainPillWidth(
            for: size,
            renderState: processingRenderState,
            layout: layout,
            expanded: false,
            processingSnapshot: snapshot,
        )
        let baseProcessingWidth = FloatingRecordingIndicatorViewUtilities.mainPillWidth(
            for: size,
            renderState: dictationProcessingState,
            layout: layout,
            expanded: false,
            processingSnapshot: snapshot,
        )

        XCTAssertEqual(processingWidth, baseProcessingWidth, accuracy: 0.001)
    }

    func testProcessingClusterUsesStatusWidthInsteadOfWaveform() {
        let size: FloatingRecordingIndicatorView.IndicatorSize = .mini
        let processingState = RecordingIndicatorRenderState(mode: .processing, kind: .assistant)
        let snapshot = RecordingIndicatorProcessingSnapshot(step: .capturingContext)

        let expectedClusterWidth = AppDesignSystem.Layout.recordingIndicatorDotSize
            + FloatingRecordingIndicatorViewUtilities.processingStatusWidth(for: size, processingSnapshot: snapshot)
            + FloatingRecordingIndicatorViewUtilities.contentSpacing(for: size)

        let actualClusterWidth = FloatingRecordingIndicatorViewUtilities.clusterWidth(
            for: size,
            renderState: processingState,
            processingSnapshot: snapshot,
        )

        XCTAssertEqual(actualClusterWidth, expectedClusterWidth, accuracy: 0.001)
    }

    func testMainContentMode_UsesWaveformDuringRecordingAndStatusDuringProcessing() {
        XCTAssertTrue(
            FloatingRecordingIndicatorViewUtilities.mainContentMode(
                for: RecordingIndicatorRenderState(mode: .recording, kind: .meeting),
            ) == .waveform,
        )
        XCTAssertTrue(
            FloatingRecordingIndicatorViewUtilities.mainContentMode(
                for: RecordingIndicatorRenderState(mode: .starting, kind: .dictation),
            ) == .waveform,
        )
        XCTAssertTrue(
            FloatingRecordingIndicatorViewUtilities.mainContentMode(
                for: RecordingIndicatorRenderState(mode: .processing, kind: .meeting),
            ) == .processingStatus,
        )
    }

    func testProcessingWidthGrowsAndShrinksWithTextWithinBounds() {
        let size: FloatingRecordingIndicatorView.IndicatorSize = .mini
        let shortSnapshot = RecordingIndicatorProcessingSnapshot(step: .postProcessing)
        let longSnapshot = RecordingIndicatorProcessingSnapshot(step: .detectingMeetingType)

        let shortWidth = FloatingRecordingIndicatorViewUtilities.processingStatusWidth(
            for: size,
            processingSnapshot: shortSnapshot,
        )
        let longWidth = FloatingRecordingIndicatorViewUtilities.processingStatusWidth(
            for: size,
            processingSnapshot: longSnapshot,
        )
        let maxWidth = FloatingRecordingIndicatorViewUtilities.processingStatusMaxWidth(for: size)

        // Localized strings can both saturate at max width; allow equality only in that clamp case.
        if shortWidth == maxWidth, longWidth == maxWidth {
            XCTAssertEqual(longWidth, shortWidth, accuracy: 0.001)
        } else {
            XCTAssertGreaterThan(longWidth, shortWidth)
        }
        XCTAssertGreaterThanOrEqual(shortWidth, FloatingRecordingIndicatorViewUtilities.processingStatusMinWidth(for: size))
        XCTAssertLessThanOrEqual(longWidth, FloatingRecordingIndicatorViewUtilities.processingStatusMaxWidth(for: size))
    }

    func testPanelWidthForProcessingUsesSnapshotDrivenTextWidth() {
        let settings = AppSettingsStore.shared
        let controller = FloatingRecordingIndicatorController(settingsStore: settings)
        let renderState = RecordingIndicatorRenderState(mode: .processing, kind: .meeting)
        let shortSnapshot = RecordingIndicatorProcessingSnapshot(step: .postProcessing)
        let longSnapshot = RecordingIndicatorProcessingSnapshot(step: .detectingMeetingType)

        let shortWidth = controller.panelWidthForTesting(
            renderState: renderState,
            processingSnapshot: shortSnapshot,
        )
        let longWidth = controller.panelWidthForTesting(
            renderState: renderState,
            processingSnapshot: longSnapshot,
        )
        let shortStatusWidth = FloatingRecordingIndicatorViewUtilities.processingStatusWidth(
            for: .mini,
            processingSnapshot: shortSnapshot,
        )
        let longStatusWidth = FloatingRecordingIndicatorViewUtilities.processingStatusWidth(
            for: .mini,
            processingSnapshot: longSnapshot,
        )

        if shortStatusWidth == longStatusWidth {
            XCTAssertEqual(longWidth, shortWidth, accuracy: 0.001)
        } else {
            XCTAssertGreaterThan(longWidth, shortWidth)
        }
    }
}
