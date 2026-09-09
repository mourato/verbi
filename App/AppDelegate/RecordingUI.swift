import AppKit
import Combine
import KeyboardShortcuts
import MeetingAssistantCore
import os
import SwiftUI

extension AppDelegate {

    // MARK: - Public Methods

    /// Update menu bar icon and menu item based on recording state.
    func updateStatusIcon(isRecording: Bool) {
        let accessibilityKey = isRecording ? "menubar.accessibility.recording" : "menubar.accessibility.idle"
        let accessibilityDesc = accessibilityKey.localized
        statusItem?.button?.image = makeStatusBarImage(
            isRecording: isRecording,
            accessibilityDescription: accessibilityDesc,
        )
        statusItem?.button?.contentTintColor = nil
    }

    func makeStatusBarImage(isRecording: Bool, accessibilityDescription: String) -> NSImage? {
        if isRecording {
            guard let baseImage = NSImage(
                systemSymbolName: "record.circle.fill",
                accessibilityDescription: accessibilityDescription,
            ) else {
                return nil
            }
            let redConfig = NSImage.SymbolConfiguration(hierarchicalColor: .systemRed)
            let configuredImage = baseImage.withSymbolConfiguration(redConfig) ?? baseImage
            configuredImage.isTemplate = false
            return configuredImage
        }

        return makeIdleStatusBarImage(accessibilityDescription: accessibilityDescription)
    }

    private func makeIdleStatusBarImage(accessibilityDescription: String) -> NSImage? {
        guard let appIcon = NSImage(named: "MenubarIcon") else { return nil }

        let canvasSize = NSSize(width: 18, height: 18)
        let targetVisibleOccupancy: CGFloat = 0.95
        // Current MenubarIcon PNG alpha bounds occupy 98.44% of its transparent canvas.
        let sourceVisibleOccupancy: CGFloat = 0.9_844
        let drawSize = NSSize(
            width: canvasSize.width * targetVisibleOccupancy / sourceVisibleOccupancy,
            height: canvasSize.height * targetVisibleOccupancy / sourceVisibleOccupancy,
        )
        let drawRect = NSRect(
            x: (canvasSize.width - drawSize.width) / 2,
            y: (canvasSize.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height,
        )

        let resizedIcon = NSImage(size: canvasSize)
        resizedIcon.lockFocus()
        appIcon.draw(
            in: drawRect,
            from: NSRect(origin: .zero, size: appIcon.size),
            operation: .copy,
            fraction: 1.0,
        )
        resizedIcon.unlockFocus()
        resizedIcon.isTemplate = true
        resizedIcon.accessibilityDescription = accessibilityDescription
        return resizedIcon
    }

    func updateFloatingIndicator(
        isRecording: Bool,
        isAssistantRecording: Bool,
        isStarting: Bool,
        isProcessing: Bool,
        automaticMeetingConfirmation: AutomaticMeetingRecordingConfirmation?,
        capturePurpose: CapturePurpose?,
        recordingSource: RecordingSource,
        meetingType: MeetingType? = nil,
    ) {
        let recordingState = indicatorRenderState(
            mode: .recording,
            capturePurpose: capturePurpose,
            recordingSource: recordingSource,
            meetingType: meetingType,
            isAssistantRecording: isAssistantRecording,
        )
        let startingState = indicatorRenderState(
            mode: .starting,
            capturePurpose: capturePurpose,
            recordingSource: recordingSource,
            meetingType: meetingType,
            isAssistantRecording: isAssistantRecording,
        )
        let processingState = indicatorRenderState(
            mode: .processing,
            capturePurpose: capturePurpose,
            recordingSource: recordingSource,
            meetingType: meetingType,
            isAssistantRecording: isAssistantRecording,
        )
        let confirmationState = automaticMeetingConfirmation.map { confirmation in
            RecordingIndicatorRenderState(
                mode: .confirmingAutomaticMeetingStart(
                    deadline: confirmation.deadline,
                    duration: confirmation.duration,
                ),
                kind: .meeting,
            )
        }

        if isRecording {
            if isAssistantRecording {
                floatingIndicatorController.show(
                    renderState: recordingState,
                    onStop: { [weak self] in
                        Task { @MainActor [weak self] in
                            await self?.assistantVoiceCommandService.stopAndProcess()
                        }
                    },
                    onCancel: { [weak self] in
                        Task { @MainActor [weak self] in
                            await self?.assistantVoiceCommandService.cancelRecording()
                        }
                    },
                )
            } else {
                floatingIndicatorController.show(renderState: recordingState)
            }
        } else if isStarting {
            floatingIndicatorController.show(renderState: startingState)
        } else if let confirmationState {
            floatingIndicatorController.show(
                renderState: confirmationState,
                onStop: {},
                onCancel: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.recordingManager.cancelAutomaticMeetingRecordingConfirmation()
                    }
                },
            )
        } else if isProcessing {
            floatingIndicatorController.show(renderState: processingState)
        } else if recordingManager.isTranscribing || recordingManager.isForegroundTranscribing {
            // Safety: if transcription is active, keep showing processing even if
            // the isProcessing flag didn't capture it due to timing.
            floatingIndicatorController.show(renderState: processingState)
        } else if floatingIndicatorController.isVisible,
                  case .error = floatingIndicatorController.renderState.mode
        {
            return
        } else {
            floatingIndicatorController.hide()
        }
    }

    func updateMeetingNotesPanel(isRecording: Bool, capturePurpose: CapturePurpose?) {
        let hasMeetingSession = isRecording && capturePurpose == .meeting
        let wantsPanel = recordingManager.isMeetingNotesPanelVisible || meetingNotesPaneController.isUserOpened

        guard wantsPanel else {
            if meetingNotesPaneController.isVisible {
                meetingNotesPaneController.dismiss()
            }
            return
        }

        if hasMeetingSession, let meetingID = recordingManager.currentMeeting?.id {
            meetingNotesPaneController.summon(scope: .meetingSession(meetingID: meetingID))
            return
        }

        if recordingManager.isMeetingNotesPanelVisible || meetingNotesPaneController.isVisible {
            meetingNotesPaneController.summon()
        }
    }

    private func indicatorRenderState(
        mode: FloatingRecordingIndicatorMode,
        capturePurpose: CapturePurpose?,
        recordingSource: RecordingSource,
        meetingType: MeetingType?,
        isAssistantRecording: Bool,
    ) -> RecordingIndicatorRenderState {
        guard isAssistantRecording else {
            if let capturePurpose {
                let kind: RecordingIndicatorKind = capturePurpose == .dictation ? .dictation : .meeting
                return RecordingIndicatorRenderState(
                    mode: mode,
                    kind: kind,
                    assistantIntegrationID: nil,
                    meetingType: capturePurpose == .meeting ? meetingType : nil,
                )
            }

            return RecordingIndicatorRenderState.forRecordingSource(
                mode: mode,
                recordingSource: recordingSource,
                meetingType: meetingType,
            )
        }

        switch floatingIndicatorController.renderState.kind {
        case .assistantIntegration:
            return RecordingIndicatorRenderState(
                mode: mode,
                kind: .assistantIntegration,
                assistantIntegrationID: floatingIndicatorController.renderState.assistantIntegrationID,
            )
        case .assistant, .dictation, .meeting:
            return RecordingIndicatorRenderState(mode: mode, kind: .assistant)
        }
    }

}
