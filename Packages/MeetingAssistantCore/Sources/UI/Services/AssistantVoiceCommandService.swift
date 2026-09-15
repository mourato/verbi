import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

@MainActor
public final class AssistantVoiceCommandService: ObservableObject {
    @Published public private(set) var isRecording = false
    @Published public private(set) var isProcessing = false

    private let audioRecorder: any AssistantRecordingService
    private let transcriptionPhase: AssistantTranscriptionPhase
    private let aiPhase: AssistantAIPhase
    private let recordingManager: RecordingManager
    private let indicator: FloatingRecordingIndicatorController
    private let screenBorder: AssistantScreenBorderController
    private let settings: AppSettingsStore
    private let normalizationPhase: AssistantNormalizationPhase
    private let dispatchPhase: AssistantDispatchPhase
    private let recordingOrchestrator: AssistantRecordingOrchestrator

    private var currentRecordingURL: URL?
    private var currentExecutionFlow: AssistantExecutionFlow = .assistantMode

    public init(
        audioRecorder: any AssistantRecordingService = AudioRecorder.shared,
        transcriptionClient: TranscriptionClient = .shared,
        postProcessingService: PostProcessingService = .shared,
        recordingManager: RecordingManager = .shared,
        indicator: FloatingRecordingIndicatorController = FloatingRecordingIndicatorController(),
        screenBorder: AssistantScreenBorderController = AssistantScreenBorderController(),
        settings: AppSettingsStore = .shared,
        normalizationPhase: AssistantNormalizationPhase = AssistantNormalizationPhase(),
        transcriptionPhase: AssistantTranscriptionPhase? = nil,
        aiPhase: AssistantAIPhase? = nil,
        dispatchPhase: AssistantDispatchPhase? = nil,
        raycastIntegrationService: any AssistantDeepLinkDispatching = AssistantRaycastIntegrationService(),
        scriptRunner: AssistantBashScriptRunner = AssistantBashScriptRunner(),
        textSelectionService: AssistantTextSelectionService = AssistantTextSelectionService()
    ) {
        self.audioRecorder = audioRecorder
        self.transcriptionPhase = transcriptionPhase ?? AssistantTranscriptionPhase(transcriptionClient: transcriptionClient)
        self.aiPhase = aiPhase ?? AssistantAIPhase(
            postProcessingService: postProcessingService,
            scriptRunner: scriptRunner,
            settings: settings
        )
        self.recordingManager = recordingManager
        self.indicator = indicator
        self.screenBorder = screenBorder
        self.settings = settings
        self.normalizationPhase = normalizationPhase
        self.dispatchPhase = dispatchPhase ?? AssistantDispatchPhase(
            raycastIntegrationService: raycastIntegrationService,
            textSelectionService: textSelectionService,
            normalizationPhase: normalizationPhase
        )
        recordingOrchestrator = AssistantRecordingOrchestrator(
            audioRecorder: audioRecorder,
            recordingManager: recordingManager,
            indicator: indicator,
            screenBorder: screenBorder,
            settings: settings
        )
    }

    public func startRecording(flow: AssistantExecutionFlow = .assistantMode) async {
        guard !isRecording, !isProcessing else { return }
        do {
            let outputURL = try await recordingOrchestrator.startRecording(
                flow: flow,
                requestedAt: Date(),
                onStop: { [weak self] in
                    Task { @MainActor [weak self] in
                        await self?.stopAndProcess()
                    }
                },
                onCancel: { [weak self] in
                    Task { @MainActor [weak self] in
                        await self?.cancelRecording()
                    }
                }
            )
            currentRecordingURL = outputURL
            currentExecutionFlow = flow
            isRecording = true
        } catch let error as AssistantVoiceCommandError {
            showError(error)
        } catch {
            showError(.failedToStartRecording)
        }
    }

