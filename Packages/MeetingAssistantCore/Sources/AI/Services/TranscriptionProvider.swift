import Foundation

// MARK: - Transcription Result

/// Unified result type for ASR transcription across all providers.
/// Provides a consistent interface regardless of the underlying transcription engine.
struct ASRTranscriptionResult {
    let text: String
    let confidence: Float
    let tokenTimings: [TokenTiming]

    /// Represents timing information for a single token/word.
    struct TokenTiming {
        let token: String
        let startTime: Double
        let endTime: Double
    }

    init(text: String, confidence: Float = 1.0, tokenTimings: [TokenTiming] = []) {
        self.text = text
        self.confidence = confidence
        self.tokenTimings = tokenTimings
    }
}

// MARK: - Transcription Provider Protocol

/// Protocol that abstracts speech-to-text transcription.
/// Implementations can use different backends (FluidAudio, Apple Speech, etc.)
protocol TranscriptionProvider: AnyObject, Sendable {
    /// Display name of the provider
    var name: String { get }

    /// Whether this provider is available on the current system
    var isAvailable: Bool { get }

    /// Whether models are downloaded and ready
    var isReady: Bool { get }

    /// Download/prepare models for transcription
    /// - Parameter progressHandler: Optional callback for download progress (0.0 to 1.0)
    func prepare(progressHandler: ((Double) -> Void)?) async throws

    /// Transcribe audio samples
    /// - Parameter samples: 16kHz mono PCM float samples
    /// - Returns: Transcription result with text and confidence
    func transcribe(_ samples: [Float]) async throws -> ASRTranscriptionResult

    /// Transcribe audio from a file URL
    /// - Parameter audioURL: Path to the audio file
    /// - Returns: Transcription result with text and confidence
    func transcribe(audioURL: URL) async throws -> ASRTranscriptionResult

    /// Check if models exist on disk (without loading them)
    func modelsExistOnDisk() -> Bool

    /// Clear cached models
    func clearCache() async throws
}

// MARK: - Default Implementations

extension TranscriptionProvider {
    func modelsExistOnDisk() -> Bool {
        false
    }

    func clearCache() throws {
        // Default: no-op
    }

    func transcribe(_: [Float]) throws -> ASRTranscriptionResult {
        throw TranscriptionProviderError.methodNotSupported("Sample-based transcription")
    }

    func transcribe(audioURL _: URL) throws -> ASRTranscriptionResult {
        throw TranscriptionProviderError.methodNotSupported("URL-based transcription")
    }
}

// MARK: - Provider Errors

/// Errors that can occur during transcription provider operations.
enum TranscriptionProviderError: LocalizedError {
    case providerNotAvailable(String)
    case modelNotLoaded
    case preparationFailed(String)
    case transcriptionFailed(String)
    case methodNotSupported(String)
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case let .providerNotAvailable(name):
            "Transcription provider '\(name)' is not available on this system."
        case .modelNotLoaded:
            "Transcription model is not loaded. Call prepare() first."
        case let .preparationFailed(reason):
            "Failed to prepare transcription model: \(reason)"
        case let .transcriptionFailed(reason):
            "Transcription failed: \(reason)"
        case let .methodNotSupported(method):
            "Method '\(method)' is not supported by this provider."
        case .unsupportedPlatform:
            "This transcription provider is not supported on your platform."
        }
    }
}

// MARK: - Architecture Detection

/// Utility to detect the current CPU architecture.
/// Used to determine which transcription providers are available.
enum CPUArchitecture {
    case appleSilicon
    case intel

    static var current: CPUArchitecture {
        #if arch(arm64)
            return .appleSilicon
        #else
            return .intel
        #endif
    }

    static var isAppleSilicon: Bool {
        current == .appleSilicon
    }

    static var isIntel: Bool {
        current == .intel
    }
}
