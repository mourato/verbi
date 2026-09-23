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

extension RecordingManager {
    func setupRecorderErrorForwarding() {
        guard let recorder = concreteMicRecorder else { return }
        let callbackGeneration = lifecycleCoordinator.recorderCallbackGeneration

        recorder.onRecordingError = { [weak self, callbackGeneration] error in
            let generation = callbackGeneration.value
            Task { @MainActor [weak self] in
                await self?.handleUnexpectedRecorderFailure(error, generation: generation)
            }
        }
    }

    private func handleUnexpectedRecorderFailure(_ error: Error, generation: UInt64) async {
        guard generation == lifecycleCoordinator.currentRecorderCallbackGeneration() else { return }

        AppLogger.error(
            "Recorder reported an unexpected runtime failure",
            category: .recordingManager,
            error: error
        )

        if isRecording {
            await stopRecording()
            return
        }

        await lifecycleCoordinator.recorderDidFail(
            error,
            isRecording: isRecording,
            isStarting: isStartingRecording,
            generation: generation,
            operations: lifecycleOperations
        )
    }

    func setupBindings() {
        // Sync with audio recorder state
        let callbackGeneration = lifecycleCoordinator.recorderCallbackGeneration
        micRecorder.isRecordingPublisher
            .sink { [weak self] recorderIsRecording in
                guard let self else { return }

                let generation = callbackGeneration.value
                let state = RecordingLifecycleCoordinator.RecorderState(
                    recorderIsRecording: recorderIsRecording,
                    isRecording: isRecording,
                    isStarting: isStartingRecording,
                    isStartOperationInFlight: isStartOperationInFlight
                )
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    if !state.recorderIsRecording,
                       state.isRecording,
                       !state.isStarting,
                       !state.isStartOperationInFlight
                    {
                        guard generation == lifecycleCoordinator.currentRecorderCallbackGeneration() else { return }
                        await stopRecording()
                        return
                    }

                    await lifecycleCoordinator.recorderStateDidChange(
                        state,
                        generation: generation,
                        operations: lifecycleOperations
                    )
                }
            }
            .store(in: &cancellables)
    }

    func cleanupTemporaryFiles(additionalURLs: [URL] = []) async {
        var urlsToDelete = additionalURLs
        if let micURL = await getMicAudioURL() {
            urlsToDelete.append(micURL)
        }
        if let sysURL = await getSystemAudioURL() {
            urlsToDelete.append(sysURL)
        }

        storage.cleanupTemporaryFiles(urls: Array(Set(urlsToDelete)))

        await setMicAudioURL(nil)
        await setSystemAudioURL(nil)
    }

    func markRecorderStartedAt(_ recorderStartedAt: Date) {
        guard var telemetry = activeStartTelemetry else { return }
        telemetry.recorderStartedAt = recorderStartedAt
        activeStartTelemetry = telemetry

        AppLogger.debug(
            "Recording startup reached recorder",
            category: .performance,
            extra: [
                "trace": telemetry.traceID,
                "trigger": telemetry.triggerLabel,
                "source": telemetry.source.rawValue
            ]
        )

        PerformanceMonitor.shared.reportMetric(
            name: "recording_start_requested_to_recorder_ms",
            value: recorderStartedAt.timeIntervalSince(telemetry.requestedAt) * 1000,
            unit: "ms"
        )
        PerformanceMonitor.shared.reportMetric(
            name: "recording_start_entry_to_recorder_ms",
            value: recorderStartedAt.timeIntervalSince(telemetry.managerEntryAt) * 1000,
            unit: "ms"
        )
    }

    func processRecordedAudio(
        micURL: URL?,
        sysURL: URL?,
        mergedAudioURL: URL? = nil,
        usesIncrementalDictation: Bool? = nil
    ) async throws -> URL {
        guard let outputURL = mergedAudioURL != nil ? mergedAudioURL : await getMergedAudioURL() else {
            throw RecordingManagerError.noOutputPath
        }

        let usesIncrementalDictation = usesIncrementalDictation
            ?? (incrementalDictationCoordinator != nil && currentCapturePurpose == .dictation)
        if usesIncrementalDictation,
           let micURL
        {
            return micURL
        }

        let settings = AppSettingsStore.shared

        if settings.shouldMergeAudioFiles {
            var inputURLs: [URL] = []
            if let micURL {
                inputURLs.append(micURL)
            }
            if let sysURL {
                inputURLs.append(sysURL)
            }

            if inputURLs.count >= 2 {
                AppLogger.info("Merging \(inputURLs.count) audio files...", category: .recordingManager)
                let finalURL = try await audioMerger.mergeAudioFiles(
                    inputURLs: inputURLs,
                    to: outputURL,
                    format: settings.audioFormat
                )
                await cleanupTemporaryFiles()
                return finalURL
            } else if let singleURL = inputURLs.first {
                AppLogger.info("Single audio source recorded. Skipping merge and using: \(singleURL.lastPathComponent)", category: .recordingManager)

                if singleURL == outputURL {
                    await cleanupTemporaryFiles()
                    return outputURL
                }

                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try FileManager.default.moveItem(at: singleURL, to: outputURL)
                await cleanupTemporaryFiles()
                return outputURL
            } else {
                throw RecordingManagerError.noInputFiles
            }
        } else {
            AppLogger.info(
                "Audio merge disabled. Using microphone recording as primary.",
                category: .recordingManager
            )

            guard let sourceURL = micURL else {
                throw RecordingManagerError.noInputFiles
            }

            if sourceURL != outputURL {
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try FileManager.default.moveItem(at: sourceURL, to: outputURL)
            }

            await cleanupTemporaryFiles()
            return outputURL
        }
    }
}
