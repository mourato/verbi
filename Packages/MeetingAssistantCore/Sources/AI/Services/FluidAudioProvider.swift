import Foundation
import MeetingAssistantCoreCommon
import os.log

#if arch(arm64)
    @preconcurrency import FluidAudio

    // MARK: - FluidAudioProvider (Apple Silicon)

    /// TranscriptionProvider implementation using FluidAudio.
    /// Optimized for Apple Silicon Macs with CoreML acceleration.
    ///
    /// This provider wraps the FluidAudio library for high-performance local transcription.
    /// All operations are performed on the MainActor for thread safety since AsrManager
    /// doesn't conform to Sendable.
    @MainActor
    final class FluidAudioProvider: @unchecked Sendable {
        // MARK: - Properties

        let name = "FluidAudio (Apple Silicon)"

        var isAvailable: Bool {
            true
        }

        private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "FluidAudioProvider")
        private var asrManager: AsrManager?
        private(set) var isReady: Bool = false

        // MARK: - Singleton

        static let shared = FluidAudioProvider()

        private init() {}

        // MARK: - Preparation

        /// Prepares the FluidAudio models for transcription.
        /// - Parameter progressHandler: Optional callback for download progress (0.0 to 1.0)
        func prepare(progressHandler _: (@Sendable (Double) -> Void)? = nil) async throws {
            guard !isReady else { return }

            logger.info("Starting FluidAudio model preparation...")

            do {
                // Download and load v3 (Multilingual) models
                let models = try await AsrModels.downloadAndLoad(version: .v3)

                // Initialize AsrManager
                let manager = AsrManager(config: .default)
                try await manager.initialize(models: models)

                asrManager = manager
                isReady = true

                logger.info("FluidAudio models ready")
            } catch {
                logger.error("FluidAudio preparation failed: \(error.localizedDescription)")
                throw TranscriptionProviderError.preparationFailed(error.localizedDescription)
            }
        }

        // MARK: - Transcription

        /// Transcribe audio samples.
        /// - Parameter samples: 16kHz mono PCM float samples
        /// - Returns: Transcription result with text and confidence
        func transcribe(_ samples: [Float]) async throws -> ASRTranscriptionResult {
            guard let manager = asrManager, isReady else {
                throw TranscriptionProviderError.modelNotLoaded
            }

            let result = try await manager.transcribe(samples, source: .microphone)

            let tokenTimings = result.tokenTimings?.map { token in
                ASRTranscriptionResult.TokenTiming(
                    token: token.token,
                    startTime: Double(token.startTime),
                    endTime: Double(token.endTime)
                )
            } ?? []

            return ASRTranscriptionResult(
                text: result.text,
                confidence: result.confidence,
                tokenTimings: tokenTimings
            )
        }

        /// Transcribe audio from a file URL.
        /// - Parameter audioURL: Path to the audio file
        /// - Returns: Transcription result with text and confidence
        func transcribe(audioURL: URL) async throws -> ASRTranscriptionResult {
            guard let manager = asrManager, isReady else {
                throw TranscriptionProviderError.modelNotLoaded
            }

            logger.info("Transcribing file: \(audioURL.lastPathComponent)")

            let result = try await manager.transcribe(audioURL, source: .system)

            let tokenTimings = result.tokenTimings?.map { token in
                ASRTranscriptionResult.TokenTiming(
                    token: token.token,
                    startTime: Double(token.startTime),
                    endTime: Double(token.endTime)
                )
            } ?? []

            return ASRTranscriptionResult(
                text: result.text,
                confidence: result.confidence,
                tokenTimings: tokenTimings
            )
        }

        // MARK: - Model Management

        /// Checks if models exist on disk without loading them.
        func modelsExistOnDisk() -> Bool {
            let baseCacheDir = AsrModels.defaultCacheDirectory().deletingLastPathComponent()
            let v3CacheDir = baseCacheDir.appendingPathComponent("parakeet-tdt-0.6b-v3-coreml")
            return FileManager.default.fileExists(atPath: v3CacheDir.path)
        }

        /// Clears cached models from disk.
        func clearCache() throws {
            let baseCacheDir = AsrModels.defaultCacheDirectory().deletingLastPathComponent()
            let v3CacheDir = baseCacheDir.appendingPathComponent("parakeet-tdt-0.6b-v3-coreml")

            if FileManager.default.fileExists(atPath: v3CacheDir.path) {
                try FileManager.default.removeItem(at: v3CacheDir)
                logger.info("FluidAudio cache cleared")
            }

            isReady = false
            asrManager = nil
        }

        // MARK: - Direct Access

        /// Provides direct access to the underlying AsrManager for advanced use cases.
        var underlyingManager: AsrManager? {
            asrManager
        }
    }

#else

    // MARK: - FluidAudioProvider Stub (Intel)

    /// Stub implementation for Intel Macs where FluidAudio is not available.
    /// FluidAudio requires Apple Silicon for optimal CoreML performance.
    @MainActor
    final class FluidAudioProvider: @unchecked Sendable {
        let name = "FluidAudio (Apple Silicon Only)"
        var isAvailable: Bool {
            false
        }

        var isReady: Bool {
            false
        }

        static let shared = FluidAudioProvider()

        private init() {}

        func prepare(progressHandler _: (@Sendable (Double) -> Void)?) throws {
            throw TranscriptionProviderError.unsupportedPlatform
        }

        func transcribe(_: [Float]) throws -> ASRTranscriptionResult {
            throw TranscriptionProviderError.unsupportedPlatform
        }

        func transcribe(audioURL _: URL) throws -> ASRTranscriptionResult {
            throw TranscriptionProviderError.unsupportedPlatform
        }

        func modelsExistOnDisk() -> Bool {
            false
        }

        func clearCache() throws {
            // No-op on Intel
        }
    }

#endif
