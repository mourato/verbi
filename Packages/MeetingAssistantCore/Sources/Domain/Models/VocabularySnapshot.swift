import Foundation

/// Provider-specific vocabulary projections for remote ASR APIs.
///
/// Term **definitions** are intentionally omitted from provider hints — only
/// the term strings themselves are sent as recognition bias.
public struct VocabularyProviderHints: Sendable, Hashable, Codable, Equatable {
    public let groqPrompt: String?
    public let elevenLabsKeyterms: [String]

    /// Conservative Groq Whisper `prompt` character budget (~224 tokens).
    public static let groqMaxCharacters = 800
    /// ElevenLabs Scribe v2 batch keyterm limits (official docs).
    public static let elevenLabsMaxTerms = 1000
    public static let elevenLabsMaxCharactersPerTerm = 50

    public init(groqPrompt: String?, elevenLabsKeyterms: [String]) {
        self.groqPrompt = groqPrompt
        self.elevenLabsKeyterms = elevenLabsKeyterms
    }

    public var isEmpty: Bool {
        let hasPrompt = groqPrompt.map { !$0.isEmpty } ?? false
        return !hasPrompt && elevenLabsKeyterms.isEmpty
    }

    public static let empty = VocabularyProviderHints(groqPrompt: nil, elevenLabsKeyterms: [])

    /// Re-applies provider limits for defense-in-depth at the wire boundary.
    public func enforcingWireLimits() -> VocabularyProviderHints {
        VocabularyProviderHints(
            groqPrompt: Self.capGroqPrompt(groqPrompt),
            elevenLabsKeyterms: Self.capElevenLabsKeyterms(elevenLabsKeyterms)
        )
    }

    /// Caps an already-joined Groq prompt to whole comma-separated terms.
    public static func capGroqPrompt(
        _ prompt: String?,
        maxCharacters: Int = groqMaxCharacters
    ) -> String? {
        guard let prompt else { return nil }
        let terms = prompt
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return nil }

        var parts: [String] = []
        var used = 0
        for term in terms {
            let separator = parts.isEmpty ? 0 : 2
            let nextLength = used + separator + term.count
            guard nextLength <= maxCharacters else { break }
            parts.append(term)
            used = nextLength
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }

    /// Caps ElevenLabs keyterms to documented length/count and unsupported-character rules.
    public static func capElevenLabsKeyterms(
        _ keyterms: [String],
        maxTerms: Int = elevenLabsMaxTerms,
        maxCharactersPerTerm: Int = elevenLabsMaxCharactersPerTerm
    ) -> [String] {
        var result: [String] = []
        result.reserveCapacity(min(keyterms.count, maxTerms))
        for raw in keyterms {
            guard result.count < maxTerms else { break }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            guard value.count <= maxCharactersPerTerm else { continue }
            guard !containsElevenLabsUnsupportedCharacters(value) else { continue }
            result.append(value)
        }
        return result
    }

    private static let elevenLabsUnsupportedCharacters = CharacterSet(charactersIn: "<>{}[]\\")

    private static func containsElevenLabsUnsupportedCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { elevenLabsUnsupportedCharacters.contains($0) }
    }
}

/// An immutable snapshot of vocabulary state captured at session start.
///
/// Captures both vocabulary terms (for provider-side hints) and replacement rules
/// (for deterministic post-hoc substitution). Using a snapshot ensures that
/// mid-recording dictionary changes do not affect the current session.
///
/// ## Provider capability matrix (2026-07-16)
///
/// Sources: Groq OpenAI-compatible Whisper `prompt`; ElevenLabs Scribe v2
/// [keyterm prompting](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/batch/keyterm-prompting)
/// (`keyterms`, max 1000 terms × 50 chars). Remote providers receive term
/// strings only (definitions omitted). Terms leave the device for Groq or
/// ElevenLabs ASR hints, and also when remote AI enhancement receives the
/// escaped `<VOCABULARY>` post-processing block.
///
/// | Provider | Vocabulary hint via | Supported? | Parameter | Notes |
/// |---|---|---|---|---|
/// | Groq (Whisper) | `prompt` field | ✅ Supported | `prompt` | ~224-token budget; projected to ~800 chars locally |
/// | ElevenLabs (Scribe v2) | `keyterms` array | ✅ Supported | `keyterms` | Max 1000 terms, 50 chars each; terms leave device |
/// | Local FluidAudio | ASR parameter | ❌ Unsupported | N/A | No vocabulary/hint API on `AsrManager.transcribe()` |
/// | XPC local | ASR parameter | ❌ Unsupported | N/A | Same local FluidAudio surface via XPC |
/// | Incremental samples | In-memory ASR | ❌ Unsupported | N/A | Local-only path; provider hints never applied |
public struct VocabularySnapshot: Codable, Sendable, Hashable, Equatable {
    /// Vocabulary terms for provider-side recognition hints (normalized once).
    public let terms: [VocabularyTerm]

