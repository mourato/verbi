import Foundation

/// One dictionary word: the spelling Verbi should write, with the wrong
/// spellings ("heard as") that correct to it.
///
/// This is a read projection over the two persisted sources —
/// `VocabularyTerm` (saved words) and `VocabularyReplacementRule` (heard-as
/// variants). A term joins the group whose `destinationKey` equals the term's
/// destination key (case-sensitive, like destinations today); otherwise it
/// stands alone as a word without variants. Nothing is migrated: writing goes
/// through the view model back to the same two sources.
public struct DictionaryWord: Identifiable, Equatable, Sendable {
    /// `groupID ?? termID`.
    public let id: UUID
    /// The spelling Verbi should write. Empty means a text-removal line.
    public let word: String
    /// The group's origins, or `[]` for a word without variants.
    public let heardAs: [String]
    /// The saved term that belongs to this line, if any.
    public let termID: UUID?
    /// The substitution group this line edits, if any.
    public let groupID: UUID?

    public init(id: UUID, word: String, heardAs: [String], termID: UUID?, groupID: UUID?) {
        self.id = id
        self.word = word
        self.heardAs = heardAs
        self.termID = termID
        self.groupID = groupID
    }

    /// `true` when the line deletes matched text instead of replacing it.
    public var isTextRemoval: Bool {
        word.isEmpty
    }

    /// Case-sensitive identity of the word, matching destination identity.
    public var wordKey: String {
        VocabularyNormalization.destinationKey(word)
    }

    /// Projects saved terms and replacement rules into one ordered word list:
    /// words alphabetically (`localizedCaseInsensitiveCompare`), then removal
    /// lines ordered by their first variant.
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
