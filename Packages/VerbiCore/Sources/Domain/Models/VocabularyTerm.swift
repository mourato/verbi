import Foundation

/// A vocabulary term with its definition, used for recognition/spelling hints
/// during transcription. Comma-separated bulk input is supported during entry;
/// each term is stored as a single unit.
public struct VocabularyTerm: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var term: String
    public var definition: String

    public init(id: UUID = UUID(), term: String, definition: String) {
        self.id = id
        self.term = term
        self.definition = definition
    }

    /// Trims outer whitespace, composes canonically equivalent Unicode, drops
    /// empty terms, deduplicates case-insensitively (first spelling wins), and
    /// returns a deterministic display order.
    public static func normalized(_ terms: [VocabularyTerm]) -> [VocabularyTerm] {
        var seenKeys = Set<String>()
        var ordered: [VocabularyTerm] = []

        for term in terms {
            let normalizedTerm = VocabularyNormalization.spelling(term.term)
            guard !normalizedTerm.isEmpty else { continue }

            let key = VocabularyNormalization.termKey(normalizedTerm)
            guard seenKeys.insert(key).inserted else { continue }

            ordered.append(
                VocabularyTerm(
                    id: term.id,
                    term: normalizedTerm,
                    definition: VocabularyNormalization.spelling(term.definition)
                )
            )
        }

        return ordered.sorted()
    }

    /// Returns `terms` with `rawTerm` appended as a recognition hint when it is
    /// non-empty and not already present. Empty or duplicate input leaves the
    /// list untouched so callers can report whether a term was added.
    public static func adding(_ rawTerm: String, to terms: [VocabularyTerm]) -> [VocabularyTerm] {
        let normalizedTerm = VocabularyNormalization.spelling(rawTerm)
        guard !normalizedTerm.isEmpty else { return terms }

        let key = VocabularyNormalization.termKey(normalizedTerm)
        guard !terms.contains(where: { VocabularyNormalization.termKey($0.term) == key }) else {
            return terms
        }

        return normalized(terms + [VocabularyTerm(term: normalizedTerm, definition: "")])
    }

    /// The unified hint list for transcription and AI spelling context: every
    /// saved term plus one derived term per non-removal substitution
    /// destination. Saved terms come first, so they win the case-insensitive
    /// deduplication. Derived terms carry the group id, keeping the snapshot
    /// deterministic. Definitions are never sent as hints.
    public static func hints(
        savedTerms: [VocabularyTerm],
        replacementRules: [VocabularyReplacementRule]
    ) -> [VocabularyTerm] {
        let derived = VocabularySubstitutionGroup.groups(from: replacementRules)
            .filter { !$0.isTextRemoval }
            .map { VocabularyTerm(id: $0.id, term: $0.destination, definition: "") }
        return normalized(savedTerms + derived)
    }
}

extension VocabularyTerm: Comparable {
    public static func < (lhs: VocabularyTerm, rhs: VocabularyTerm) -> Bool {
        let comparison = lhs.term.localizedCaseInsensitiveCompare(rhs.term)
        if comparison == .orderedSame {
            return lhs.term < rhs.term
        }
        return comparison == .orderedAscending
    }
}
