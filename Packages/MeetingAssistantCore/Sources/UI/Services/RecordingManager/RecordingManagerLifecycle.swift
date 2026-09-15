import Foundation
import MeetingAssistantCoreAudio

extension RecordingManager {
    var lifecycleOperations: RecordingLifecycleCoordinator.Operations {
        RecordingLifecycleCoordinator.Operations(
            stopRecorders: {
                let mic = await self.micRecorder.stopRecording()
                let system = await self.systemRecorder.stopRecording()
                return (mic: mic, system: system)
            },
            cancelIncremental: {
                await self.cancelIncrementalTranscriptionSessionsIfNeeded()
            },
            cancelPostStartTasks: {
                self.cancelPostStartCaptureTasks()
            },
            cleanupTemporaryFiles: { recordings in
                await self.cleanupTemporaryFiles(
                    additionalURLs: [recordings.mic, recordings.system].compactMap(\.self)
                )
            },
            removeMergedAudio: {
                if let mergedURL = await self.getMergedAudioURL() {
                    try? FileManager.default.removeItem(at: mergedURL)
                    await self.setMergedAudioURL(nil)
                }
            },
            resetState: { error, transcriptionID in
                await self.resetRecordingLifecycleState(error: error, transcriptionID: transcriptionID)
            },
            endExclusivity: {
                await RecordingExclusivityCoordinator.shared.endRecording()
            },
            playStopSound: {
                SoundFeedbackService.shared.playRecordingStopSound()
            },
            playCancelledSound: {
                SoundFeedbackService.shared.playRecordingCancelledSound()
            }
        )
    }

    func resetRecordingLifecycleState(error: Error?, transcriptionID: UUID?) {
        if let transcriptionID {
            unregisterTranscriptionSession(transcriptionID)
        }
        isRecording = false
        isStartingRecording = false
        isTranscribing = !activeTranscriptionSessionIDs.isEmpty
        cancelEstimatedPostProcessingProgress(for: currentMeeting?.id)
        if let error {
            lastError = error
            meetingState = .failed(error.localizedDescription)
            currentMeeting?.state = .failed(error.localizedDescription)
        } else {
            meetingState = .idle
        }
        clearMeetingNotesState(removePersistedValue: true)
        currentMeeting = nil
        currentCapturePurpose = nil
        isMeetingMicrophoneEnabled = false
        postProcessingContext = nil
        postProcessingContextItems = []
        dictationSessionOutputLanguageOverride = nil
        dictationStartBundleIdentifier = nil
        dictationStartURL = nil
        activeDictationStyleSnapshot = nil
        activeStartTelemetry = nil
        clearActiveTranscriptionSnapshot()
        clearPostProcessingReadinessWarning()
    }
}
