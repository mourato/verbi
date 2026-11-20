import Foundation

public struct VocabularyProviderHints: Sendable, Hashable, Codable, Equatable {
    public let groqPrompt: String?
    public let elevenLabsKeyterms: [String]

    public static let groqMaxCharacters = 800
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

    public func enforcingWireLimits() -> VocabularyProviderHints {
        VocabularyProviderHints(
            groqPrompt: Self.capGroqPrompt(groqPrompt),
            elevenLabsKeyterms: Self.capElevenLabsKeyterms(elevenLabsKeyterms)
        )
    }

    public func selecting(parameter: VocabularyRecognitionHelperParameter) -> VocabularyProviderHints? {
        switch parameter {
        case .none:
            nil
        case .prompt:
            VocabularyProviderHints(groqPrompt: groqPrompt, elevenLabsKeyterms: [])
        case .keyterms:
            VocabularyProviderHints(groqPrompt: nil, elevenLabsKeyterms: elevenLabsKeyterms)
        }
    }

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
            guard !value.isEmpty, value.count <= maxCharactersPerTerm, !containsElevenLabsUnsupportedCharacters(value) else { continue }
            result.append(value)
        }
        return result
    }

    private static let elevenLabsUnsupportedCharacters = CharacterSet(charactersIn: "<>{}[]\\")

    private static func containsElevenLabsUnsupportedCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { elevenLabsUnsupportedCharacters.contains($0) }
    }
}

public struct VocabularySnapshot: Codable, Sendable, Hashable, Equatable {
    public let terms: [VocabularyTerm]

    public let replacementRules: [VocabularyReplacementRule]

    public init(terms: [VocabularyTerm], replacementRules: [VocabularyReplacementRule]) {
        self.terms = VocabularyTerm.normalized(terms)
        self.replacementRules = Self.validatedReplacementRules(replacementRules)
    }

    public static let empty = VocabularySnapshot(terms: [], replacementRules: [])

    public var providerHints: VocabularyProviderHints {
        VocabularyProviderHints(
            groqPrompt: projectedGroqPrompt(),
            elevenLabsKeyterms: projectedElevenLabsKeyterms()
        )
    }

    public func projectedGroqPrompt(maxCharacters: Int = VocabularyProviderHints.groqMaxCharacters) -> String? {
        let termStrings = terms.map(\.term).filter { !$0.isEmpty }
        guard !termStrings.isEmpty else { return nil }

        var parts: [String] = []
        var used = 0
        for term in termStrings {
            let separator = parts.isEmpty ? 0 : 2
            let nextLength = used + separator + term.count
            guard nextLength <= maxCharacters else { break }
            parts.append(term)
            used = nextLength
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }

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

    public func prependToContext(_ baseContext: String?) -> String? {
        guard let vocab = postProcessingContext else { return baseContext }
        guard let existing = baseContext,
              !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return vocab
        }
        return vocab + "\n\n" + existing
    }

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

    private static func validatedReplacementRules(
        _ rules: [VocabularyReplacementRule]
    ) -> [VocabularyReplacementRule] {
        rules.filter { !$0.find.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

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
