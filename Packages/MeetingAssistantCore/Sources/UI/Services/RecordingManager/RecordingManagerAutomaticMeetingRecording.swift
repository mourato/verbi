import AppKit
import ApplicationServices
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
        guard let bundleId = Bundle.main.bundleIdentifier,
              !bundleId.lowercased().contains("xctest")
        else {
            return
        }

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
        applyMeetingDetectionMode(isEnabled ? .auto : .off)
    }
}

extension RecordingManager {
    /// Enables meeting detection monitoring, optionally auto-recording when meeting candidates are confirmed.
    func enableMeetingDetection(autoRecord: Bool) {
        automaticMeetingRecordingCancellable?.cancel()
        meetingDetector.startMonitoring()

        automaticMeetingRecordingCancellable = meetingDetector.$detectedContext
            .dropFirst()
            .removeDuplicates()
            .sink { @Sendable [weak self] detectedContext in
                guard let self else { return }
                Task { @MainActor [self] in
                    let isMeetingCaptureActive = currentCapturePurpose == .meeting
                        && (isRecording || isStartingRecording)

                    guard let detectedContext else {
                        cancelAutomaticMeetingRecordingConfirmation()
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
                                Task { await self?.startCapture(purpose: .meeting) }
                            },
                            onRecordWithoutSummary: { [weak self] in
                                MeetingDetectionToastController.shared.hide()
                                AppSettingsStore.shared.selectedPromptId = AppSettingsStore.noPostProcessingPromptId
                                Task { await self?.startCapture(purpose: .meeting) }
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
    }

    func disableMeetingDetection() {
        automaticMeetingRecordingCancellable?.cancel()
        automaticMeetingRecordingCancellable = nil
        cancelAutomaticMeetingRecordingConfirmation()
        cancelAutomaticMeetingRecordingStop()
        meetingDetector.stopMonitoring()
    }

    private func resolveRunningMeetingPID(for targetApp: MeetingApp) -> pid_t {
        let runningApp = NSWorkspace.shared.runningApplications.first { app in
            guard let bid = app.bundleIdentifier else { return false }
            return targetApp.bundleIdentifiers.contains(bid)
        }
        return runningApp?.processIdentifier ?? 0
    }

    private func evaluateCallControlState(pid: pid_t, app: MeetingApp) async -> CallState {
        guard pid > 0, AXIsProcessTrusted() else {
            return .inconclusive
        }
        return await callControlProvider.evaluateCallState(for: pid, app: app)
    }

    private func executeEndCountdownToast(targetApp: MeetingApp, appName: String) async -> Bool {
        if hasSuppressedEndCountdownForSession {
            return false
        }

        let totalSeconds = MeetingEndCountdownCoordinator.Constants.endedCountdownSeconds
        let toast = MeetingDetectionToastController.shared
        toast.show(
            state: .ended(
                app: targetApp,
                appName: appName,
                countdownSeconds: totalSeconds,
                totalCountdownSeconds: totalSeconds
            ),
            onContinue: { [weak self] in
                self?.hasSuppressedEndCountdownForSession = true
                self?.meetingEndCountdownCoordinator.continueRecording()
                self?.cancelAutomaticMeetingRecordingStop()
            }
        )

        var remaining = totalSeconds
        while remaining > 0 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return false }
            remaining -= 1
            toast.show(
                state: .ended(
                    app: targetApp,
                    appName: appName,
                    countdownSeconds: remaining,
                    totalCountdownSeconds: totalSeconds
                )
            )
        }
        guard !Task.isCancelled else { return false }
        toast.hide()
        return true
    }

    private func executeSilentGracePeriod() async -> Bool {
        let totalSeconds = Int(AutomaticMeetingRecordingConstants.lostActivityGracePeriod.components.seconds)
        try? await Task.sleep(for: .seconds(Double(totalSeconds)))
        return !Task.isCancelled
    }

    private func performStopEligibilityCheck(callState: CallState) async {
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
            extra: ["reason": "meeting_candidate_and_media_lost", "callState": "\(callState)"]
        )
        await stopRecording()
    }

    private func scheduleAutomaticMeetingRecordingStop() {
        guard automaticMeetingRecordingStopTask == nil else { return }

        let currentAppBundleID = currentMeeting?.appBundleIdentifier
        let meetingAppFromCurrent = currentAppBundleID.flatMap { bid in
            MeetingApp.allCases.first { $0.bundleIdentifiers.contains(bid) }
        }
        let targetApp = automaticMeetingRecordingConfirmation?.meetingApp ?? meetingAppFromCurrent ?? .unknown
        let appName = targetApp.displayName
        let targetPid = resolveRunningMeetingPID(for: targetApp)

        automaticMeetingRecordingStopTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let callState = await evaluateCallControlState(pid: targetPid, app: targetApp)
            switch callState {
            case .inCall:
                automaticMeetingRecordingStopTask = nil
                return

            case .ended:
                let completed = await executeEndCountdownToast(targetApp: targetApp, appName: appName)
                guard completed else {
                    automaticMeetingRecordingStopTask = nil
                    return
                }

            case .inconclusive:
                let completed = await executeSilentGracePeriod()
                guard completed else { return }
            }

            await performStopEligibilityCheck(callState: callState)
        }
    }

    func cancelAutomaticMeetingRecordingStop() {
        automaticMeetingRecordingStopTask?.cancel()
        automaticMeetingRecordingStopTask = nil
        meetingEndCountdownCoordinator.cancel()
        MeetingDetectionToastController.shared.hide()
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
        MeetingDetectionToastController.shared.show(
            state: .recording(
                app: confirmation.meetingApp,
                appName: confirmation.detectedContext.appDisplayName ?? confirmation.meetingApp.displayName,
                startedAt: Date()
            ),
            onStop: { [weak self] in
                Task { await self?.stopRecording() }
            }
        )
        await startCapture(
            purpose: .meeting,
            requestedAt: confirmation.deadline,
            triggerLabel: "recording.start.automatic_meeting_confirmation"
        )
    }
}
