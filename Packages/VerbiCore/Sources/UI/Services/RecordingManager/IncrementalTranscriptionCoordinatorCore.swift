@preconcurrency import AVFoundation
import Foundation
import VerbiCoreAI
import VerbiCoreAudio
import VerbiCoreCommon
import VerbiCoreData
import VerbiCoreDomain
@preconcurrency import VerbiCoreInfrastructure

actor IncrementalTranscriptionCoordinatorCore {
    struct Configuration: @unchecked Sendable {
        let transcriptionID: UUID
        let meeting: CaptureSession
        let inputSource: String?
        let storage: any StorageService
        let transcriptionClientBox: RecordingManager.UncheckedTranscriptionServiceBox
        let voiceActivityKernel: any VoiceActivityKernel
        let onPreviewTextChanged: (@Sendable (String) -> Void)?
        let onProcessedDurationChanged: @Sendable (Double) -> Void
        let fallbackLogMessage: String
        let holdBuffersUntilASRReady: Bool
        let asrWarmup: (@Sendable () async -> Void)?
        let isRemote: Bool
        let suppressLivePreview: Bool
        let remoteDispatchThresholdSeconds: Double
        var executionProvenance: ExecutionProvenance?
    }

    private let executionProvenance: ExecutionProvenance?
    private let transcriptionID: UUID
    private let meeting: CaptureSession
    private let inputSource: String?
    private let storage: any StorageService
    private let transcriptionClientBox: RecordingManager.UncheckedTranscriptionServiceBox
    private let voiceActivityKernel: any VoiceActivityKernel
    private let onPreviewTextChanged: (@Sendable (String) -> Void)?
    private let onProcessedDurationChanged: @Sendable (Double) -> Void
    private let fallbackLogMessage: String
    private let holdBuffersUntilASRReady: Bool
    private let asrWarmup: (@Sendable () async -> Void)?
    private let isRemote: Bool
    private let suppressLivePreview: Bool
    private let remoteBatcher: IncrementalRemoteWindowBatcher?
    private let createdAt: Date

    private enum ASRReadyGateConstants {
        static let maxQueuedSecondsBeforeReady = 3.0
    }

    private var isASRReady = true
    private var pendingBufferBoxes: [RecordingManager.SendableIncrementalAudioBufferBox] = []
    private var queuedFramesBeforeReady = 0
    private var queuedSampleRateBeforeReady: Double = 0
    private var asrWarmupTask: Task<Void, Never>?

    private var accumulatedRawText = ""
    private var accumulatedSegments: [CaptureArtifact.Segment] = []
    private var language = "auto"
    private var modelName = "parakeet-tdt-0.6b-v3-coreml"
    private var processedDurationSeconds: Double = 0
    private var confidenceScores: [Double] = []
    private var hasPersistedCheckpoint = false
    private var isHighLoadModeEnabled = false
    private(set) var requiresLegacyFallback = false
    private(set) var fallbackError: Error?
    private(set) var fallbackReason: IncrementalTranscriptionFallbackReason?

    init(configuration: Configuration) {
        executionProvenance = configuration.executionProvenance
        transcriptionID = configuration.transcriptionID
        meeting = configuration.meeting
        inputSource = configuration.inputSource
        storage = configuration.storage
        transcriptionClientBox = configuration.transcriptionClientBox
        voiceActivityKernel = configuration.voiceActivityKernel
        onPreviewTextChanged = configuration.onPreviewTextChanged
        onProcessedDurationChanged = configuration.onProcessedDurationChanged
        fallbackLogMessage = configuration.fallbackLogMessage
        holdBuffersUntilASRReady = configuration.holdBuffersUntilASRReady
        asrWarmup = configuration.asrWarmup
        isRemote = configuration.isRemote
        suppressLivePreview = configuration.suppressLivePreview
        remoteBatcher = configuration.isRemote
            ? IncrementalRemoteWindowBatcher(dispatchThresholdSeconds: configuration.remoteDispatchThresholdSeconds)
            : nil
        createdAt = Date()
        isASRReady = !configuration.holdBuffersUntilASRReady
    }

    var checkpointID: UUID {
        transcriptionID
    }

    var currentSegments: [CaptureArtifact.Segment] {
        accumulatedSegments
    }

    var wallClockElapsedSeconds: Double {
        max(0, Date().timeIntervalSince(createdAt))
    }

    var hasAccumulatedContent: Bool {
        !accumulatedRawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || accumulatedSegments.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var isRemoteSession: Bool {
        isRemote
    }

    func dispatchedRemoteWindowCount() async -> Int {
        await remoteBatcher?.dispatchedWindowCount ?? 0
    }

    func start() async throws {
        try await persistCheckpoint(lifecycleState: .partial)
        if holdBuffersUntilASRReady {
            isASRReady = asrWarmup == nil
        }
    }

    func beginASRWarmupIfNeeded() {
        guard holdBuffersUntilASRReady else { return }
        guard let asrWarmup else {
            isASRReady = true
            return
        }
        guard asrWarmupTask == nil else { return }

        isASRReady = false
        asrWarmupTask = Task {
            defer {
                Task {
                    await self.setASRReady(true)
                }
            }
            await asrWarmup()
        }
    }

    func setASRReady(_ ready: Bool) async {
        guard holdBuffersUntilASRReady else { return }
        guard ready else {
            isASRReady = false
            return
        }

        isASRReady = true
        asrWarmupTask?.cancel()
        asrWarmupTask = nil
        await flushPendingBufferBoxes()
    }

    func append(bufferBox: RecordingManager.SendableIncrementalAudioBufferBox) async {
        guard !requiresLegacyFallback else { return }

        if holdBuffersUntilASRReady, !isASRReady {
            await enqueueBeforeReady(bufferBox)
            return
        }

        await processBufferBox(bufferBox)
    }

    func setHighLoadMode(_ isHighLoad: Bool) async {
        guard isHighLoadModeEnabled != isHighLoad else { return }
        isHighLoadModeEnabled = isHighLoad

        let mode: RealtimeVoiceActivityWindowAssembler.AdaptiveQualityMode = if isHighLoad {
            .reduced
        } else {
            .normal
        }
        await voiceActivityKernel.setAdaptiveQualityMode(mode)
    }

    func finishAccumulation() async throws {
        if let fallbackError {
            throw fallbackError
        }

        await releaseASRReadyGateForShutdown()

        do {
            let windows = try await voiceActivityKernel.finish()
            for window in windows {
                try await transcribe(window: window)
            }
            try await drainRemoteWindowsInOrder()
        } catch {
            if error is RemoteShortDictationSingleRequestError {
                throw error
            }
            if !requiresLegacyFallback {
                await markForLegacyFallback(error, reason: .assemblerFailed)
            }
            throw error
        }

        if let fallbackError {
            throw fallbackError
        }

        try await ensureAccumulatedTranscriptionContent()
    }

    func buildFinalizedResponse(
        segmentsOverride: [CaptureArtifact.Segment]? = nil
    ) async throws -> DomainTranscriptionResponse {
        if let segmentsOverride {
            accumulatedSegments = segmentsOverride
        }

        try await persistCheckpoint(lifecycleState: .finalizing)

        return DomainTranscriptionResponse(
            text: accumulatedRawText,
            segments: accumulatedSegments.map { segment in
                DomainTranscriptionSegment(
                    id: segment.id,
                    speaker: segment.speaker,
                    text: segment.text,
                    startTime: segment.startTime,
                    endTime: segment.endTime
                )
            },
            language: language,
            durationSeconds: processedDurationSeconds,
            model: modelName,
            processedAt: ISO8601DateFormatter().string(from: Date()),
            confidenceScore: mergedConfidenceScore
        )
    }

    func cancelAndDiscard() async {
        asrWarmupTask?.cancel()
        asrWarmupTask = nil
        await remoteBatcher?.cancelAll()
        pendingBufferBoxes = []
        queuedFramesBeforeReady = 0
        queuedSampleRateBeforeReady = 0
        fallbackError = CancellationError()
        requiresLegacyFallback = true
        if hasPersistedCheckpoint {
            try? await storage.deleteTranscription(by: transcriptionID)
        }
    }

    func markForLegacyFallback(
        _ error: Error,
        reason: IncrementalTranscriptionFallbackReason
    ) async {
        guard !requiresLegacyFallback else { return }
        requiresLegacyFallback = true
        fallbackError = error
        fallbackReason = reason
        AppLogger.warning(
            fallbackLogMessage,
            category: .recordingManager,
            extra: [
                "reason": reason.rawValue,
                "error": error.localizedDescription,
                "isRateLimited": RemoteWindowAudioSupport.isRateLimited(error) ? "true" : "false"
            ]
        )
        try? await persistCheckpoint(lifecycleState: .finalizing)
    }

    private func enqueueBeforeReady(_ bufferBox: RecordingManager.SendableIncrementalAudioBufferBox) async {
        let buffer = bufferBox.buffer
        let sampleRate = buffer.format.sampleRate
        guard sampleRate > 0 else {
            pendingBufferBoxes.append(bufferBox)
            return
        }
        if queuedSampleRateBeforeReady <= 0 {
            queuedSampleRateBeforeReady = sampleRate
        }
        let referenceRate = queuedSampleRateBeforeReady
        let incomingFrames = if sampleRate == referenceRate {
            Int(buffer.frameLength)
        } else {
            Int((Double(buffer.frameLength) * referenceRate / sampleRate).rounded(.down))
        }
        let frameBudget = Int(ASRReadyGateConstants.maxQueuedSecondsBeforeReady * referenceRate)
        if queuedFramesBeforeReady + incomingFrames > frameBudget {
            await markForLegacyFallback(
                TranscriptionError.transcriptionFailed("ASR ready queue overflow"),
                reason: .assemblerFailed
            )
            return
        }

        pendingBufferBoxes.append(bufferBox)
        queuedFramesBeforeReady += incomingFrames
    }

    private func flushPendingBufferBoxes() async {
        guard !pendingBufferBoxes.isEmpty else { return }

        let pending = pendingBufferBoxes
        pendingBufferBoxes = []
        queuedFramesBeforeReady = 0
        queuedSampleRateBeforeReady = 0

        for bufferBox in pending {
            await processBufferBox(bufferBox)
        }
    }

    private func releaseASRReadyGateForShutdown() async {
        asrWarmupTask?.cancel()
        asrWarmupTask = nil
        if holdBuffersUntilASRReady, !isASRReady {
            isASRReady = true
            await flushPendingBufferBoxes()
        }
    }

    private func processBufferBox(_ bufferBox: RecordingManager.SendableIncrementalAudioBufferBox) async {
        guard !requiresLegacyFallback else { return }
        if let failure = await remoteBatcher?.currentFailure {
            await markForLegacyFallback(failure, reason: .windowTranscriptionFailed)
            return
        }

        do {
            let windows = try await voiceActivityKernel.append(buffer: bufferBox.buffer)
            for window in windows {
                try await transcribe(window: window)
            }
        } catch {
            if !requiresLegacyFallback {
                await markForLegacyFallback(error, reason: .assemblerFailed)
            }
        }
    }

    private func transcribe(window: RealtimeVoiceActivityWindowAssembler.Window) async throws {
        guard !window.samples.isEmpty else { return }

        if isRemote {
            await ingestRemoteWindow(window)
            return
        }

        do {
            let response = try await transcriptionClientBox.transcribe(samples: window.samples)
            append(
                response: response,
                absoluteWindowStartTime: window.startTime,
                absoluteWindowEndTime: window.endTime
            )
            try await persistCheckpoint(lifecycleState: .partial)
        } catch {
            await markForLegacyFallback(error, reason: .windowTranscriptionFailed)
            throw error
        }
    }

    private func ingestRemoteWindow(_ window: RealtimeVoiceActivityWindowAssembler.Window) async {
        guard let remoteBatcher else { return }
        let clientBox = transcriptionClientBox
        if let failure = await remoteBatcher.ingest(
            samples: window.samples,
            startTime: window.startTime,
            endTime: window.endTime,
            transcribe: { samples in
                try await clientBox.transcribe(samples: samples)
            }
        ) {
            await markForLegacyFallback(failure, reason: .windowTranscriptionFailed)
        }
    }

    private func drainRemoteWindowsInOrder() async throws {
        guard let remoteBatcher else { return }
        let completed: [IncrementalRemoteWindowBatcher.CompletedWindow]
        do {
            completed = try await remoteBatcher.drainOrdered()
        } catch {
            if error is RemoteShortDictationSingleRequestError {
                throw error
            }
            await markForLegacyFallback(error, reason: .windowTranscriptionFailed)
            throw error
        }
        for window in completed {
            append(
                response: window.response,
                absoluteWindowStartTime: window.startTime,
                absoluteWindowEndTime: window.endTime
            )
            try await persistCheckpoint(lifecycleState: .partial)
        }
    }

    private func append(
        response: TranscriptionResponse,
        absoluteWindowStartTime: Double,
        absoluteWindowEndTime: Double
    ) {
        let trimmedText = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
            if accumulatedRawText.isEmpty {
                accumulatedRawText = trimmedText
            } else {
                accumulatedRawText += " \(trimmedText)"
            }
        }

        let mappedSegments = if response.segments.isEmpty, !trimmedText.isEmpty {
            [
                CaptureArtifact.Segment(
                    speaker: CaptureArtifact.unknownSpeaker,
                    text: trimmedText,
                    startTime: absoluteWindowStartTime,
                    endTime: absoluteWindowEndTime
                )
            ]
        } else {
            response.segments.map { segment in
                CaptureArtifact.Segment(
                    id: segment.id,
                    speaker: segment.speaker,
                    text: segment.text,
                    startTime: absoluteWindowStartTime + segment.startTime,
                    endTime: absoluteWindowStartTime + segment.endTime
                )
            }
        }

        accumulatedSegments.append(contentsOf: mappedSegments)
        language = response.language
        modelName = response.model
        processedDurationSeconds = max(processedDurationSeconds, absoluteWindowEndTime)
        if let confidence = response.confidenceScore {
            confidenceScores.append(confidence)
        }

        if !suppressLivePreview {
            onPreviewTextChanged?(accumulatedRawText)
        }
        onProcessedDurationChanged(processedDurationSeconds)
    }

    private func persistCheckpoint(lifecycleState: TranscriptionLifecycleState) async throws {
        let checkpoint = CaptureArtifact(
            id: transcriptionID,
            meeting: meeting,
            contextItems: [],
            segments: accumulatedSegments,
            text: accumulatedRawText,
            rawText: accumulatedRawText,
            processedContent: nil,
            canonicalSummary: nil,
            qualityProfile: nil,
            postProcessingPromptId: nil,
            postProcessingPromptTitle: nil,
            language: language,
            createdAt: createdAt,
            modelName: modelName,
            inputSource: inputSource,
            transcriptionDuration: processedDurationSeconds,
            postProcessingDuration: 0,
            postProcessingModel: nil,
            meetingType: nil,
            lifecycleState: lifecycleState,
            meetingConversationState: nil,
            executionProvenance: executionProvenance
        )
        try await storage.saveTranscription(checkpoint)
        hasPersistedCheckpoint = true
    }

    private var mergedConfidenceScore: Double? {
        guard !confidenceScores.isEmpty else { return nil }
        return confidenceScores.reduce(0, +) / Double(confidenceScores.count)
    }

    private func ensureAccumulatedTranscriptionContent() async throws {
        if !accumulatedRawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }

        let hasSegmentText = accumulatedSegments.contains {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !hasSegmentText else { return }

        let error = TranscriptionError.transcriptionFailed(
            PostProcessingError.emptyTranscription.localizedDescription
        )
        await markForLegacyFallback(error, reason: .emptyTranscript)
        throw error
    }
}
