import AppKit
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

// MARK: - Floating Indicator Rendering

extension FloatingRecordingIndicatorView {
    var leadingControls: some View {
        HStack(spacing: controlSpacing(for: currentIndicatorSize)) {
            ActionIconButton(
                symbol: "trash",
                helpKey: "recording_indicator.cancel.help",
                keyboardShortcut: .escape
            ) {
                onCancel()
            }

            divider
        }
    }

    /// Warning overlay shown when microphone input appears silent.
    var silenceWarningOverlay: some View {
        RecordingSilenceWarningOverlay(
            isDialogPresented: $isSilenceWarningDialogPresented,
            onContinue: { audioMonitor.dismissSilenceWarning() },
            onStop: {
                onStop()
                audioMonitor.dismissSilenceWarning()
            },
            onDiscard: {
                onCancel()
                audioMonitor.dismissSilenceWarning()
            }
        )
    }

    func postProcessingReadinessWarningOverlay(
        _ descriptor: RecordingPostProcessingWarningDescriptor
    ) -> some View {
        RecordingPostProcessingWarningOverlay(descriptor: descriptor) { section in
            navigationService.openSettings(section: section)
        }
    }

    var divider: some View {
        Rectangle()
            .fill(AppDesignSystem.Colors.overlayDivider)
            .frame(width: 1, height: 20)
    }

    var trailingControl: some View {
        HStack(spacing: controlSpacing(for: currentIndicatorSize)) {
            divider

            ActionIconButton(
                symbol: "arrow.up",
                helpKey: "recording_indicator.stop.help",
                keyboardShortcut: nil,
                style: .success
            ) {
                onStop()
            }
        }
    }

    /// Dot indicating recording or processing (Figma uses 12x12).
    func statusDot(for _: IndicatorSize) -> some View {
        Circle()
            .fill(isRecordingMode ? AppDesignSystem.Colors.recording : AppDesignSystem.Colors.accent)
            .frame(width: AppDesignSystem.Layout.recordingIndicatorDotSize, height: AppDesignSystem.Layout.recordingIndicatorDotSize)
            .modifier(
                PulsingModifier(
                    isActive: isAnimationActive && (isRecordingMode || isStartingMode),
                    speed: isRecordingMode ? 0.9 : 1.2
                )
            )
    }

    var warningOverlayTransition: AnyTransition {
        AppleMotion.transition(reduceMotion: reduceMotion, edge: .top)
    }

    func resetHoverState() {
        hoverCollapseTask?.cancel()
        hoverCollapseTask = nil
        isMainRegionHovered = false
        isPromptRegionHovered = false
        isPromptSessionArmed = false
        isKeyboardFocused = false
        resetAccessibilityControls()
    }

    var isRecordingMode: Bool {
        if case .recording = renderState.mode {
            return true
        }
        return false
    }

    var isStartingMode: Bool {
        if case .starting = renderState.mode {
            return true
        }
        return false
    }

    var isProcessingMode: Bool {
        if case .processing = renderState.mode {
            return true
        }
        return false
    }

    var confirmationTiming: (deadline: Date, duration: TimeInterval)? {
        if case let .confirmingAutomaticMeetingStart(deadline, duration) = renderState.mode {
            return (deadline, duration)
        }
        return nil
    }

    var overlayLayout: RecordingIndicatorOverlayLayout {
        RecordingIndicatorOverlayLayout.resolve(renderState: renderState, settingsStore: settingsStore)
    }

    var postProcessingWarningDescriptor: RecordingPostProcessingWarningDescriptor? {
        guard isRecordingMode || isProcessingMode else { return nil }
        guard settingsStore.postProcessingEnabled else { return nil }
        guard let issue = recordingManager.postProcessingReadinessWarningIssue,
              let warningMode = recordingManager.postProcessingReadinessWarningMode
        else {
            return nil
        }

        return RecordingPostProcessingWarningDescriptor(issue: issue, mode: warningMode)
    }

    var errorView: some View {
        let message = errorMessage ?? "Error"

        return HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppDesignSystem.Colors.overlayStatusForeground)
                .font(.caption.weight(.bold))

