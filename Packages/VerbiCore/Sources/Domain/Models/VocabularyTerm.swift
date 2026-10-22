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

    /// Trims values, drops empty terms, deduplicates case-insensitively (first wins),
    /// and returns a deterministic display order.
    public static func normalized(_ terms: [VocabularyTerm]) -> [VocabularyTerm] {
        var seenKeys = Set<String>()
        var ordered: [VocabularyTerm] = []

        for term in terms {
            let trimmedTerm = term.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTerm.isEmpty else { continue }

            let key = trimmedTerm.lowercased()
            guard seenKeys.insert(key).inserted else { continue }

            ordered.append(
                VocabularyTerm(
                    id: term.id,
                    term: trimmedTerm,
                    definition: term.definition.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }

        return ordered.sorted()
    }
}

extension VocabularyTerm: Comparable {
    public static func < (lhs: VocabularyTerm, rhs: VocabularyTerm) -> Bool {
        lhs.term.localizedCaseInsensitiveCompare(rhs.term) == .orderedAscending
    }
}
