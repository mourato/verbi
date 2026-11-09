import Foundation

/// Which parameter carries vocabulary term strings to a speech recognition
/// provider. The per-provider mapping lives beside the provider definition
/// (`TranscriptionProvider.vocabularyHelper` in VerbiCoreInfrastructure);
/// `TranscriptionClient.transcribeConfigured` selects the encoded hints field
/// through that same mapping, so this type owns no wire limits.
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
/// boundary would send, partially send, or drop.
///
/// Counts are derived from the same projection functions the request boundary
/// applies, followed by the wire cap the adapters re-apply, so this summary
/// cannot diverge from the request. Term definitions are never sent as hints.
public struct VocabularyRecognitionSupport: Sendable, Hashable, Equatable {
    /// The recognition parameter the selected provider/model accepts.
    public let parameter: VocabularyRecognitionHelperParameter
    /// Term strings the wire boundary would send as recognition hints.
    public let usedTerms: [String]
    /// Term strings where only part reaches the wire: in prompt mode, the
    /// final comma splitting keeps the fragments that fit the budget and the
    /// rest of the term is cut off.
    public let partiallySentTerms: [String]
    /// Term strings dropped by provider limits or unsupported format —
    /// nothing of them reaches the wire.
    public let skippedTerms: [String]

    /// `true` when recognition hints apply; `false` for local ASR.
    public var usesRecognitionHints: Bool {
        parameter != .none
    }

    public var usedCount: Int {
        usedTerms.count
    }

    public var partiallySentCount: Int {
        partiallySentTerms.count
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
            partiallySentTerms = []
            skippedTerms = snapshot.terms.map(\.term)
        case .prompt:
            // The adapters re-apply `capGroqPrompt` to the joined `prompt`
            // field, which re-splits saved terms on commas and counts each
            // fragment (with ", " separators) against the character budget.
            // Derive the summary from that final wire string so counting
            // matches the request: a term counts as used only when every one
            // of its fragments fits; when only some fragments fit, the term
            // is partially sent; a term absent from the wire — and every
            // term after it — is skipped completely.
            let wiredPrompt = VocabularyProviderHints.capGroqPrompt(
                snapshot.projectedGroqPrompt()
            ) ?? ""
            var candidate = ""
            var used: [String] = []
            var partial: [String] = []
            var skipped: [String] = []
            for term in snapshot.terms.map(\.term) {
                let fragments = Self.promptFragments(of: term)
                guard !fragments.isEmpty else {
                    skipped.append(term)
                    continue
                }
                let fullContribution = fragments.joined(separator: ", ")
                let fullCandidate = candidate.isEmpty
                    ? fullContribution
                    : candidate + ", " + fullContribution
                if wiredPrompt.hasPrefix(fullCandidate) {
                    used.append(term)
                    candidate = fullCandidate
                    continue
                }
                // The wire carries at most a prefix of this term's fragments.
                var prefixCandidate = candidate
                var sentFragments = 0
                for fragment in fragments.dropLast() {
                    let next = prefixCandidate.isEmpty
                        ? fragment
                        : prefixCandidate + ", " + fragment
                    guard wiredPrompt.hasPrefix(next) else { break }
                    sentFragments += 1
                    prefixCandidate = next
                }
                guard sentFragments > 0 else {
                    // Nothing of this term reaches the wire, so nothing after
                    // it does either — every later term stays skipped.
                    skipped.append(term)
                    continue
                }
                partial.append(term)
            }
            usedTerms = used
            partiallySentTerms = partial
            skippedTerms = skipped
        case .keyterms:
            let used = snapshot.projectedElevenLabsKeyterms()
            usedTerms = used
            partiallySentTerms = []
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