            Text(message)
                .font(.caption.bold())
                .foregroundStyle(AppDesignSystem.Colors.overlayStatusForeground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppDesignSystem.Colors.error.opacity(0.95))
        .clipShape(Capsule())
        .shadow(
            color: .black.opacity(0.2),
            radius: AppDesignSystem.Layout.shadowRadiusSmall,
            x: AppDesignSystem.Layout.shadowX,
            y: AppDesignSystem.Layout.shadowYSmall
        )
    }

    var errorMessage: String? {
        guard case let .error(message) = renderState.mode else {
            return nil
        }
        return message
    }

    func confirmationPill(size: IndicatorSize) -> some View {
        AutoMeetingConfirmationPill(
            size: size,
            timing: confirmationTiming,
            isAnimationActive: isAnimationActive,
            onCancel: onCancel
        )
    }

    var usesMeetingPromptSource: Bool {
        renderState.kind == .meeting
    }

    func recordingCluster(size: IndicatorSize) -> some View {
        let waveformMetrics = FloatingRecordingIndicatorViewUtilities.waveformMetrics(for: size)

        return HStack(spacing: FloatingRecordingIndicatorViewUtilities.contentSpacing(for: size)) {
            statusDot(for: size)

            switch FloatingRecordingIndicatorViewUtilities.mainContentMode(for: renderState) {
            case .waveform:
                AudioVisualizer(
                    audioLevel: audioMonitor.audioMeter.averagePower,
                    isAnimationActive: isAnimationActive,
                    isSetup: isStartingMode,
                    barCount: waveformMetrics.barCount,
                    maxHeight: waveformMetrics.height,
                    barWidth: waveformMetrics.barWidth,
                    barSpacing: waveformMetrics.barSpacing,
                    barCornerRadius: waveformMetrics.barCornerRadius,
                    minHeight: AppDesignSystem.Layout.recordingIndicatorWaveformMinHeight
                )
            case .processingStatus:
                processingStatusView(size: size)
            }
        }
    }

    func processingStatusView(size: IndicatorSize) -> some View {
        HStack(spacing: 6) {
            Text(processingStageTitle)
                .font(Font(FloatingRecordingIndicatorViewUtilities.processingStatusFont(for: size)))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(AppDesignSystem.Colors.overlayForegroundMuted)
                .layoutPriority(1)
            processingActivityDots
        }
        .frame(
            width: FloatingRecordingIndicatorViewUtilities.processingStatusWidth(
                for: size,
                processingSnapshot: activeProcessingSnapshot
            ),
            alignment: .leading
        )
        .animation(AppleMotion.animation(reduceMotion: reduceMotion, kind: .default), value: processingStageTitle)
        .accessibilityLabel(processingAccessibilityLabel)
    }

    var processingActivityDots: some View {
        Group {
            if isAnimationActive, !reduceMotion {
                TimelineView(.periodic(from: .now, by: 0.35)) { context in
                    let step = Int(context.date.timeIntervalSinceReferenceDate / 0.35)
                    processingDots(activeIndex: step % 3)
                }
            } else {
                processingDots(activeIndex: 0)
            }
        }
    }

    func processingDots(activeIndex: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0 ..< 3, id: \.self) { index in
                Circle()
                    .fill(AppDesignSystem.Colors.overlayForeground)
                    .frame(width: 3, height: 3)
                    .opacity(index == activeIndex ? 0.95 : 0.35)
            }
        }
    }

    var activeProcessingSnapshot: RecordingIndicatorProcessingSnapshot {
        processingSnapshot
            ?? FloatingRecordingIndicatorViewUtilities.defaultProcessingSnapshot(for: renderState)
    }

    var processingStageTitle: String {
        activeProcessingSnapshot.step.localizedTitleKey.localized
    }

    var processingAccessibilityLabel: String {
        if let progressPercent = activeProcessingSnapshot.progressPercent {
            return "recording_indicator.processing.accessibility.with_progress".localized(
                with: processingStageTitle,
                Int(progressPercent.rounded())
            )
        }

        return "recording_indicator.processing.accessibility.title_only".localized(with: processingStageTitle)
    }

    var meetingTimerView: some View {
        Group {
            if isAnimationActive {
                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                    let durationText = FloatingRecordingIndicatorViewUtilities.formatRecordingDuration(
                        startTime: recordingManager.currentMeeting?.startTime,
                        at: context.date
                    )
                    Text(durationText)
                        .font(Font(FloatingRecordingIndicatorViewUtilities.timerFont(for: currentIndicatorSize)))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .frame(
                            width: FloatingRecordingIndicatorViewUtilities.timerReservedWidth(for: currentIndicatorSize),
                            alignment: .center
                        )
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                        .foregroundStyle(AppDesignSystem.Colors.overlayForegroundMuted)
                }
            } else {
                let durationText = FloatingRecordingIndicatorViewUtilities.formatRecordingDuration(
                    startTime: recordingManager.currentMeeting?.startTime,
                    at: Date()
                )
                Text(durationText)
                    .font(Font(FloatingRecordingIndicatorViewUtilities.timerFont(for: currentIndicatorSize)))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(
                        width: FloatingRecordingIndicatorViewUtilities.timerReservedWidth(for: currentIndicatorSize),
                        alignment: .center
                    )
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                    .foregroundStyle(AppDesignSystem.Colors.overlayForegroundMuted)
            }
        }
        .animation(nil, value: isHovering)
        .accessibilityLabel("recording_indicator.duration".localized)
    }

    var currentIndicatorSize: IndicatorSize {
        switch style {
        case .classic:
            .classic
        case .mini:
            .mini
        case .super:
            .super
        case .none:
            .classic
        }
    }

    var mainPillHorizontalPadding: CGFloat {
        if revealsExpandedControls {
            return AppDesignSystem.Layout.recordingIndicatorSidePadding
        }
        return max(AppDesignSystem.Layout.recordingIndicatorSidePadding, 16)
    }

    func mainPill(size: IndicatorSize) -> some View {
        mainPillContent(size: size)
            .padding(.horizontal, mainPillHorizontalPadding)
            .frame(height: FloatingRecordingIndicatorViewUtilities.controlHeight(for: size))
            .background(.ultraThinMaterial)
            .background(AppDesignSystem.Colors.recordingIndicatorMaterialTint)
            .overlay(
                Capsule()
                    .strokeBorder(AppDesignSystem.Colors.recordingIndicatorStroke, lineWidth: 1.2)
            )
            .clipShape(Capsule())
            .contentShape(Capsule())
            .focusable(isRecordingMode)
            .focused($isKeyboardFocused)
            .accessibilityActions {
                if !revealsExpandedControls, isRecordingMode {
                    if showsMeetingMicrophoneControl {
                        Button(collapsedMicrophoneActionName) {
                            Task { await recordingManager.toggleMeetingMicrophone() }
                        }
                    }

                    if showsMeetingNotesControl {
                        Button(collapsedNotesActionName) {
                            Task { @MainActor in
                                recordingManager.toggleMeetingNotesPanel()
                            }
                        }
                    }

                    Button("recording_indicator.expand.help".localized) {
                        revealAccessibilityControls()
                    }
                }
            }
            .onHover { hovering in
                handleMainRegionHover(hovering)
            }
    }

    func mainPillContent(size: IndicatorSize) -> some View {
        HStack(spacing: FloatingRecordingIndicatorViewUtilities.contentSpacing(for: size)) {
            if revealsExpandedControls {
                leadingControls
            }

            if showsInlinePromptSelector {
                inlinePromptControl(size: size)
                divider
            }

            recordingCluster(size: size)

            if showsInlineLanguageSelector {
                divider
                inlineLanguageControl(size: size)
            }

            if showsMeetingTimerInPill {
                divider
                meetingTimerView
            }

            if showsExpandedMeetingMicrophoneControl {
                divider
                meetingMicrophoneControl
            }

            if showsExpandedMeetingNotesControl {
                divider
                meetingNotesControl
            }

            if revealsExpandedControls {
                trailingControl
            }
        }
    }

    var collapsedMicrophoneActionName: String {
        recordingManager.isMeetingMicrophoneEnabled
            ? "recording_indicator.microphone.enabled.help".localized
            : "recording_indicator.microphone.disabled.help".localized
    }

    var collapsedNotesActionName: String {
        recordingManager.isMeetingNotesPanelVisible
            ? "recording_indicator.meeting_notes.hide.help".localized
            : "recording_indicator.meeting_notes.show.help".localized
    }

    func controlSpacing(for size: IndicatorSize) -> CGFloat {
        FloatingRecordingIndicatorViewUtilities.controlSpacing(for: size)
    }
}
