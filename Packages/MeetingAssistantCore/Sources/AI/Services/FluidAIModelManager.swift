@preconcurrency import AVFoundation
import Combine
@preconcurrency import FluidAudio
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import os.log

/// Manages the lifecycle of FluidAudio models (Download, Load, Initialize).
@MainActor
public protocol AIModelService: ObservableObject {
    var modelState: FluidAIModelManager.ModelState { get }
    var modelStatePublisher: AnyPublisher<FluidAIModelManager.ModelState, Never> { get }
    var downloadPhase: FluidAIModelManager.DownloadPhase { get }
    var lastError: String? { get }
    func loadModels() async
    func loadDiarizationModels() async
    func retryFailedModels() async
}

/// Manages the lifecycle of FluidAudio models (Download, Load, Initialize).
@MainActor
public class FluidAIModelManager: ObservableObject, AIModelService {
    public static let shared = FluidAIModelManager()

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "FluidAIModelManager")

    @Published public var modelState: ModelState = .unloaded
    public var modelStatePublisher: AnyPublisher<ModelState, Never> {
        $modelState.eraseToAnyPublisher()
    }

    @Published public var progress: Double = 0.0

    @Published public var isASRInstalled: Bool = false
    @Published public var isDiarizationLoaded: Bool = false
    @Published public private(set) var loadedASRLocalModelID: String?
    @Published public private(set) var lastRequestedASRLocalModelID: String?
    @Published public private(set) var lastASRActivityAt: Date?
    @Published public private(set) var lastDiarizationActivityAt: Date?

    public var isASRInUse: Bool {
        asrInFlightOperationCount > 0
    }

    public var isDiarizationInUse: Bool {
        diarizationInFlightOperationCount > 0
    }

    public var isASRResidentInMemory: Bool {
        hasLoadedASRRuntime && modelState == .loaded
    }

    public var isDiarizationResidentInMemory: Bool {
        diarizerManager != nil
    }

    private(set) var asrManager: AsrManager?
    private(set) var diarizerManager: OfflineDiarizerManager?
    private var asrInFlightOperationCount = 0
    private var diarizationInFlightOperationCount = 0

    private var hasLoadedASRRuntime: Bool {
        asrManager != nil
    }

    public enum ModelState: String, Sendable {
        case unloaded
        case downloading
        case loading
        case loaded
        case error
    }

    /// Detailed phase tracking for UI progress feedback
    public enum DownloadPhase: Equatable, Sendable {
        case idle
        case downloadingASR
        case loadingASR
        case downloadingDiarization
        case loadingDiarization
        case ready
        case failed(String)

        public var isInProgress: Bool {
            switch self {
            case .downloadingASR, .loadingASR, .downloadingDiarization, .loadingDiarization:
                true
            default:
                false
            }
        }

        public var localizedDescription: String {
            switch self {
            case .idle:
                "settings.ai.phase_idle".localized
            case .downloadingASR:
                "settings.ai.downloading_asr".localized
            case .loadingASR:
                "settings.ai.loading_asr".localized
            case .downloadingDiarization:
                "settings.ai.downloading_diarization".localized
            case .loadingDiarization:
                "settings.ai.loading_diarization".localized
            case .ready:
                "settings.ai.models_ready".localized
            case let .failed(error):
                "settings.ai.download_failed".localized(with: error)
            }
        }
    }

    @Published public var downloadPhase: DownloadPhase = .idle
    @Published public var lastError: String?

    private init() {
        refreshInstalledModelStates()
    }

    /// Loads the ASR models. Downloads them if not present.
    public func loadModels() async {
        let meetingSelection = AppSettingsStore.shared.resolvedTranscriptionSelection(for: .meeting)
        await loadModels(for: meetingSelection.selectedModel)
    }

    /// Loads the ASR models for a specific local model ID.
    public func loadModels(for localModelID: String) async {
        let requestedModel = resolveLocalModel(from: localModelID)

        guard modelState != .downloading, modelState != .loading else { return }
        if modelState == .loaded,
           hasLoadedASRRuntime,
           loadedASRLocalModelID == requestedModel.rawValue
        {
            return
        }

        lastRequestedASRLocalModelID = requestedModel.rawValue
        modelState = .downloading
        downloadPhase = .downloadingASR
        lastError = nil
        logger.info("Starting model download/load for local ASR model: \(requestedModel.rawValue, privacy: .public)")

        do {
            modelState = .loading
            downloadPhase = .loadingASR
            logger.info("Initializing local ASR runtime for model: \(requestedModel.rawValue, privacy: .public)")

            switch requestedModel {
            case .parakeetTdt06BV3:
                // Model deserialization and Core ML compilation must not run on the MainActor during capture.
                let manager = try await Task.detached(priority: .userInitiated) {
                    let models = try await Self.loadASRModels(for: requestedModel)
                    let manager = AsrManager(config: .default)
                    try await manager.initialize(models: models)
                    return manager
                }.value
                asrManager = manager
            }

            loadedASRLocalModelID = requestedModel.rawValue
            modelState = .loaded
            isASRInstalled = isASRModelInstalled(localModelID: requestedModel.rawValue)
            recordASRActivity()
            updateReadyState()
            logger.info("Local ASR runtime initialized successfully.")

        } catch {
            let errorMessage = error.localizedDescription
            logger.error("Failed to load models: \(errorMessage)")
            modelState = .error
            downloadPhase = .failed(errorMessage)
            lastError = errorMessage
        }
    }

    /// Unified retry method that attempts to load failed components.
    public func retryFailedModels() async {
        if case .failed = downloadPhase {
            // Check if ASR is missing or failed
            if modelState == .error || modelState == .unloaded {
                await loadModels()
            }

            // If ASR is ready or just loaded successfully, and diarization is still failing/missing
            if modelState == .loaded || modelState == .loading, !isDiarizationLoaded {
                await loadDiarizationModels()
            }
        }
    }

    /// Loads the Diarization models.
    /// Public version without parameters for protocol conformance.
    public func loadDiarizationModels() async {
        await loadDiarizationModels(
            minSpeakers: nil,
            maxSpeakers: nil,
            numSpeakers: nil
        )
    }

    /// Loads the Diarization models with optional speaker constraints.
    func loadDiarizationModels(
        minSpeakers: Int? = nil,
        maxSpeakers: Int? = nil,
        numSpeakers: Int? = nil
    ) async {
        let min = minSpeakers ?? AppSettingsStore.shared.minSpeakers
        let max = maxSpeakers ?? AppSettingsStore.shared.maxSpeakers
        let num = numSpeakers ?? AppSettingsStore.shared.numSpeakers

        // Check if we already have a manager with these same constraints
        if diarizerManager != nil,
           currentDiarizerMinSpeakers == min,
           currentDiarizerMaxSpeakers == max,
           currentDiarizerNumSpeakers == num
        {
            // Already loaded with same constraints, ensure phase reflects ready state
            if downloadPhase != .ready {
                updateReadyState()
            }
            return
        }

        downloadPhase = .downloadingDiarization
        lastError = nil
        logger.info("Loading Diarization models with constraints: min=\(min ?? 0), max=\(max ?? 0), num=\(num ?? 0)...")

        do {
            var config = OfflineDiarizerConfig()
                .withSpeakers(min: min, max: max)

            if let num {
                config = config.withSpeakers(exactly: num)
            }

            let manager = OfflineDiarizerManager(config: config)

            downloadPhase = .loadingDiarization
            try await manager.prepareModels()

            diarizerManager = manager
            currentDiarizerMinSpeakers = min
            currentDiarizerMaxSpeakers = max
            currentDiarizerNumSpeakers = num

            isDiarizationLoaded = true
            lastDiarizationActivityAt = Date()
            updateReadyState()

            logger.info("Diarization Manager initialized successfully.")
        } catch {
            let errorMessage = error.localizedDescription
            logger.error("Failed to load diarization models: \(errorMessage)")
            isDiarizationLoaded = false
            downloadPhase = .failed(errorMessage)
            lastError = errorMessage
        }
    }

    private func updateReadyState() {
        let isDiarizationEnabled = AppSettingsStore.shared.isDiarizationEnabled
        if modelState == .loaded, !isDiarizationEnabled || isDiarizationLoaded {
            downloadPhase = .ready
        }
    }

    /// Deletes the downloaded ASR models from disk and unloads from memory.
    public func deleteASRModels() {
        LocalTranscriptionModel.allCases.forEach { deleteASRModels(for: $0.rawValue) }
    }

    /// Deletes a specific downloaded ASR model from disk and unloads it from memory if needed.
    public func deleteASRModels(for localModelID: String) {
        let requestedModel = resolveLocalModel(from: localModelID)
        guard modelState != .downloading, modelState != .loading else { return }

        let isLoadedModel = loadedASRLocalModelID == requestedModel.rawValue
        guard !isLoadedModel || !isASRInUse else {
            logger.warning("Skipped ASR model deletion because transcription is currently in progress.")
            return
        }

        if isLoadedModel {
            asrManager = nil
            loadedASRLocalModelID = nil
            modelState = .unloaded
            lastASRActivityAt = nil

            if downloadPhase == .ready {
                downloadPhase = .idle
            }
        }

        do {
            try removeASRModelFromDisk(requestedModel)
            logger.info("Deleted ASR model: \(requestedModel.rawValue, privacy: .public)")
        } catch {
            logger.error("Failed to delete ASR models: \(error.localizedDescription)")
        }

        refreshInstalledModelStates()
    }

    /// Deletes the downloaded diarization models from disk and unloads from memory.
    public func deleteDiarizationModels() {
        guard !isDiarizationInUse else {
            logger.warning("Skipped diarization model deletion because diarization is currently in progress.")
            return
        }

        // Unload from memory
        diarizerManager = nil
        currentDiarizerMinSpeakers = nil
        currentDiarizerMaxSpeakers = nil
        currentDiarizerNumSpeakers = nil
        isDiarizationLoaded = false
        lastDiarizationActivityAt = nil

        // Remove from disk
        let fileManager = FileManager.default
        guard let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let modelsDir = supportDir.appendingPathComponent("FluidAudio/Models")

        do {
            if fileManager.fileExists(atPath: modelsDir.path) {
                let contents = try fileManager.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: nil)
                for url in contents {
                    // Safe heuristic: delete known Diarization model folders (pyannote)
                    if url.lastPathComponent.contains("pyannote") || url.lastPathComponent.contains("segmentation") {
                        try fileManager.removeItem(at: url)
                        logger.info("Deleted Diarization model: \(url.lastPathComponent)")
                    }
                }
            }
        } catch {
            logger.error("Failed to delete Diarization models: \(error.localizedDescription)")
        }
    }

    /// Refreshes model installation flags based on in-memory managers and local disk contents.
    public func refreshInstalledModelStates() {
        if hasLoadedASRRuntime {
            isASRInstalled = true
        } else {
            isASRInstalled = hasASRModelsOnDisk()
        }

        if diarizerManager != nil {
            isDiarizationLoaded = true
        } else {
            isDiarizationLoaded = hasDiarizationModelsOnDisk()
        }
    }

    @discardableResult
    public func unloadASRFromMemoryIfPossible() -> Bool {
        guard hasLoadedASRRuntime else { return false }
        guard !isASRInUse else { return false }
        guard modelState != .downloading, modelState != .loading else { return false }

        asrManager = nil
        loadedASRLocalModelID = nil
        modelState = .unloaded
        if downloadPhase == .ready {
            downloadPhase = .idle
        }
        refreshInstalledModelStates()
        logger.info("Unloaded ASR model from RAM due to inactivity.")
        return true
    }

    @discardableResult
    public func unloadDiarizationFromMemoryIfPossible() -> Bool {
        guard diarizerManager != nil else { return false }
        guard !isDiarizationInUse else { return false }

        diarizerManager = nil
        currentDiarizerMinSpeakers = nil
        currentDiarizerMaxSpeakers = nil
        currentDiarizerNumSpeakers = nil
        if downloadPhase == .ready {
            downloadPhase = .idle
        }
        refreshInstalledModelStates()
        logger.info("Unloaded diarization model from RAM due to inactivity.")
        return true
    }

    private var currentDiarizerMinSpeakers: Int?
    private var currentDiarizerMaxSpeakers: Int?
    private var currentDiarizerNumSpeakers: Int?

    private func recordASRActivity() {
        lastASRActivityAt = Date()
        LocalModelResidencyCoordinator.shared.noteASRActivity()
    }
}

