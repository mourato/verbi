import AppKit
import Combine
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

private enum AutomaticMeetingRecordingConstants {
    // ponytail: fixed grace period; make it configurable only if real usage needs tuning.
    static let lostActivityGracePeriod: Duration = .seconds(30)
}

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

func isAutomaticMeetingRecordingStopEligible(
    currentCapturePurpose: CapturePurpose?,
    isRecording: Bool,
    isStartingRecording: Bool,
    detectedContext: ResolvedCaptureContext?,
    mediaActivity: MeetingMediaActivity
) -> Bool {
    currentCapturePurpose == .meeting
        && (isRecording || isStartingRecording)
        && detectedContext == nil
        && !mediaActivity.isActive
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
                    let isMeetingCaptureActive = currentCapturePurpose == .meeting
                        && (isRecording || isStartingRecording)

                    guard let detectedContext else {
                        cancelAutomaticMeetingRecordingConfirmation()
                        if case .detected = MeetingDetectionToastController.shared.currentState {
                            MeetingDetectionToastController.shared.hide()
                        }
                        if isMeetingCaptureActive {
                            scheduleAutomaticMeetingRecordingStop()
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

    private func executeSilentGracePeriod() async -> Bool {
        let totalSeconds = Int(AutomaticMeetingRecordingConstants.lostActivityGracePeriod.components.seconds)
        try? await Task.sleep(for: .seconds(Double(totalSeconds)))
        return !Task.isCancelled
    }

    private func performStopEligibilityCheck() async {
        automaticMeetingRecordingStopTask = nil
        let mediaActivity = meetingDetector.refreshMediaActivity()
        let shouldStop = isAutomaticMeetingRecordingStopEligible(
            currentCapturePurpose: currentCapturePurpose,
            isRecording: isRecording,
            isStartingRecording: isStartingRecording,
            detectedContext: meetingDetector.detectedContext,
            mediaActivity: mediaActivity
        )
        guard shouldStop else {
            if currentCapturePurpose == .meeting,
               isRecording || isStartingRecording,
               meetingDetector.detectedContext == nil
            {
                scheduleAutomaticMeetingRecordingStop()
            }
            return
        }

        AppLogger.info(
            "Stopping automatic meeting recording after meeting activity was lost",
            category: .recordingManager,
            extra: ["reason": "meeting_candidate_and_media_lost"]
        )
        await stopRecording()
    }

    private func scheduleAutomaticMeetingRecordingStop() {
        guard automaticMeetingRecordingStopTask == nil else { return }

        automaticMeetingRecordingStopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard await executeSilentGracePeriod() else { return }
            await performStopEligibilityCheck()
        }
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
