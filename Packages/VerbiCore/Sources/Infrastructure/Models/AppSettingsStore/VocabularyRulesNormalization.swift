import Foundation
import VerbiCoreDomain

@MainActor
extension AppSettingsStore {
    /// Reads and writes substitution rules in their consolidated shape: one
    /// rule per normalized destination, every origin trimmed and Unicode
    /// composed. Origins that conflict across destinations are preserved so
    /// legacy data never disappears without a visible resolution.
    static func normalizedVocabularyReplacementRules(
        _ rules: [VocabularyReplacementRule]
    ) -> [VocabularyReplacementRule] {
        VocabularySubstitutionGroup.rules(from: VocabularySubstitutionGroup.groups(from: rules))
    }

    static func normalizedVocabularyTerms(_ terms: [VocabularyTerm]) -> [VocabularyTerm] {
        VocabularyTerm.normalized(terms)
    }
}