extension FluidAIModelManager {
    /// Structure to hold raw diarization result
    struct DiarizationSegment: Identifiable {
        let id = UUID()
        let speakerId: String
        let startTime: Double
        let endTime: Double
    }

    /// Perform speaker diarization on an audio file
    func diarize(
        audioURL: URL,
        minSpeakers: Int? = nil,
        maxSpeakers: Int? = nil,
        numSpeakers: Int? = nil
    ) async throws -> [DiarizationSegment] {
        lastDiarizationActivityAt = Date()
        diarizationInFlightOperationCount += 1
        defer { diarizationInFlightOperationCount = max(0, diarizationInFlightOperationCount - 1) }

        await loadDiarizationModels(
            minSpeakers: minSpeakers,
            maxSpeakers: maxSpeakers,
            numSpeakers: numSpeakers
        )

        guard let manager = diarizerManager else {
            throw FluidError.diarizerNotLoaded
        }

        logger.info("Diarizing audio file: \(audioURL.path)")

        let result = try await manager.process(audioURL)

        return result.segments.map { segment in
            DiarizationSegment(
                speakerId: String(segment.speakerId),
                startTime: Double(segment.startTimeSeconds),
                endTime: Double(segment.endTimeSeconds)
            )
        }
    }

    /// Structure to hold ASR segment (text + timing)
    struct AsrSegment {
        let text: String
        let startTime: Double
        let endTime: Double
    }

