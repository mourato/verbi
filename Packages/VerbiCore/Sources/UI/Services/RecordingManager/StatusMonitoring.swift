import AVFoundation
import Combine
import Foundation
import os.log
import UserNotifications
import VerbiCoreAI
import VerbiCoreAudio
import VerbiCoreCommon
import VerbiCoreData
import VerbiCoreDomain
import VerbiCoreInfrastructure

extension RecordingManager {
    private enum StatusMonitoringConstants {
        static let pollingIntervalSeconds: Double = 30
    }

    func startStatusMonitoring() {
        statusCheckTask?.cancel()

        statusCheckTask = Task { @Sendable @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.checkServiceStatus()
                try? await Task.sleep(for: .seconds(StatusMonitoringConstants.pollingIntervalSeconds))
            }
        }
    }

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

    func refreshServiceStatus() async {
        await checkServiceStatus()
    }

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
