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
/// transcription model: which parameter is used, and which terms the request
/// boundary would send or drop.
///
/// Counts are derived from the same projection functions the request boundary
/// applies, followed by the wire cap the adapters re-apply, so this summary
/// cannot diverge from the request. Term definitions are never sent as hints.
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
            // The adapters re-apply `capGroqPrompt` to the joined `prompt`
            // field, which re-splits saved terms on commas and counts each
            // fragment (with ", " separators) against the character budget.
            // Derive the summary from that final wire string so counting
            // matches the request: a term is used only when all of its
            // fragments fit; partially sent terms are skipped, not counted
            // as complete.
            let wiredPrompt = VocabularyProviderHints.capGroqPrompt(
                snapshot.projectedGroqPrompt()
            ) ?? ""
            var candidate = ""
            var used: [String] = []
            for term in snapshot.terms.map(\.term) {
                let fragments = Self.promptFragments(of: term)
                guard !fragments.isEmpty else {
                    continue
                }
                let contribution = fragments.joined(separator: ", ")
                let nextCandidate = candidate.isEmpty
                    ? contribution
                    : candidate + ", " + contribution
                guard wiredPrompt.hasPrefix(nextCandidate) else {
                    // The wire drops every fragment from here on, so this
                    // term is incomplete (or absent) and later terms follow.
                    break
                }
                used.append(term)
                candidate = nextCandidate
            }
            usedTerms = used
            skippedTerms = Self.skipped(from: snapshot.terms.map(\.term), used: used)
        case .keyterms:
            let used = snapshot.projectedElevenLabsKeyterms()
            usedTerms = used
            skippedTerms = Self.skipped(from: snapshot.terms.map(\.term), used: used)
        }
    }

    /// Comma fragments the Groq/OpenAI wire boundary counts against the
    /// character budget — the same split `VocabularyProviderHints.capGroqPrompt`
    /// applies, so trimming and empties behave identically on both sides.
    private static func promptFragments(of term: String) -> [String] {
        term
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func skipped(from terms: [String], used: [String]) -> [String] {
        let usedSet = Set(used)
        return terms.filter { !usedSet.contains($0) }
    }
}