    struct AsrTranscriptionOutput {
        let text: String
        let segments: [AsrSegment]
        let confidenceScore: Double?
    }

    /// Transcribe audio from a URL.
    func transcribe(
        audioURL: URL,
        inputLanguageHintCode: String? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> AsrTranscriptionOutput {
        recordASRActivity()
        guard modelState == .loaded, let loadedASRLocalModelID else {
            throw FluidError.modelNotLoaded
        }
        let loadedModel = resolveLocalModel(from: loadedASRLocalModelID)

        asrInFlightOperationCount += 1
        defer { asrInFlightOperationCount = max(0, asrInFlightOperationCount - 1) }

        logger.info("Transcribing audio file: \(audioURL.path)")

        switch loadedModel {
        case .parakeetTdt06BV3:
            if let inputLanguageHintCode, !inputLanguageHintCode.isEmpty {
                logger.info(
                    "ASR language hint requested: \(inputLanguageHintCode) (FluidAudio currently auto-detects language)"
                )
            }

            guard let manager = asrManager else {
                throw FluidError.modelNotLoaded
            }

            let stream = await manager.transcriptionProgressStream
            let progressTask = Task {
                if let progress {
                    do {
                        for try await p in stream {
                            progress(p * 100.0)
                        }
                    } catch {
                        // Keep transcription resilient when progress stream fails.
                    }
                }
            }
            defer { progressTask.cancel() }

            let result = try await manager.transcribe(audioURL, source: .system)

            let mappedSegments = (result.tokenTimings ?? []).compactMap { (token: Any) -> AsrSegment? in
                guard let timing = token as? TokenTiming else { return nil }
                return AsrSegment(
                    text: timing.token,
                    startTime: Double(timing.startTime),
                    endTime: Double(timing.endTime)
                )
            }

            return AsrTranscriptionOutput(
                text: result.text,
                segments: mappedSegments,
                confidenceScore: Double(result.confidence)
            )
        }
    }

    func transcribe(
        samples: [Float],
        inputLanguageHintCode: String? = nil
    ) async throws -> AsrTranscriptionOutput {
        recordASRActivity()
        guard modelState == .loaded, let loadedASRLocalModelID else {
            throw FluidError.modelNotLoaded
        }
        let loadedModel = resolveLocalModel(from: loadedASRLocalModelID)

        asrInFlightOperationCount += 1
        defer { asrInFlightOperationCount = max(0, asrInFlightOperationCount - 1) }

        logger.info("Transcribing in-memory audio samples: \(samples.count)")

        switch loadedModel {
        case .parakeetTdt06BV3:
            if let inputLanguageHintCode, !inputLanguageHintCode.isEmpty {
                logger.info(
                    "ASR language hint requested: \(inputLanguageHintCode) (FluidAudio currently auto-detects language)"
                )
            }

            guard let manager = asrManager else {
                throw FluidError.modelNotLoaded
            }

            let result = try await manager.transcribe(samples, source: .microphone)

            let mappedSegments = (result.tokenTimings ?? []).map { timing in
                AsrSegment(
                    text: timing.token,
                    startTime: Double(timing.startTime),
                    endTime: Double(timing.endTime)
                )
            }

            return AsrTranscriptionOutput(
                text: result.text,
                segments: mappedSegments,
                confidenceScore: Double(result.confidence)
            )
        }
    }

    private func convertTo16kHz(buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false
            )
        else {
            throw FluidError.conversionFailed
        }

        if buffer.format.sampleRate == 16000, buffer.format.channelCount == 1 {
            return buffer
        }

        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            throw FluidError.conversionFailed
        }

        let targetFrameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate
        )

        guard
            let targetBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat, frameCapacity: targetFrameCapacity
            )
        else {
            throw FluidError.conversionFailed
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: targetBuffer, error: &error, withInputFrom: inputBlock)

        if let error {
            throw error
        }

        return targetBuffer
    }

    private func arrayFloat(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let channelPointer = channelData[0]
        return Array(UnsafeBufferPointer(start: channelPointer, count: Int(buffer.frameLength)))
    }
}

enum FluidError: Error {
    case modelNotLoaded
    case diarizerNotLoaded
    case audioReadFailed
    case conversionFailed
}