    public func stopAndProcess() async {
        guard isRecording, !isProcessing else { return }

        recordingManager.refreshPostProcessingReadinessWarning(for: .assistant, settings: settings)
        isProcessing = true
        indicator.updateProcessingSnapshot(.init(step: .transcribingCommand))
        indicator.update(mode: .processing)

        let recordingURL = await recordingOrchestrator.stopRecording()
        isRecording = false

        defer {
            isProcessing = false
            currentExecutionFlow = .assistantMode
            screenBorder.hide()
            recordingOrchestrator.cleanupRecordingFile(recordingURL ?? currentRecordingURL)
            currentRecordingURL = nil
            recordingManager.clearPostProcessingReadinessWarning()
        }

        do {
            let (command, executionFlow, selectedIntegration) = try await performTranscription(recordingURL: recordingURL)
            let (sourceText, selectedTextResult) = try await captureSourceText(executionFlow: executionFlow, command: command)
            let processedCommand = try await processWithAI(
                sourceText: sourceText,
                command: command,
                executionFlow: executionFlow,
                selectedIntegration: selectedIntegration
            )
            let finalCommand = normalizationPhase.applyNormalization(
                processedCommand: processedCommand,
                command: command,
                executionFlow: executionFlow,
                sourceText: sourceText
            )
            try await executeDispatch(
                executionFlow: executionFlow,
                finalCommand: finalCommand,
                command: command,
                processedCommand: processedCommand,
                selectedIntegration: selectedIntegration,
                selectedTextResult: selectedTextResult
            )
            indicator.hide()
        } catch let error as AssistantVoiceCommandError {
            AppLogger.error("Assistant processing failed with known error", category: .assistant, error: error)
            showError(error)
        } catch let error as PostProcessingError {
            AppLogger.error("Assistant post-processing failed", category: .assistant, error: error)
            indicator.showError(error.localizedDescription)
        } catch {
            AppLogger.error("Assistant processing failed with unexpected error", category: .assistant, error: error)
            showError(.processingFailed)
        }
    }

    // MARK: - Phase Helpers

    private func performTranscription(recordingURL: URL?) async throws -> (
        command: String,
        executionFlow: AssistantExecutionFlow,
        selectedIntegration: AssistantIntegrationConfig?
    ) {
        indicator.updateProcessingSnapshot(.init(step: .transcribingCommand))
        guard let recordingURL else {
            throw AssistantVoiceCommandError.failedToStopRecording
        }

        // Snapshot current vocabulary state for this assistant command.
        let vocabularySnapshot = VocabularySnapshot.current(from: settings)
        let vocabularyHints = vocabularySnapshot.providerHints
        let selection = settings.resolvedTranscriptionSelection(for: .assistant)
        let inputLanguageCode = settings.resolvedTranscriptionInputLanguageCode(for: .assistant)

        return try await transcriptionPhase.performTranscription(
            recordingURL: recordingURL,
            vocabularyReplacementRules: vocabularySnapshot.replacementRules,
            vocabularyHints: vocabularyHints.isEmpty ? nil : vocabularyHints,
            selection: selection,
            inputLanguageCode: inputLanguageCode,
            executionFlow: currentExecutionFlow,
            isAssistantIntegrationsEnabled: settings.isAssistantIntegrationsEnabled,
            assistantSelectedIntegration: settings.assistantSelectedIntegration
        )
    }

    private func captureSourceText(
        executionFlow: AssistantExecutionFlow,
        command: String
    ) async throws -> (
        sourceText: String,
        selectedTextResult: (text: String, snapshot: AssistantTextSelectionService.PasteboardSnapshot)?
    ) {
        indicator.updateProcessingSnapshot(.init(step: .capturingContext))
        return try await dispatchPhase.captureSourceText(
            executionFlow: executionFlow,
            command: command
        )
    }

    private func processWithAI(
        sourceText: String,
        command: String,
        executionFlow: AssistantExecutionFlow,
        selectedIntegration: AssistantIntegrationConfig?
    ) async throws -> String {
        indicator.updateProcessingSnapshot(.init(step: .interpretingCommand))
        return try await aiPhase.processWithAI(
            sourceText: sourceText,
            command: command,
            executionFlow: executionFlow,
            selectedIntegration: selectedIntegration
        )
    }

    private func executeDispatch(
        executionFlow: AssistantExecutionFlow,
        finalCommand: String,
        command: String,
        processedCommand: String,
        selectedIntegration: AssistantIntegrationConfig?,
        selectedTextResult: (text: String, snapshot: AssistantTextSelectionService.PasteboardSnapshot)?
    ) async throws {
        indicator.updateProcessingSnapshot(.init(step: .dispatchingResult))
        try await dispatchPhase.executeDispatch(
            executionFlow: executionFlow,
            finalCommand: finalCommand,
            command: command,
            processedCommand: processedCommand,
            selectedIntegration: selectedIntegration,
            selectedTextResult: selectedTextResult
        )
    }

    public func cancelRecording() async {
        guard isRecording || audioRecorder.isRecording else { return }

        await recordingOrchestrator.cancelRecording(currentRecordingURL: currentRecordingURL)
        isRecording = false
        isProcessing = false
        currentExecutionFlow = .assistantMode
        currentRecordingURL = nil
    }

    private func showError(_ error: AssistantVoiceCommandError) {
        indicator.showError(error.localizedDescription)
    }
}
