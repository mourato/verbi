import Foundation

/// Which parameter carries vocabulary term strings to a speech recognition
/// provider. The per-provider mapping lives beside the provider definition
/// (`TranscriptionProvider.vocabularyHelper` in VerbiCoreInfrastructure) and
/// mirrors the routing in `TranscriptionClient.transcribeConfigured`; this
/// type owns no wire limits.
public enum VocabularyRecognitionHelperParameter: String, Sendable, Hashable {
    /// Local FluidAudio ASR has no vocabulary parameter.
    case none
    /// Whisper-compatible `prompt` field (Groq and OpenAI audio transcription).
    case prompt
    /// ElevenLabs Scribe repeated `keyterms` fields.
    case keyterms
}

/// A truthful summary of how the saved vocabulary reaches one selected
/// transcription model: which parameter is used, and which terms the same
/// projection functions that build the wire request would send or drop.
///
/// Counts are derived exclusively from `VocabularySnapshot` projections, so
/// this summary cannot diverge from the request boundary. Term definitions
/// are never sent as hints.
public struct VocabularyRecognitionSupport: Sendable, Hashable, Equatable {
    /// The recognition parameter the selected provider/model accepts.
    public let parameter: VocabularyRecognitionHelperParameter
    /// Term strings the wire boundary would send as recognition hints.
    public let usedTerms: [String]
    /// Term strings dropped by provider limits or unsupported format.
    public let skippedTerms: [String]

    /// `true` when recognition hints apply; `false` for local ASR.
    public var usesRecognitionHints: Bool {
        parameter != .none
    }

    public var usedCount: Int {
        usedTerms.count
    }

    public var skippedCount: Int {
        skippedTerms.count
    }

    /// Derives the summary with the same limits the request boundary applies.
    public init(
        parameter: VocabularyRecognitionHelperParameter,
        snapshot: VocabularySnapshot
    ) {
        self.parameter = parameter

        switch parameter {
        case .none:
            // Local (including incremental) ASR receives no hints.
            usedTerms = []
            skippedTerms = snapshot.terms.map(\.term)
        case .prompt:
            // Re-caps the prompt with the same helper the request boundary
            // applies to the `prompt` field, then reads back the terms.
            let prompt = snapshot.projectedGroqPrompt() ?? ""
            // Count saved entries, not comma-delimited fragments of a term.
            var used: [String] = []
            var prefix = ""
            for term in snapshot.terms.map(\.term) {
                let candidate = prefix.isEmpty ? term : prefix + ", " + term
                guard prompt.hasPrefix(candidate) else { break }
                used.append(term)
                prefix = candidate
            }
            usedTerms = used
            skippedTerms = Self.skipped(from: snapshot.terms.map(\.term), used: used)
        case .keyterms:
            let used = snapshot.projectedElevenLabsKeyterms()
            usedTerms = used
            skippedTerms = Self.skipped(from: snapshot.terms.map(\.term), used: used)
        }
    }

    private static func skipped(from terms: [String], used: [String]) -> [String] {
        let usedSet = Set(used)
        return terms.filter { !usedSet.contains($0) }
    }
}
