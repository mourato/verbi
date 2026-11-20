import Foundation
import VerbiCoreDomain

@MainActor
extension AppSettingsStore {
    static func normalizedVocabularyReplacementRules(
        _ rules: [VocabularyReplacementRule]
    ) -> [VocabularyReplacementRule] {
        VocabularySubstitutionGroup.rules(from: VocabularySubstitutionGroup.groups(from: rules))
    }

    static func normalizedVocabularyTerms(_ terms: [VocabularyTerm]) -> [VocabularyTerm] {
        VocabularyTerm.normalized(terms)
    }
}
