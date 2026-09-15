import AVFoundation
import Combine
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import os.log
import UserNotifications

// MARK: - Status Monitoring

extension RecordingManager {
    private enum StatusMonitoringConstants {
        static let pollingIntervalSeconds: Double = 30
    }

    /// Start periodic status monitoring.
    func startStatusMonitoring() {
        statusCheckTask?.cancel()

        statusCheckTask = Task { @Sendable @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.checkServiceStatus()
                try? await Task.sleep(for: .seconds(StatusMonitoringConstants.pollingIntervalSeconds))
            }
        }
    }

    /// Check and update service status.
    private func checkServiceStatus() async {
        transcriptionStatus.updateServiceState(.connecting)

        do {
            let status = try await transcriptionClient.fetchServiceStatus()
            transcriptionStatus.updateServiceState(.connected)
            transcriptionStatus.updateModelState(status.modelStateEnum, device: status.device)
        } catch {
            transcriptionStatus.updateServiceState(.disconnected)
            transcriptionStatus.recordError(.connectionFailed(error.localizedDescription))
        }
    }

    /// Manually refresh service status.
    func refreshServiceStatus() async {
        await checkServiceStatus()
    }

    /// Resets the manager and actor state to idle.
    public func reset() async {
        if isRecording || isStartingRecording || isStartOperationInFlight {
            await cancelRecording()
        }
        await lifecycleCoordinator.waitForIdle()

        cancelPostStartCaptureTasks()
        await recordingActor.reset()
        isRecording = false
        isStartingRecording = false
        isTranscribing = false
        isForegroundTranscribing = false
        activeTranscriptionSessionIDs.removeAll()
        foregroundTranscriptionSessionID = nil
        await cancelIncrementalTranscriptionSessionsIfNeeded()
        cancelEstimatedPostProcessingProgress()
        meetingState = .idle
        currentMeeting = nil
        currentCapturePurpose = nil
        isMeetingMicrophoneEnabled = false
        lastError = nil
        dictationSessionOutputLanguageOverride = nil
        dictationStartBundleIdentifier = nil
        dictationStartURL = nil
        activeStartTelemetry = nil
        clearPostProcessingReadinessWarning()
        RecordingIndicatorProcessingStateStore.shared.reset()
    }
}
