import Foundation
import MeetingAssistantCoreDomain

@MainActor
extension AppSettingsStore {
    static func normalizedVocabularyReplacementRules(
        _ rules: [VocabularyReplacementRule]
    ) -> [VocabularyReplacementRule] {
        var seenFindValues = Set<String>()
        var ordered: [VocabularyReplacementRule] = []

        for rule in rules {
            let normalizedVariants = rule.normalizedFindVariants.filter { variant in
                seenFindValues.contains(variant.lowercased()) == false
            }
            guard !normalizedVariants.isEmpty else {
                continue
            }

            for variant in normalizedVariants {
                seenFindValues.insert(variant.lowercased())
            }

            ordered.append(
                VocabularyReplacementRule(
                    id: rule.id,
                    find: normalizedVariants.joined(separator: ", "),
                    replace: rule.replace.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }

        return ordered
    }

    static func normalizedVocabularyTerms(_ terms: [VocabularyTerm]) -> [VocabularyTerm] {
        VocabularyTerm.normalized(terms)
    }
}
