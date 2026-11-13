import AppKit
import Combine
import Foundation
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

public struct AutomaticMeetingRecordingConfirmation: Sendable, Equatable {
    public let id: UUID
    public let meetingApp: CaptureOrigin
    public let detectedContext: ResolvedCaptureContext
    public let detectedAt: Date
    public let deadline: Date
    public let duration: TimeInterval

    public init(
        id: UUID = UUID(),
        meetingApp: CaptureOrigin,
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
            .removeDuplicates { previous, current in
                switch (previous, current) {
                case (nil, nil): true
                case let (previous?, current?): previous.isSameMeeting(as: current)
                default: false
                }
            }
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
        meetingEndPromptObservation = meetingDetector.$isMeetingSignalPresent
            .removeDuplicates()
            .sink { [weak self] signalPresent in
                MainActor.assumeIsolated {
                    self?.meetingSignalPresenceChanged(signalPresent)
                }
            }
    }

    func disableMeetingDetection() {
        cancelMeetingEndPrompt(resetSuppression: true)
        meetingEndPromptObservation?.cancel()
        meetingEndPromptObservation = nil
        meetingDetectionToastStartContext = nil
        meetingDetectionObservationID = UUID()
        automaticMeetingRecordingCancellable?.cancel()
        automaticMeetingRecordingCancellable = nil
        cancelAutomaticMeetingRecordingConfirmation()
        meetingDetector.stopMonitoring()
        MeetingDetectionToastController.shared.hide()
    }

    func meetingSignalPresenceChanged(_ isPresent: Bool) {
        guard isPresent else {
            scheduleMeetingEndPromptIfEligible()
            return
        }

        let wasShowingPrompt = meetingEndPromptDeadline != nil
        cancelMeetingEndPrompt(resetSuppression: true)
        if wasShowingPrompt {
            restoreMeetingRecordingToast()
        }
    }

    func scheduleMeetingEndPromptIfEligible() {
        guard isMeetingEndPromptEligible,
              !meetingEndPromptIgnoredForLoss,
              meetingEndPromptContext != nil,
              meetingEndPromptGraceTask == nil,
              meetingEndPromptDeadline == nil
        else { return }

        meetingEndPromptGraceTask = meetingEndPromptScheduler.schedule(after: 15) { [weak self] in
            guard let self else { return }
            meetingEndPromptGraceTask = nil
            guard isMeetingEndPromptEligible,
                  !meetingDetector.isMeetingSignalPresent,
                  meetingEndPromptContext != nil
            else { return }
            presentMeetingEndPrompt()
        }
    }

    func presentMeetingEndPrompt() {
        guard isMeetingEndPromptEligible,
              !meetingDetector.isMeetingSignalPresent,
              let context = meetingEndPromptContext,
              let startedAt = meetingEndPromptStartedAt
        else { return }

        let deadline = now().addingTimeInterval(30)
        meetingEndPromptDeadline = deadline
        MeetingDetectionToastController.shared.show(
            state: .endPrompt(
                app: context.meetingApp,
                appName: context.appDisplayName ?? context.meetingApp.displayName,
                startedAt: startedAt,
                deadline: deadline
            ),
            onStop: { [weak self] in
                Task { await self?.stopRecording() }
            },
            onKeepRecording: { [weak self] in
                self?.keepRecordingAfterMeetingEndPrompt()
            }
        )
        meetingEndPromptStopTask = meetingEndPromptScheduler.schedule(after: 30) { [weak self] in
            guard let self,
                  !meetingDetector.isMeetingSignalPresent,
                  meetingEndPromptDeadline == deadline
            else { return }
            cancelMeetingEndPrompt(resetSuppression: false)
            await stopRecording()
        }
    }

    func keepRecordingAfterMeetingEndPrompt() {
        meetingEndPromptIgnoredForLoss = true
        cancelMeetingEndPrompt(resetSuppression: false)
        guard let context = meetingEndPromptContext,
              let startedAt = meetingEndPromptStartedAt
        else {
            MeetingDetectionToastController.shared.hide()
            return
        }
        MeetingDetectionToastController.shared.show(
            state: .recording(
                app: context.meetingApp,
                appName: context.appDisplayName ?? context.meetingApp.displayName,
                startedAt: startedAt
            ),
            onStop: { [weak self] in
                Task { await self?.stopRecording() }
            }
        )
    }

    func restoreMeetingRecordingToast() {
        guard isMeetingEndPromptEligible,
              let context = meetingEndPromptContext,
              let startedAt = meetingEndPromptStartedAt
        else {
            MeetingDetectionToastController.shared.hide()
            return
        }
        MeetingDetectionToastController.shared.show(
            state: .recording(
                app: context.meetingApp,
                appName: context.appDisplayName ?? context.meetingApp.displayName,
                startedAt: startedAt
            ),
            onStop: { [weak self] in
                Task { await self?.stopRecording() }
            }
        )
    }

    func cancelMeetingEndPrompt(resetSuppression: Bool) {
        meetingEndPromptGraceTask?.cancel()
        meetingEndPromptGraceTask = nil
        meetingEndPromptStopTask?.cancel()
        meetingEndPromptStopTask = nil
        meetingEndPromptDeadline = nil
        if resetSuppression {
            meetingEndPromptIgnoredForLoss = false
        }
        if case .endPrompt = MeetingDetectionToastController.shared.currentState {
            MeetingDetectionToastController.shared.hide()
        }
    }

    var isMeetingEndPromptEligible: Bool {
        isRecording
            && currentMeeting?.capturePurpose == .meeting
            && AppSettingsStore.shared.meetingDetectionMode != .off
            && AppSettingsStore.shared.isMeetingTranscriptionEnabled
    }

    func scheduleAutomaticMeetingRecordingConfirmation(for detectedContext: ResolvedCaptureContext) {
        if let pending = automaticMeetingRecordingConfirmation?.detectedContext, pending.isSameMeeting(as: detectedContext) {
            return
        }

        automaticMeetingRecordingConfirmationTask?.cancel()

        let detectedAt = Date()
        let duration = AppSettingsStore.shared.automaticRecordingConfirmationDelay.timeInterval
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
        // A meeting inside its loss grace period is still shown, but only a live signal may
        // start a recording without a user action.
        guard meetingDetector.isMeetingSignalPresent,
              meetingDetector.detectedContext?.isSameMeeting(as: confirmation.detectedContext) == true,
              isIdleForAutomaticMeetingStart(
                  currentCapturePurpose: currentCapturePurpose,
                  isRecording: isRecording,
                  isStartingRecording: isStartingRecording
              )
        else {
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
