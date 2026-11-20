import Combine
import Foundation
import VerbiCoreDomain
import VerbiCoreInfrastructure

@MainActor
public final class VocabularySettingsViewModel: ObservableObject {
    public enum ValidationError: Equatable {
        case emptyWordAndHeardAs
        case emptyHeardAs
        case duplicateWord(String)
        case originConflict
        case saveFailed
    }

    public enum QuickTeachOutcome: Equatable {
        case saved
        case invalid
        case conflicts
        case failed(VocabularyTeachError)
    }

    public struct OriginConflict: Identifiable, Equatable, Sendable {
        public let origin: String
        public let destination: String

        public init(origin: String, destination: String) {
            self.origin = origin
            self.destination = destination
        }

        public var id: String {
            "\(VocabularyNormalization.originKey(origin))→\(VocabularyNormalization.destinationKey(destination))"
        }
    }

    @Published public var showWordEditor = false
    @Published public var editingWord: DictionaryWord?
    @Published public var showWordDeleteConfirmation = false
    @Published public var wordToDelete: DictionaryWord?
    @Published public var editorValidationError: ValidationError?
    @Published public private(set) var pendingConflicts: [OriginConflict] = []
    @Published public private(set) var hasPendingQuickMove = false

    private struct PendingSave {
        let origins: [String]
        let destination: String
        let isQuickTeach: Bool
        let pendingWord: DictionaryWord?
    }

    private let settings: AppSettingsStore
    private let quickTeachStore: DictionaryPersistenceStore
    private var pendingSave: PendingSave?
    private var pendingQuickMovedOriginKeys: Set<String>?
    private var cancellables = Set<AnyCancellable>()

