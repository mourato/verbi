import Foundation
import VerbiCoreDomain
import VerbiCoreInfrastructure

/// Policy constants for remote incremental dictation.
///
/// Remote dictation (Groq Whisper and equivalents) transcribes closed VAD
/// speech windows in parallel during speech, hides live preview, and pastes
/// the joined post-processed result once at stop. Meetings and local
/// transcription behavior are unchanged.
enum RemoteIncrementalDictationPolicy {
    /// Dictations shorter than this stay on a single full-file request so
    /// short speech pays no extra request overhead.
    static let shortDictationSingleRequestSeconds = 5.0

    /// Silent recordings at or below this length never reach remote
    /// transcription or AI post-processing.
    static let shortSilenceSkipSeconds = 4.0

    /// Peak amplitude below this counts as silence for the short-silence skip.
    static let silencePeakThreshold: Float = 0.025

    /// RMS below this counts as silence for the short-silence skip.
    static let silenceRMSThreshold: Float = 0.008

    /// Delay before the pill shows `.processing(.transcribing)` so fast
    /// tail finalizations skip a transient main-thread redraw.
    static let transcribingStateDelayNanoseconds: UInt64 = 250_000_000

    static func isRemoteProvider(_ provider: TranscriptionProvider) -> Bool {
        provider.usesRemoteInference
    }
}

/// Thrown when a remote incremental session never crossed the window-dispatch
/// threshold. The stop path treats this as a clean single full-file request,
/// not a transcription failure.
struct RemoteShortDictationSingleRequestError: Error {}

/// Result of a finished incremental dictation session with finalization
/// timings (milliseconds) for the structured latency breakdown.
struct FinishedIncrementalDictation: Sendable {
    let artifact: CaptureArtifact
    let incrementalFinishMs: Int
    let finalizeMs: Int
}

/// Stage timings (milliseconds) for one remote incremental finalization.
/// Carries durations and identifiers only, never speech content.
struct DictationLatencyBreakdown: Sendable {
    var incrementalFinishMs: Int?
    var finalizeMs: Int?
    var deliveryMs: Int?

    var extras: [String: String] {
        var result: [String: String] = [:]
        if let incrementalFinishMs {
            result["incrementalFinishMs"] = String(incrementalFinishMs)
        }
        if let finalizeMs {
            result["finalizeMs"] = String(finalizeMs)
        }
        if let deliveryMs {
            result["deliveryMs"] = String(deliveryMs)
        }
        return result
    }
}
