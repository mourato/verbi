import Foundation
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure

@MainActor
public final class AssistantRecordingOrchestrator {
    private let audioRecorder: any AssistantRecordingService
    private let recordingManager: RecordingManager
    private let indicator: FloatingRecordingIndicatorController
    private let screenBorder: AssistantScreenBorderController
    private let settings: AppSettingsStore
    private let playCancelSound: () -> Void

    public init(
        audioRecorder: any AssistantRecordingService,
        recordingManager: RecordingManager,
        indicator: FloatingRecordingIndicatorController,
        screenBorder: AssistantScreenBorderController,
        settings: AppSettingsStore,
        playCancelSound: @escaping () -> Void = {
            SoundFeedbackService.shared.playRecordingCancelledSound()
        }
    ) {
        self.audioRecorder = audioRecorder
        self.recordingManager = recordingManager
        self.indicator = indicator
        self.screenBorder = screenBorder
        self.settings = settings
        self.playCancelSound = playCancelSound
    }

    public func startRecording(
        flow: AssistantExecutionFlow,
        requestedAt: Date,
        onStop: @escaping @Sendable () -> Void,
        onCancel: @escaping @Sendable () -> Void
    ) async throws -> URL {
        guard settings.isAssistantEnabled else {
            throw AssistantVoiceCommandError.assistantDisabled
        }

        if flow == .integrationDispatch, !settings.isAssistantIntegrationsEnabled {
            throw AssistantVoiceCommandError.integrationDisabled
        }

        guard !recordingManager.isRecording, !recordingManager.isStartingRecording else {
            AppLogger.info(
                "Assistant start blocked because RecordingManager capture is active",
                category: .assistant
            )
            throw AssistantVoiceCommandError.recordingInProgress
        }

        guard await RecordingExclusivityCoordinator.shared.beginAssistant() else {
            AppLogger.info("Assistant recording start blocked by exclusivity coordinator", category: .assistant)
            throw AssistantVoiceCommandError.recordingInProgress
        }

        let hasPermission = await audioRecorder.hasPermission()
        if !hasPermission {
            await audioRecorder.requestPermission()
        }

        guard await audioRecorder.hasPermission() else {
            await RecordingExclusivityCoordinator.shared.endAssistant()
            throw AssistantVoiceCommandError.microphonePermissionRequired
        }

        recordingManager.refreshPostProcessingReadinessWarning(for: .assistant, settings: settings)

        let outputURL = makeTemporaryRecordingURL()

        do {
            try await audioRecorder.startRecording(to: outputURL, source: .microphone)
            indicator.show(
                renderState: recordingIndicatorRenderState(mode: .recording, executionFlow: flow),
                onStop: onStop,
                onCancel: onCancel
            )
            screenBorder.show()

            PerformanceMonitor.shared.reportMetric(
                name: "assistant_start_requested_to_recorder_ms",
                value: Date().timeIntervalSince(requestedAt) * 1000,
                unit: "ms"
            )

            return outputURL
        } catch {
            recordingManager.clearPostProcessingReadinessWarning()
            await RecordingExclusivityCoordinator.shared.endAssistant()
            cleanupRecordingFile(outputURL)
            throw AssistantVoiceCommandError.failedToStartRecording
        }
    }

    public func stopRecording() async -> URL? {
        let recordingURL = await audioRecorder.stopRecording()
        await RecordingExclusivityCoordinator.shared.endAssistant()
        return recordingURL
    }

    public func cancelRecording(currentRecordingURL: URL?) async {
        let wasRecording = audioRecorder.isRecording
        if wasRecording {
            _ = await audioRecorder.stopRecording()
        }
        await RecordingExclusivityCoordinator.shared.endAssistant()
        if wasRecording {
            playCancelSound()
        }
        recordingManager.clearPostProcessingReadinessWarning()
        indicator.hide()
        screenBorder.hide()
        cleanupRecordingFile(currentRecordingURL)
    }

    public func cleanupRecordingFile(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func makeTemporaryRecordingURL() -> URL {
        let fileName = "assistant-command-\(UUID().uuidString).m4a"
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }

    private func recordingIndicatorRenderState(
        mode: FloatingRecordingIndicatorMode,
        executionFlow: AssistantExecutionFlow
    ) -> RecordingIndicatorRenderState {
        switch executionFlow {
        case .assistantMode:
            RecordingIndicatorRenderState(mode: mode, kind: .assistant)
        case .integrationDispatch:
            RecordingIndicatorRenderState(
                mode: mode,
                kind: .assistantIntegration,
                assistantIntegrationID: settings.assistantSelectedIntegrationId
            )
        }
    }
}
