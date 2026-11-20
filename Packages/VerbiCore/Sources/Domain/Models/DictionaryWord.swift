import Foundation

public struct DictionaryWord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let word: String
    public let heardAs: [String]
    public let termID: UUID?
    public let groupID: UUID?

    public init(id: UUID, word: String, heardAs: [String], termID: UUID?, groupID: UUID?) {
        self.id = id
        self.word = word
        self.heardAs = heardAs
        self.termID = termID
        self.groupID = groupID
    }

    public var isTextRemoval: Bool {
        word.isEmpty
    }

    public var wordKey: String {
        VocabularyNormalization.destinationKey(word)
    }

    public static func words(
        terms: [VocabularyTerm],
        rules: [VocabularyReplacementRule]
    ) -> [DictionaryWord] {
        let groups = VocabularySubstitutionGroup.groups(from: rules)

        var termOwner: [UUID: UUID] = [:]
        var groupTermID: [UUID: UUID] = [:]
        for group in groups {
            for term in terms where termOwner[term.id] == nil {
                if VocabularyNormalization.destinationKey(term.term) == group.destinationKey {
                    termOwner[term.id] = group.id
                    groupTermID[group.id] = term.id
                    break
                }
            }
        }

        var result: [DictionaryWord] = groups.map { group in
            DictionaryWord(
                id: group.id,
                word: group.destination,
                heardAs: group.origins,
                termID: groupTermID[group.id],
                groupID: group.id
            )
        }

        for term in terms where termOwner[term.id] == nil {
            let spelling = VocabularyNormalization.spelling(term.term)
            guard !spelling.isEmpty else { continue }
            result.append(
                DictionaryWord(
                    id: term.id,
                    word: spelling,
                    heardAs: [],
                    termID: term.id,
                    groupID: nil
                )
            )
        }

        let words = result.filter { !$0.isTextRemoval }.sorted {
            $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending
        }
        let removals = result.filter(\.isTextRemoval).sorted {
            ($0.heardAs.first ?? "").localizedCaseInsensitiveCompare($1.heardAs.first ?? "")
                == .orderedAscending
        }
        return words + removals
    }
}
