import Combine
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import os.log

// swiftlint:disable file_length type_body_length function_body_length function_parameter_count

// MARK: - Transcription Client

/// Client for communicating with the local FluidAudio transcription service.
/// Adapts the local model manager to the existing client interface.
@MainActor
public class TranscriptionClient: ObservableObject, TranscriptionService, TranscriptionServiceDiarizationOverride, TranscriptionServicePurposeAware, TranscriptionServicePurposeDiarized, TranscriptionServiceFinalDiarization {
    public static let shared = TranscriptionClient()

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "TranscriptionClient")
    private let settingsStore: AppSettingsStore
    private let groqTranscriptionClient: GroqTranscriptionClient
    private let elevenLabsTranscriptionClient: ElevenLabsTranscriptionClient

    public enum CachedReadinessState: String, Sendable {
        case unknown
        case healthy
        case unhealthy
    }

    /// The underlying transcription implementation based on feature flags.
    private enum TranscriptionImplementation {
        case xpc
        case local
    }

    private enum TranscriptionBackend {
        case xpc
        case local
        case groq(modelID: String)
        case elevenLabs(modelID: String)
    }

    private var transcriptionImplementation: TranscriptionImplementation {
        FeatureFlags.useXPCService ? .xpc : .local
    }

    @Published public private(set) var cachedReadinessState: CachedReadinessState = .unknown

    public var supportsIncrementalTranscription: Bool {
        transcriptionImplementation == .local
    }

    public func supportsIncrementalTranscription(for mode: TranscriptionExecutionMode) -> Bool {
        guard transcriptionImplementation == .local else { return false }
        return settingsStore.supportsIncrementalTranscription(for: mode)
    }

    public func supportsIncrementalTranscription(selection: TranscriptionProviderSelection) -> Bool {
        guard transcriptionImplementation == .local, selection.provider == .local else { return false }
        return LocalTranscriptionModel(rawValue: selection.selectedModel)?.supportsIncrementalTranscription ?? false
    }

    /// ponytail: test-only seam; production uses FluidAIModelManager.shared.
    var localASRWarmupLoader: (@MainActor (String) async -> Void)?
    var diarizationWarmupLoader: (@MainActor () async -> Void)?

    init(
        settingsStore: AppSettingsStore = .shared,
        groqTranscriptionClient: GroqTranscriptionClient = GroqTranscriptionClient(),
        elevenLabsTranscriptionClient: ElevenLabsTranscriptionClient = ElevenLabsTranscriptionClient()
    ) {
        self.settingsStore = settingsStore
        self.groqTranscriptionClient = groqTranscriptionClient
        self.elevenLabsTranscriptionClient = elevenLabsTranscriptionClient
    }

    /// Check if the transcription service is healthy.
    public func healthCheck() async throws -> Bool {
        let isHealthy: Bool
        switch transcriptionImplementation {
        case .xpc:
            do {
                let status = try await MeetingAssistantAIClient.shared.fetchServiceStatus()
                isHealthy = status.status == "healthy"
            } catch {
                isHealthy = false
            }
        case .local:
            isHealthy = FluidAIModelManager.shared.modelState == .loaded
        }
        updateCachedReadiness(isHealthy ? .healthy : .unhealthy)
        return isHealthy
    }

    /// Fetch detailed service status.
    public func fetchServiceStatus() async throws -> ServiceStatusResponse {
        switch transcriptionImplementation {
        case .xpc:
            let xpcStatus = try await MeetingAssistantAIClient.shared.fetchServiceStatus()
            updateCachedReadiness(xpcStatus.status == "healthy" ? .healthy : .unhealthy)
            return ServiceStatusResponse(
                status: xpcStatus.status,
                modelState: xpcStatus.modelState,
                modelLoaded: xpcStatus.modelLoaded,
                device: xpcStatus.device,
                modelName: xpcStatus.modelName,
                uptimeSeconds: xpcStatus.uptimeSeconds,
                lastTranscriptionTime: nil,
                totalTranscriptions: 0,
                totalAudioProcessedSeconds: 0
            )
        case .local:
            let state = FluidAIModelManager.shared.modelState
            let meetingModelID = settingsStore.resolvedTranscriptionSelection(for: .meeting).selectedModel
            updateCachedReadiness(state == .loaded ? .healthy : (state == .error ? .unhealthy : .unknown))
            return ServiceStatusResponse(
                status: state == .error ? "unhealthy" : "healthy",
                modelState: state.rawValue,
                modelLoaded: state == .loaded,
                device: "ANE",
                modelName: meetingModelID,
                uptimeSeconds: 0,
                lastTranscriptionTime: nil,
                totalTranscriptions: 0,
                totalAudioProcessedSeconds: 0
            )
        }
    }

    /// Whether the local ASR model for the given id is loaded and ready for incremental transcription.
    public func isLocalASRReady(for modelID: String) -> Bool {
        let manager = FluidAIModelManager.shared
        return manager.modelState == .loaded && manager.loadedASRLocalModelID == modelID
    }

    /// Warm up the transcription model for meeting capture.
    public func warmupModel() async throws {
        try await warmupModel(for: .meeting, configuration: nil)
    }

    /// Purpose-aware warmup for meeting or dictation capture.
    public func warmupModel(
        for executionMode: TranscriptionExecutionMode,
        configuration: DomainTranscriptionRequestConfiguration?
    ) async throws {
        if executionMode == .meeting {
            guard settingsStore.isMeetingTranscriptionEnabled else {
                updateCachedReadiness(.unknown)
                AppLogger.debug(
                    "Skipped model warmup because meeting transcription capability is disabled",
                    category: .transcriptionEngine
                )
                return
            }
        }

        let selection = warmupSelection(for: executionMode, configuration: configuration)

        switch resolvedBackend(for: selection) {
        case .xpc:
            guard executionMode == .meeting else { return }
            do {
                try await MeetingAssistantAIClient.shared.warmupModel()
                updateCachedReadiness(.healthy)
            } catch {
                updateCachedReadiness(.unhealthy)
                throw error
            }
        case .local:
            await loadLocalASRModel(modelID: selection.selectedModel)
            if shouldLoadDiarization(for: executionMode, modelID: selection.selectedModel) {
                await loadDiarizationModelsIfNeeded()
            }
            updateCachedReadiness(FluidAIModelManager.shared.modelState == .loaded ? .healthy : .unhealthy)
        case .groq, .elevenLabs:
            return
        }
    }

    /// Transcribe an audio file.
    public func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> TranscriptionResponse {
        try await transcribe(
            audioURL: audioURL,
            onProgress: onProgress,
            executionMode: .meeting,
            diarizationEnabledOverride: nil
        )
    }

    public func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        capturePurpose: CapturePurpose
    ) async throws -> TranscriptionResponse {
        try await transcribe(
            audioURL: audioURL,
            onProgress: onProgress,
            executionMode: executionMode(for: capturePurpose),
            diarizationEnabledOverride: nil
        )
    }

    public func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        executionMode: TranscriptionExecutionMode
    ) async throws -> TranscriptionResponse {
        try await transcribe(
            audioURL: audioURL,
            onProgress: onProgress,
            executionMode: executionMode,
            diarizationEnabledOverride: nil
        )
    }

    public func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        diarizationEnabledOverride: Bool?
    ) async throws -> TranscriptionResponse {
        try await transcribe(
            audioURL: audioURL,
            onProgress: onProgress,
            executionMode: .meeting,
            diarizationEnabledOverride: diarizationEnabledOverride
        )
    }

    public func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        diarizationEnabledOverride: Bool?,
        capturePurpose: CapturePurpose
    ) async throws -> TranscriptionResponse {
        try await transcribe(
            audioURL: audioURL,
            onProgress: onProgress,
            executionMode: executionMode(for: capturePurpose),
            diarizationEnabledOverride: diarizationEnabledOverride
        )
    }

    public func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        executionMode: TranscriptionExecutionMode,
        diarizationEnabledOverride: Bool?,
        selection: TranscriptionProviderSelection,
        inputLanguageCode: String?,
        vocabularyHints: VocabularyProviderHints?
    ) async throws -> TranscriptionResponse {
        try await transcribeConfigured(
            audioURL: audioURL,
            onProgress: onProgress,
            executionMode: executionMode,
            diarizationEnabledOverride: diarizationEnabledOverride,
            selection: selection,
            inputLanguageCode: inputLanguageCode,
            vocabularyHints: vocabularyHints
        )
    }

    public func transcribe(
        samples: [Float],
        selection: TranscriptionProviderSelection,
        inputLanguageCode: String?,
        vocabularyHints _: VocabularyProviderHints?
    ) async throws -> TranscriptionResponse {
        // Incremental/sample ASR is local-only; provider vocabulary hints are unsupported.
        try await transcribe(samples: samples, inputLanguageCode: inputLanguageCode, selection: selection)
    }

    public func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        executionMode: TranscriptionExecutionMode,
        diarizationEnabledOverride: Bool?,
        configuration: DomainTranscriptionRequestConfiguration
    ) async throws -> TranscriptionResponse {
        guard let provider = MeetingAssistantCoreInfrastructure.TranscriptionProvider(rawValue: configuration.providerID) else {
            throw TranscriptionError.transcriptionFailed("Unsupported transcription provider")
        }
        if provider == .local, LocalTranscriptionModel(rawValue: configuration.modelID) == nil {
            throw TranscriptionError.transcriptionFailed("Unsupported local transcription model")
        }
        return try await transcribeConfigured(
            audioURL: audioURL,
            onProgress: onProgress,
            executionMode: executionMode,
            diarizationEnabledOverride: diarizationEnabledOverride,
            selection: .init(provider: provider, selectedModel: configuration.modelID),
            inputLanguageCode: configuration.inputLanguageCode,
            vocabularyHints: configuration.vocabularyHints
        )
    }

    public func transcribe(
        samples: [Float],
        configuration: DomainTranscriptionRequestConfiguration
    ) async throws -> TranscriptionResponse {
        guard let provider = MeetingAssistantCoreInfrastructure.TranscriptionProvider(rawValue: configuration.providerID) else {
            throw TranscriptionError.transcriptionFailed("Unsupported transcription provider")
        }
        if provider == .local, LocalTranscriptionModel(rawValue: configuration.modelID) == nil {
            throw TranscriptionError.transcriptionFailed("Unsupported local transcription model")
        }
        return try await transcribe(
            samples: samples,
            selection: .init(provider: provider, selectedModel: configuration.modelID),
            inputLanguageCode: configuration.inputLanguageCode,
            vocabularyHints: configuration.vocabularyHints
        )
    }

    private func transcribe(
        samples: [Float],
        inputLanguageCode: String,
        selection: TranscriptionProviderSelection
    ) async throws -> TranscriptionResponse {
        try await transcribe(samples: samples, inputLanguageCode: Optional(inputLanguageCode), selection: selection)
    }

    private func transcribe(
        samples: [Float],
        inputLanguageCode: String?,
        selection: TranscriptionProviderSelection
    ) async throws -> TranscriptionResponse {
        AppLogger.info("Transcribing in-memory samples", category: .transcriptionEngine, extra: ["sampleCount": samples.count])
        guard selection.provider == .local else {
            throw TranscriptionError.transcriptionFailed("Incremental transcription requires a local provider")
        }
        return try await LocalTranscriptionClient.shared.transcribe(
            samples: samples,
            inputLanguageHintCode: inputLanguageCode,
            modelID: selection.selectedModel,
            useSettingsLanguageFallback: false
        )
    }

    public func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        executionMode: TranscriptionExecutionMode,
        diarizationEnabledOverride: Bool?
    ) async throws -> TranscriptionResponse {
        try await transcribeConfigured(
            audioURL: audioURL,
            onProgress: onProgress,
            executionMode: executionMode,
            diarizationEnabledOverride: diarizationEnabledOverride,
            selection: settingsStore.resolvedTranscriptionSelection(for: executionMode),
            inputLanguageCode: settingsStore.resolvedTranscriptionInputLanguageCode(for: executionMode),
            vocabularyHints: nil
        )
    }

    private func transcribeConfigured(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        executionMode: TranscriptionExecutionMode,
        diarizationEnabledOverride: Bool?,
        selection: TranscriptionProviderSelection,
        inputLanguageCode: String?,
        vocabularyHints: VocabularyProviderHints?
    ) async throws -> TranscriptionResponse {
        let backend = resolvedBackend(for: selection)
        let implementationLabel = switch backend {
        case .xpc:
            "XPC"
        case .local:
            "local"
        case .groq:
            "groq"
        case .elevenLabs:
            "elevenlabs"
        }

        // Never log raw vocabulary terms — only whether hints were attached.
        AppLogger.info(
            "Transcribing file",
            category: .transcriptionEngine,
            extra: [
                "filename": audioURL.lastPathComponent,
                "implementation": implementationLabel,
                "mode": executionMode.rawValue,
                "hasVocabularyHints": vocabularyHints.map { !$0.isEmpty } ?? false
            ]
        )

        switch backend {
        case .xpc:
            return try await transcribeViaXPC(
                audioURL: audioURL,
                onProgress: onProgress,
                diarizationEnabledOverride: diarizationEnabledOverride,
                executionMode: executionMode,
                selection: selection,
                inputLanguageCode: inputLanguageCode,
                vocabularyHints: vocabularyHints
            )
        case .local:
            let effectiveDiarizationOverride = localDiarizationOverride(
                for: selection,
                requestedOverride: diarizationEnabledOverride
            )
            return try await transcribeLocally(
                audioURL: audioURL,
                onProgress: onProgress,
                diarizationEnabledOverride: effectiveDiarizationOverride,
                modelID: selection.selectedModel,
                inputLanguageCode: inputLanguageCode,
                useSettingsFallback: false
            )
        case let .groq(modelID):
            return try await transcribeViaGroq(
                audioURL: audioURL,
                modelID: modelID,
                onProgress: onProgress,
                inputLanguageCode: inputLanguageCode,
                vocabularyHint: vocabularyHints?.groqPrompt
            )
        case let .elevenLabs(modelID):
            return try await transcribeViaElevenLabs(
                audioURL: audioURL,
                modelID: modelID,
                onProgress: onProgress,
                inputLanguageCode: inputLanguageCode,
                vocabularyKeyterms: vocabularyHints?.elevenLabsKeyterms ?? []
            )
        }
    }

    public func transcribe(samples: [Float]) async throws -> TranscriptionResponse {
        AppLogger.info(
            "Transcribing in-memory samples",
            category: .transcriptionEngine,
            extra: ["sampleCount": samples.count, "implementation": transcriptionImplementation == .xpc ? "XPC" : "local"]
        )

        guard supportsIncrementalTranscription else {
            updateCachedReadiness(.unhealthy)
            throw TranscriptionError.transcriptionFailed("Incremental transcription unsupported in current backend")
        }

        do {
            let inputLanguageCode = settingsStore.resolvedTranscriptionInputLanguageCode(for: .dictation)
            let response = try await LocalTranscriptionClient.shared.transcribe(
                samples: samples,
                inputLanguageHintCode: inputLanguageCode
            )
            updateCachedReadiness(.healthy)
            return response
        } catch {
            updateCachedReadiness(.unhealthy)
            throw error
        }
    }

    public func diarize(audioURL: URL) async throws -> [SpeakerTimelineSegment] {
        guard transcriptionImplementation == .local else {
            throw TranscriptionError.transcriptionFailed("Final diarization unsupported in current backend")
        }

        do {
            let speakerTimeline = try await LocalTranscriptionClient.shared.diarize(audioURL: audioURL)
            updateCachedReadiness(.healthy)
            return speakerTimeline
        } catch {
            updateCachedReadiness(.unhealthy)
            throw error
        }
    }

    public func assignSpeakers(
        to segments: [Transcription.Segment],
        using speakerTimeline: [SpeakerTimelineSegment]
    ) -> [Transcription.Segment] {
        guard transcriptionImplementation == .local else { return segments }
        return LocalTranscriptionClient.shared.assignSpeakers(
            to: segments,
            using: speakerTimeline
        )
    }

    public func warmupModelIfNeededInBackground() {
        warmupModelIfNeededInBackground(for: .meeting, configuration: nil)
    }

    public func warmupModelIfNeededInBackground(
        for executionMode: TranscriptionExecutionMode,
        configuration: DomainTranscriptionRequestConfiguration?
    ) {
        guard FeatureFlags.enableCachedTranscriptionReadinessGate else { return }

        if executionMode == .meeting {
            guard settingsStore.isMeetingTranscriptionEnabled else { return }
            guard cachedReadinessState != .healthy else { return }
        } else {
            let selection = warmupSelection(for: executionMode, configuration: configuration)
            guard isLocalWarmupBackend(for: selection) else { return }
            guard needsLocalASRWarmup(modelID: selection.selectedModel) else { return }
        }

        Task { @MainActor [weak self] in
            do {
                try await self?.warmupModel(for: executionMode, configuration: configuration)
            } catch {
                self?.logger.error("Background warmup failed: \(error.localizedDescription)")
            }
        }
    }

    private func transcribeViaXPC(
        audioURL: URL,
        onProgress _: (@Sendable (Double) -> Void)?,
        diarizationEnabledOverride: Bool?,
        executionMode: TranscriptionExecutionMode,
        selection: TranscriptionProviderSelection,
        inputLanguageCode: String?,
        vocabularyHints: VocabularyProviderHints?
    ) async throws -> TranscriptionResponse {
        do {
            let response = try await MeetingAssistantAIClient.shared.transcribe(
                audioURL: audioURL,
                diarizationEnabledOverride: diarizationEnabledOverride,
                executionMode: executionMode,
                selection: selection,
                inputLanguageCode: inputLanguageCode,
                vocabularyHints: vocabularyHints
            )
            updateCachedReadiness(.healthy)
            AppLogger.info(
                "Transcription completed via XPC",
                category: .transcriptionEngine,
                extra: ["words": response.text.split(separator: " ").count]
            )
            return response
        } catch {
            updateCachedReadiness(.unhealthy)
            AppLogger.error(
                "Transcription failed via XPC",
                category: .transcriptionEngine,
                error: error,
                extra: ["filename": audioURL.lastPathComponent]
            )
            throw error
        }
    }

    private func transcribeLocally(
        audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        diarizationEnabledOverride: Bool?,
        modelID: String,
        inputLanguageCode: String?,
        useSettingsFallback: Bool = true
    ) async throws -> TranscriptionResponse {
        do {
            let response = try await LocalTranscriptionClient.shared.transcribe(
                audioURL: audioURL,
                isDiarizationEnabled: diarizationEnabledOverride,
                modelID: modelID,
                inputLanguageHintCode: inputLanguageCode,
                useSettingsLanguageFallback: useSettingsFallback,
                useSettingsDiarizationFallback: useSettingsFallback,
                onProgress: onProgress
            )
            updateCachedReadiness(.healthy)
            AppLogger.info(
                "Transcription completed locally",
                category: .transcriptionEngine,
                extra: ["words": response.text.split(separator: " ").count]
            )
            return response
        } catch {
            updateCachedReadiness(.unhealthy)
            AppLogger.error(
                "Transcription failed locally",
                category: .transcriptionEngine,
                error: error,
                extra: ["filename": audioURL.lastPathComponent]
            )
            throw error
        }
    }

    private func transcribeViaGroq(
        audioURL: URL,
        modelID: String,
        onProgress: (@Sendable (Double) -> Void)?,
        inputLanguageCode: String?,
        vocabularyHint: String? = nil
    ) async throws -> TranscriptionResponse {
        do {
            let response = try await groqTranscriptionClient.transcribe(
                audioURL: audioURL,
                modelID: modelID,
                inputLanguageCode: inputLanguageCode,
                onProgress: onProgress,
                vocabularyHint: vocabularyHint
            )
            updateCachedReadiness(.healthy)
            AppLogger.info(
                "Transcription completed via Groq",
                category: .transcriptionEngine,
                extra: [
                    "words": response.text.split(separator: " ").count,
                    "model": response.model,
                    "hasVocabularyPrompt": vocabularyHint.map { !$0.isEmpty } ?? false
                ]
            )
            return response
        } catch {
            updateCachedReadiness(.unhealthy)
            AppLogger.error(
                "Transcription failed via Groq",
                category: .transcriptionEngine,
                error: error,
                extra: ["filename": audioURL.lastPathComponent, "model": modelID]
            )
            throw error
        }
    }

    private func transcribeViaElevenLabs(
        audioURL: URL,
        modelID: String,
        onProgress: (@Sendable (Double) -> Void)?,
        inputLanguageCode: String?,
        vocabularyKeyterms: [String] = []
    ) async throws -> TranscriptionResponse {
        do {
            let response = try await elevenLabsTranscriptionClient.transcribe(
                audioURL: audioURL,
                modelID: modelID,
                inputLanguageCode: inputLanguageCode,
                onProgress: onProgress,
                vocabularyKeyterms: vocabularyKeyterms
            )
            updateCachedReadiness(.healthy)
            AppLogger.info(
                "Transcription completed via ElevenLabs",
                category: .transcriptionEngine,
                extra: [
                    "words": response.text.split(separator: " ").count,
                    "model": response.model,
                    "hasVocabularyKeyterms": !vocabularyKeyterms.isEmpty
                ]
            )
            return response
        } catch {
            updateCachedReadiness(.unhealthy)
            AppLogger.error(
                "Transcription failed via ElevenLabs",
                category: .transcriptionEngine,
                error: error,
                extra: ["filename": audioURL.lastPathComponent, "model": modelID]
            )
            throw error
        }
    }

    private func executionMode(for capturePurpose: CapturePurpose) -> TranscriptionExecutionMode {
        switch capturePurpose {
        case .meeting:
            .meeting
        case .dictation:
            .dictation
        }
    }

    private func resolvedBackend(for selection: TranscriptionProviderSelection) -> TranscriptionBackend {
        switch selection.provider {
        case .local:
            transcriptionImplementation == .xpc ? .xpc : .local
        case .groq:
            .groq(modelID: selection.selectedModel)
        case .elevenLabs:
            .elevenLabs(modelID: selection.selectedModel)
        }
    }

    private func localDiarizationOverride(
        for selection: TranscriptionProviderSelection,
        requestedOverride: Bool?
    ) -> Bool? {
        guard selection.provider == .local else { return requestedOverride }
        guard LocalTranscriptionModel(rawValue: selection.selectedModel)?.supportsDiarization == true else {
            if requestedOverride != false {
                AppLogger.info(
                    "Diarization auto-disabled for selected local transcription model",
                    category: .transcriptionEngine,
                    extra: ["model": selection.selectedModel]
                )
            }
            return false
        }
        return requestedOverride
    }

    private func warmupSelection(
        for executionMode: TranscriptionExecutionMode,
        configuration: DomainTranscriptionRequestConfiguration?
    ) -> TranscriptionProviderSelection {
        if let configuration,
           let provider = MeetingAssistantCoreInfrastructure.TranscriptionProvider(rawValue: configuration.providerID)
        {
            return TranscriptionProviderSelection(provider: provider, selectedModel: configuration.modelID)
        }
        return settingsStore.resolvedTranscriptionSelection(for: executionMode)
    }

    private func isLocalWarmupBackend(for selection: TranscriptionProviderSelection) -> Bool {
        if case .local = resolvedBackend(for: selection) {
            return true
        }
        return false
    }

    private func shouldLoadDiarization(for executionMode: TranscriptionExecutionMode, modelID: String) -> Bool {
        guard executionMode == .meeting else { return false }
        guard FeatureFlags.enableDiarization, settingsStore.isDiarizationEnabled else { return false }
        return settingsStore.localModelSupportsDiarization(modelID: modelID)
    }

    private func needsLocalASRWarmup(modelID: String) -> Bool {
        let manager = FluidAIModelManager.shared
        guard manager.modelState == .loaded,
              manager.loadedASRLocalModelID == modelID
        else {
            return true
        }
        return false
    }

    private func loadLocalASRModel(modelID: String) async {
        if let localASRWarmupLoader {
            await localASRWarmupLoader(modelID)
        } else {
            await FluidAIModelManager.shared.loadModels(for: modelID)
        }
    }

    private func loadDiarizationModelsIfNeeded() async {
        if let diarizationWarmupLoader {
            await diarizationWarmupLoader()
        } else {
            await FluidAIModelManager.shared.loadDiarizationModels()
        }
    }

    private func updateCachedReadiness(_ state: CachedReadinessState) {
        guard FeatureFlags.enableCachedTranscriptionReadinessGate else { return }
        cachedReadinessState = state
    }

    deinit {
        AppLogger.debug("TranscriptionClient deinitialized", category: .transcriptionEngine)
    }
}
