import AppKit
import Combine
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

public struct AutomaticMeetingRecordingConfirmation: Sendable, Equatable {
    public let id: UUID
    public let meetingApp: MeetingApp
    public let detectedContext: ResolvedCaptureContext
    public let detectedAt: Date
    public let deadline: Date
    public let duration: TimeInterval

    public init(
        id: UUID = UUID(),
        meetingApp: MeetingApp,
        detectedContext: ResolvedCaptureContext,
        detectedAt: Date,
        deadline: Date,
        duration: TimeInterval
    ) {
        self.id = id
        self.meetingApp = meetingApp
        self.detectedContext = detectedContext
        self.detectedAt = detectedAt
        self.deadline = deadline
        self.duration = duration
    }
}

func isIdleForAutomaticMeetingStart(
    currentCapturePurpose: CapturePurpose?,
    isRecording: Bool,
    isStartingRecording: Bool
) -> Bool {
    guard !isRecording, !isStartingRecording else { return false }
    return currentCapturePurpose == nil
}

public extension RecordingManager {
    func applyMeetingDetectionMode(_ mode: MeetingDetectionMode) {
        switch mode {
        case .off:
            disableMeetingDetection()
        case .notify:
            enableMeetingDetection(autoRecord: false)
        case .auto:
            enableMeetingDetection(autoRecord: true)
        }
    }

    func setAutomaticMeetingRecordingEnabled(_ isEnabled: Bool) {
        guard let bundleID = Bundle.main.bundleIdentifier,
              bundleID.range(of: "xctest", options: .caseInsensitive) == nil
        else { return }
        applyMeetingDetectionMode(isEnabled ? .auto : .off)
    }
}

extension RecordingManager {
    /// Enables meeting detection monitoring, optionally auto-recording when meeting candidates are confirmed.
    func enableMeetingDetection(autoRecord: Bool) {
        automaticMeetingRecordingCancellable?.cancel()
        let observationID = UUID()
        meetingDetectionObservationID = observationID
        cancelAutomaticMeetingRecordingConfirmation()

        automaticMeetingRecordingCancellable = meetingDetector.$detectedContext
            .removeDuplicates()
            .sink { @Sendable [weak self] detectedContext in
                guard let self else { return }
                Task { @MainActor [self] in
                    guard meetingDetectionObservationID == observationID else { return }
                    guard let detectedContext else {
                        cancelAutomaticMeetingRecordingConfirmation()
                        if case .detected = MeetingDetectionToastController.shared.currentState {
                            MeetingDetectionToastController.shared.hide()
                        }
                        return
                    }

                    cancelAutomaticMeetingRecordingStop()
                    if isIdleForAutomaticMeetingStart(
                        currentCapturePurpose: currentCapturePurpose,
                        isRecording: isRecording,
                        isStartingRecording: isStartingRecording
                    ) {
                        let targetApp = detectedContext.meetingApp
                        let appName = detectedContext.appDisplayName ?? targetApp.displayName
                        MeetingDetectionToastController.shared.show(
                            state: .detected(app: targetApp, appName: appName, context: detectedContext),
                            onRecord: { [weak self] in
                                MeetingDetectionToastController.shared.hide()
                                Task { await self?.startMeetingFromDetectionToast(detectedContext) }
                            },
                            onRecordWithoutSummary: { [weak self] in
                                MeetingDetectionToastController.shared.hide()
                                Task { await self?.startMeetingFromDetectionToast(detectedContext, skipPostProcessing: true) }
                            },
                            onDismiss: {
                                MeetingDetectionToastController.shared.hide()
                            }
                        )

                        if autoRecord {
                            scheduleAutomaticMeetingRecordingConfirmation(for: detectedContext)
                        }
                    }
                }
            }
        meetingDetector.startMonitoring()
    }

    func disableMeetingDetection() {
        meetingDetectionToastStartContext = nil
        meetingDetectionObservationID = UUID()
        automaticMeetingRecordingCancellable?.cancel()
        automaticMeetingRecordingCancellable = nil
        cancelAutomaticMeetingRecordingConfirmation()
        cancelAutomaticMeetingRecordingStop()
        meetingDetector.stopMonitoring()
        MeetingDetectionToastController.shared.hide()
    }

    func cancelAutomaticMeetingRecordingStop() {
        automaticMeetingRecordingStopTask?.cancel()
        automaticMeetingRecordingStopTask = nil
    }

    func scheduleAutomaticMeetingRecordingConfirmation(for detectedContext: ResolvedCaptureContext) {
        if automaticMeetingRecordingConfirmation?.detectedContext == detectedContext {
            return
        }

        automaticMeetingRecordingConfirmationTask?.cancel()

        let detectedAt = Date()
        let duration = AppSettingsStore.shared.automaticAutomaticMeetingRecordingConfirmationDelay.timeInterval
        let confirmation = AutomaticMeetingRecordingConfirmation(
            meetingApp: detectedContext.meetingApp,
            detectedContext: detectedContext,
            detectedAt: detectedAt,
            deadline: detectedAt.addingTimeInterval(duration),
            duration: duration
        )

        automaticMeetingRecordingConfirmation = confirmation
        automaticMeetingRecordingConfirmationTask = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(max(0, duration) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self else { return }
            await startConfirmedAutomaticMeetingRecording(confirmation)
        }
    }

    public func cancelAutomaticMeetingRecordingConfirmation() {
        automaticMeetingRecordingConfirmationTask?.cancel()
        automaticMeetingRecordingConfirmationTask = nil
        automaticMeetingRecordingConfirmation = nil
    }

    private func startConfirmedAutomaticMeetingRecording(_ confirmation: AutomaticMeetingRecordingConfirmation) async {
        guard automaticMeetingRecordingConfirmation?.id == confirmation.id else { return }
        guard meetingDetector.detectedContext == confirmation.detectedContext else {
            cancelAutomaticMeetingRecordingConfirmation()
            return
        }
        guard isIdleForAutomaticMeetingStart(
            currentCapturePurpose: currentCapturePurpose,
            isRecording: isRecording,
            isStartingRecording: isStartingRecording
        ) else {
            cancelAutomaticMeetingRecordingConfirmation()
            return
        }

        automaticMeetingRecordingConfirmationTask = nil
        automaticMeetingRecordingConfirmation = nil
        await startMeetingFromDetectionToast(
            confirmation.detectedContext,
            requestedAt: confirmation.deadline,
            triggerLabel: "recording.start.automatic_meeting_confirmation"
        )
    }

    func startMeetingFromDetectionToast(
        _ context: ResolvedCaptureContext,
        requestedAt: Date = Date(),
        triggerLabel: String = "recording.start.meeting_detection_toast",
        skipPostProcessing: Bool = false
    ) async {
        guard !isRecording, !isStartingRecording, !isStartOperationInFlight else { return }
        meetingDetectionToastStartContext = context
        defer { meetingDetectionToastStartContext = nil }
        await startCapture(
            purpose: .meeting,
            source: source(for: .meeting),
            requestedAt: requestedAt,
            triggerLabel: triggerLabel,
            skipPostProcessing: skipPostProcessing
        )
    }
}