    public init(
        settings: AppSettingsStore = .shared,
        quickTeachStore: DictionaryPersistenceStore? = nil
    ) {
        self.settings = settings
        self.quickTeachStore = quickTeachStore ?? settings

        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public var words: [DictionaryWord] {
        DictionaryWord.words(
            terms: settings.vocabularyTerms,
            rules: settings.vocabularyReplacementRules
        )
    }

    public var groups: [VocabularySubstitutionGroup] {
        VocabularySubstitutionGroup.groups(from: settings.vocabularyReplacementRules)
    }

    public var conflictingOriginKeys: Set<String> {
        VocabularySubstitutionGroup.conflictingOriginKeys(in: settings.vocabularyReplacementRules)
    }

    public var conflictingOriginCount: Int {
        conflictingOriginKeys.count
    }

    public func startCreatingWord() {
        editingWord = nil
        clearEditorState()
        showWordEditor = true
    }

    public func startEditingWord(_ word: DictionaryWord) {
        editingWord = word
        clearEditorState()
        showWordEditor = true
    }

    public func dismissWordEditor() {
        clearEditorState()
        editingWord = nil
        showWordEditor = false
    }

    @discardableResult
    public func saveWord(word rawWord: String, heardAs rawHeardAs: String) -> Bool {
        let word = VocabularyNormalization.spelling(rawWord)
        let heardAs = VocabularyReplacementRule.normalizedVariants(from: rawHeardAs)

        guard !word.isEmpty || !heardAs.isEmpty else {
            editorValidationError = .emptyWordAndHeardAs
            return false
        }

        if !word.isEmpty, let duplicate = duplicateWordError(word: word, heardAs: heardAs) {
            editorValidationError = duplicate
            return false
        }

        let destinationKey = VocabularyNormalization.destinationKey(word)
        let conflicts = conflicts(
            forOriginKeys: Set(heardAs.map(VocabularyNormalization.originKey)),
            destinationKey: destinationKey,
            excludingGroupID: editingWord?.groupID
        )

        guard conflicts.isEmpty else {
            pendingConflicts = conflicts
            pendingSave = PendingSave(
                origins: heardAs,
                destination: word,
                isQuickTeach: false,
                pendingWord: editingWord
            )
            editorValidationError = .originConflict
            return false
        }

        return persistWord(word: word, heardAs: heardAs, editingWord: editingWord)
    }

    @discardableResult
    public func saveQuickTeach(
        origins rawOrigins: String,
        destination rawDestination: String
    ) -> QuickTeachOutcome {
        let origins = VocabularyReplacementRule.normalizedVariants(from: rawOrigins)
        guard !origins.isEmpty else {
            editorValidationError = .emptyHeardAs
            return .invalid
        }

        let destination = VocabularyNormalization.spelling(rawDestination)

        if let save = pendingSave,
           save.isQuickTeach,
           let movingOriginKeys = pendingQuickMovedOriginKeys
        {
            if save.origins == origins, save.destination == destination {
                return persistQuickTeach(
                    origins: origins,
                    destination: destination,
                    movingOriginKeys: movingOriginKeys
                )
            }

            cancelQuickTeachDraft()
        } else if pendingSave?.isQuickTeach == true {
            cancelQuickTeachDraft()
        }

        let destinationKey = VocabularyNormalization.destinationKey(destination)
        let conflicts = conflicts(
            forOriginKeys: Set(origins.map(VocabularyNormalization.originKey)),
            destinationKey: destinationKey
        )

        guard conflicts.isEmpty else {
            pendingConflicts = conflicts
            pendingSave = PendingSave(
                origins: origins,
                destination: destination,
                isQuickTeach: true,
                pendingWord: nil
            )
            editorValidationError = .originConflict
            return .conflicts
        }

        return persistQuickTeach(
            origins: origins,
            destination: destination,
            movingOriginKeys: []
        )
    }

    @discardableResult
    public func stageQuickTeachConflictMove() -> Bool {
        guard let save = pendingSave, save.isQuickTeach, !pendingConflicts.isEmpty else {
            return false
        }

        pendingQuickMovedOriginKeys = Set(pendingConflicts.map { VocabularyNormalization.originKey($0.origin) })
        pendingConflicts = []
        editorValidationError = nil
        hasPendingQuickMove = true
        return true
    }

    public func cancelQuickTeachDraft() {
        pendingConflicts = []
        pendingSave = nil
        pendingQuickMovedOriginKeys = nil
        hasPendingQuickMove = false
        editorValidationError = nil
    }

    @discardableResult
    public func resolveOriginConflictsByMoving() -> Bool {
        guard let save = pendingSave, !save.isQuickTeach, !pendingConflicts.isEmpty else { return false }

        let movingOriginKeys = Set(pendingConflicts.map { VocabularyNormalization.originKey($0.origin) })
        let targetKey = VocabularyNormalization.destinationKey(save.destination)

        let relocatedRules = VocabularySubstitutionGroup.movingOrigins(
            movingOriginKeys,
            awayFrom: targetKey,
            in: settings.vocabularyReplacementRules
        )
        let result = wordResult(
            word: save.destination,
            heardAs: save.origins,
            editingWord: save.pendingWord,
            baseTerms: settings.vocabularyTerms,
            baseRules: relocatedRules
        )

        guard persist(terms: result.terms, rules: result.rules) else { return false }
        pendingConflicts = []
        pendingSave = nil
        dismissWordEditor()
        return true
    }

    public func cancelOriginConflicts() {
        pendingConflicts = []
        pendingSave = nil
        pendingQuickMovedOriginKeys = nil
        hasPendingQuickMove = false
        if editorValidationError == .originConflict {
            editorValidationError = nil
        }
    }

    @discardableResult
    public func removeVariant(_ variant: String, from word: DictionaryWord) -> Bool {
        guard let groupID = word.groupID else { return false }
        let entry = VocabularySubstitutionGroup(
            id: groupID,
            destination: word.word,
            origins: word.heardAs
        )
        let remaining = entry.removingOrigin(variant)
        guard !remaining.origins.isEmpty, remaining.origins.count < entry.origins.count else {
            return false
        }

        var rules = settings.vocabularyReplacementRules
        guard let index = rules.firstIndex(where: {
            VocabularyNormalization.destinationKey($0.replace) == entry.destinationKey
        }) else {
            return false
        }

        rules[index] = VocabularyReplacementRule(
            id: rules[index].id,
            find: remaining.origins.joined(separator: ", "),
            replace: rules[index].replace
        )
        return persist(terms: settings.vocabularyTerms, rules: rules)
    }

    public func confirmDeleteWord(_ word: DictionaryWord) {
        wordToDelete = word
        showWordDeleteConfirmation = true
    }

    public func executeDeleteWord() {
        guard let word = wordToDelete else {
            showWordDeleteConfirmation = false
            return
        }

        var terms = settings.vocabularyTerms
        if let termID = word.termID {
            terms.removeAll { $0.id == termID }
        }
        var rules = settings.vocabularyReplacementRules
        rules.removeAll {
            VocabularyNormalization.destinationKey($0.replace) == word.wordKey
        }
        _ = persist(terms: terms, rules: rules)
        if editingWord?.id == word.id {
            dismissWordEditor()
        }

        wordToDelete = nil
        showWordDeleteConfirmation = false
    }

    private func duplicateWordError(word: String, heardAs: [String]) -> ValidationError? {
        let destinationKey = VocabularyNormalization.destinationKey(word)
        let isOtherLine = words.contains {
            $0.id != editingWord?.id && $0.wordKey == destinationKey
        }
        if isOtherLine {
            return .duplicateWord(word)
        }

        if heardAs.isEmpty {
            let termKey = VocabularyNormalization.termKey(word)
            let isDuplicateTerm = settings.vocabularyTerms.contains {
                $0.id != editingWord?.termID && VocabularyNormalization.termKey($0.term) == termKey
            }
            if isDuplicateTerm {
                return .duplicateWord(word)
            }
        }

        return nil
    }

    private func conflicts(
        forOriginKeys originKeys: Set<String>,
        destinationKey: String,
        excludingGroupID: UUID? = nil
    ) -> [OriginConflict] {
        var conflicts: [OriginConflict] = []

        for entry in groups
            where entry.destinationKey != destinationKey && entry.id != excludingGroupID
        {
            for origin in entry.origins where originKeys.contains(VocabularyNormalization.originKey(origin)) {
                conflicts.append(OriginConflict(origin: origin, destination: entry.destination))
            }
        }

        return conflicts
    }

    private func wordResult(
        word: String,
        heardAs: [String],
        editingWord: DictionaryWord?,
        baseTerms: [VocabularyTerm],
        baseRules: [VocabularyReplacementRule]
    ) -> (terms: [VocabularyTerm], rules: [VocabularyReplacementRule]) {
        var rules = baseRules
        if editingWord?.groupID != nil {
            let oldKey = VocabularyNormalization.destinationKey(editingWord?.word ?? "")
            rules.removeAll { VocabularyNormalization.destinationKey($0.replace) == oldKey }
        }
        if !heardAs.isEmpty {
            rules = VocabularySubstitutionGroup.merging(
                origins: heardAs,
                destination: word,
                into: rules,
                replacingEntryID: editingWord?.groupID
            )
        }

        var terms = baseTerms
        if let termID = editingWord?.termID {
            if word.isEmpty {
                terms.removeAll { $0.id == termID }
            } else if let index = terms.firstIndex(where: { $0.id == termID }) {
                terms[index] = VocabularyTerm(
                    id: termID,
                    term: word,
                    definition: terms[index].definition
                )
            }
        } else if heardAs.isEmpty, !word.isEmpty {
            terms = VocabularyTerm.adding(word, to: terms)
        }

        return (terms, rules)
    }

    @discardableResult
    private func persistWord(word: String, heardAs: [String], editingWord: DictionaryWord?) -> Bool {
        let result = wordResult(
            word: word,
            heardAs: heardAs,
            editingWord: editingWord,
            baseTerms: settings.vocabularyTerms,
            baseRules: settings.vocabularyReplacementRules
        )
        guard persist(terms: result.terms, rules: result.rules) else { return false }
        dismissWordEditor()
        return true
    }

    @discardableResult
    private func persist(terms: [VocabularyTerm], rules: [VocabularyReplacementRule]) -> Bool {
        do {
            try settings.persistDictionary(terms: terms, rules: rules)
            return true
        } catch {
            editorValidationError = .saveFailed
            return false
        }
    }

    @discardableResult
    private func persistQuickTeach(
        origins: [String],
        destination: String,
        movingOriginKeys: Set<String>
    ) -> QuickTeachOutcome {
        do {
            let coordinator = VocabularyTeachCoordinator()
            let plan = try coordinator.prepare(
                origins: origins,
                destination: destination,
                movingOriginKeys: movingOriginKeys,
                store: quickTeachStore
            )
            try coordinator.confirm(plan, into: quickTeachStore)
            clearEditorState()
            return .saved
        } catch let error as VocabularyTeachError {
            return .failed(error)
        } catch {
            return .failed(.persistenceFailed(error.localizedDescription))
        }
    }

    private func clearEditorState() {
        editorValidationError = nil
        pendingConflicts = []
        pendingSave = nil
        pendingQuickMovedOriginKeys = nil
        hasPendingQuickMove = false
    }
}