    /// Replacement rules for deterministic post-hoc text substitution.
    /// Expected to already be normalized by settings; empty finds are dropped.
    public let replacementRules: [VocabularyReplacementRule]

    public init(terms: [VocabularyTerm], replacementRules: [VocabularyReplacementRule]) {
        self.terms = VocabularyTerm.normalized(terms)
        self.replacementRules = Self.validatedReplacementRules(replacementRules)
    }

    /// An empty snapshot — no terms and no replacement rules.
    public static let empty = VocabularySnapshot(terms: [], replacementRules: [])

    /// Provider projections built from the normalized term list.
    public var providerHints: VocabularyProviderHints {
        VocabularyProviderHints(
            groqPrompt: projectedGroqPrompt(),
            elevenLabsKeyterms: projectedElevenLabsKeyterms()
        )
    }

    /// Projects terms into a Groq Whisper `prompt` under a conservative character budget.
    /// Whole terms only — stops before exceeding `maxCharacters`.
    public func projectedGroqPrompt(maxCharacters: Int = VocabularyProviderHints.groqMaxCharacters) -> String? {
        let termStrings = terms.map(\.term).filter { !$0.isEmpty }
        guard !termStrings.isEmpty else { return nil }

        var parts: [String] = []
        var used = 0
        for term in termStrings {
            let separator = parts.isEmpty ? 0 : 2 // ", "
            let nextLength = used + separator + term.count
            guard nextLength <= maxCharacters else { break }
            parts.append(term)
            used = nextLength
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }

    /// Projects terms into ElevenLabs `keyterms`.
    ///
    /// Terms longer than `maxCharactersPerTerm` are **skipped** (not truncated)
    /// to avoid sending partial keyterms that could bias incorrectly. Terms
    /// containing ElevenLabs-unsupported characters (`<>{}[]\`) are also skipped.
    /// Cap at `maxTerms` (documented batch limit: 1000).
    public func projectedElevenLabsKeyterms(
        maxTerms: Int = VocabularyProviderHints.elevenLabsMaxTerms,
        maxCharactersPerTerm: Int = VocabularyProviderHints.elevenLabsMaxCharactersPerTerm
    ) -> [String] {
        VocabularyProviderHints.capElevenLabsKeyterms(
            terms.map(\.term),
            maxTerms: maxTerms,
            maxCharactersPerTerm: maxCharactersPerTerm
        )
    }

    /// Prepends this snapshot's vocabulary context block to the base
    /// post-processing context, separated by a blank line. Returns the
    /// base context unchanged when there are no vocabulary terms.
    public func prependToContext(_ baseContext: String?) -> String? {
        guard let vocab = postProcessingContext else { return baseContext }
        guard let existing = baseContext,
              !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return vocab
        }
        return vocab + "\n\n" + existing
    }

    /// Composes a delimited vocabulary context block for enhancement models.
    /// Instructs the model to prefer these specific spellings without
    /// inventing content. Returns `nil` when there are no terms.
    public var postProcessingContext: String? {
        let termStrings = terms.map(\.term).filter { !$0.isEmpty }
        guard !termStrings.isEmpty else { return nil }

        let escapedList = termStrings
            .map { Self.escapeTermForPostProcessing($0) }
            .map { "\"\($0)\"" }
            .joined(separator: ", ")

        return """
        <VOCABULARY>
        The user has defined the following vocabulary terms. Prefer these specific \
        spellings and forms when they appear in the transcript. Do not invent \
        content or apply these terms outside their natural context.
        Terms: \(escapedList)
        </VOCABULARY>
        """
    }

    // MARK: - Private helpers

    private static func validatedReplacementRules(
        _ rules: [VocabularyReplacementRule]
    ) -> [VocabularyReplacementRule] {
        rules.filter { !$0.find.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Strips control characters, neutralizes vocabulary delimiter tags, and escapes quotes.
    private static func escapeTermForPostProcessing(_ term: String) -> String {
        let withoutControls = String(
            term.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        )
        let withoutDelimiterTags = withoutControls
            .replacingOccurrences(of: "</VOCABULARY>", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "<VOCABULARY>", with: "", options: .caseInsensitive)
        return withoutDelimiterTags
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
