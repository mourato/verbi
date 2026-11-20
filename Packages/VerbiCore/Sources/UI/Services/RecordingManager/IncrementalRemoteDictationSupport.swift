import Foundation
import VerbiCoreDomain
import VerbiCoreInfrastructure

enum RemoteIncrementalDictationPolicy {
    static let shortDictationSingleRequestSeconds = 5.0

    static let shortSilenceSkipSeconds = 4.0

    static let silencePeakThreshold: Float = 0.025

    static let silenceRMSThreshold: Float = 0.008

    static let transcribingStateDelayNanoseconds: UInt64 = 250_000_000
}

struct RemoteShortDictationSingleRequestError: Error {}

struct FinishedIncrementalDictation: Sendable {
    let artifact: CaptureArtifact
    let incrementalFinishMs: Int
    let finalizeMs: Int
}

struct DictationLatencyBreakdown: Sendable {
    var incrementalFinishMs: Int?
    var finalizeMs: Int?
    var deliveryMs: Int?

    var extras: [String: Int] {
        var result: [String: Int] = [:]
        if let incrementalFinishMs {
            result["incrementalFinishMs"] = incrementalFinishMs
        }
        if let finalizeMs {
            result["finalizeMs"] = finalizeMs
        }
        if let deliveryMs {
            result["deliveryMs"] = deliveryMs
        }
        return result
    }
}
