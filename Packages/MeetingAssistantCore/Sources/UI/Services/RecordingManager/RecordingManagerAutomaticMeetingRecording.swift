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
    func setAutomaticMeetingRecordingEnabled(_ isEnabled: Bool) {
        guard let bundleId = Bundle.main.bundleIdentifier,
              !bundleId.lowercased().contains("xctest")
        else {
            return
        }

        if isEnabled {
            enableAutoRecording()
        } else {
            disableAutoRecording()
        }
    }
}

extension RecordingManager {
    /// Enables automatic recording when meeting candidates are detected.
    func enableAutoRecording() {
        guard automaticMeetingRecordingCancellable == nil else {
            meetingDetector.startMonitoring()
            return
        }

        meetingDetector.startMonitoring()
        automaticMeetingRecordingCancellable = meetingDetector.$detectedContext
            .dropFirst()
            .removeDuplicates()
            .sink { @Sendable [weak self] detectedContext in
                Task { @MainActor in
                    guard let self else { return }

                    let isMeetingCaptureActive = self.currentCapturePurpose == .meeting
                        && (self.isRecording || self.isStartingRecording)

                    guard let detectedContext else {
                        self.cancelAutomaticMeetingRecordingConfirmation()
                        if isMeetingCaptureActive {
                            self.scheduleAutomaticMeetingRecordingStop()
                        }
                        return
                    }

                    self.cancelAutomaticMeetingRecordingStop()
                    if isIdleForAutomaticMeetingStart(
                        currentCapturePurpose: self.currentCapturePurpose,
                        isRecording: self.isRecording,
                        isStartingRecording: self.isStartingRecording
                    ) {
                        self.scheduleAutomaticMeetingRecordingConfirmation(for: detectedContext)
                    }
                }
            }
    }

    func disableAutoRecording() {
        automaticMeetingRecordingCancellable?.cancel()
        automaticMeetingRecordingCancellable = nil
        cancelAutomaticMeetingRecordingConfirmation()
        cancelAutomaticMeetingRecordingStop()
        meetingDetector.stopMonitoring()
    }

    private func scheduleAutomaticMeetingRecordingStop() {
        guard automaticMeetingRecordingStopTask == nil else { return }

        automaticMeetingRecordingStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: AutomaticMeetingRecordingConstants.lostActivityGracePeriod)
            guard !Task.isCancelled, let self else { return }

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
        await startCapture(
            purpose: .meeting,
            requestedAt: confirmation.deadline,
            triggerLabel: "recording.start.automatic_meeting_confirmation"
        )
    }
}
