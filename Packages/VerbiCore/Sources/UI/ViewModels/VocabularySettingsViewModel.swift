import Combine
import Foundation
import VerbiCoreDomain
import VerbiCoreInfrastructure

/// Edits substitution entries as consolidated groups: one destination with all
/// the origin spellings that lead to it.
@MainActor
public final class VocabularySettingsViewModel: ObservableObject {
    public enum ValidationError: Equatable {
        case emptyOrigins
        case originConflict
    }

    /// Result of one quick correction save.
    public enum QuickTeachOutcome: Equatable {
        case saved(vocabularyTermAdded: Bool)
        case invalid
        case conflicts
        case failed(VocabularyTeachError)
    }

    /// One origin that already points at a different destination.
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

    @Published public var showEntryEditor = false
    @Published public var editingEntry: VocabularySubstitutionGroup?
    @Published public var showDeleteConfirmation = false
    @Published public var entryToDelete: VocabularySubstitutionGroup?
    @Published public var editorValidationError: ValidationError?
    @Published public private(set) var pendingConflicts: [OriginConflict] = []
    /// `true` after the user explicitly moves a conflicting origin in the quick
    /// editor. The move stays in the draft until Save persists it.
    @Published public private(set) var hasPendingQuickMove = false

    private struct PendingSave {
        let origins: [String]
        let destination: String
        let isQuickTeach: Bool
        let alsoAddVocabularyTerm: Bool
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

    public var groups: [VocabularySubstitutionGroup] {
        VocabularySubstitutionGroup.groups(from: settings.vocabularyReplacementRules)
    }

    /// Origin keys that still point at more than one destination.
    public var conflictingOriginKeys: Set<String> {
        VocabularySubstitutionGroup.conflictingOriginKeys(in: settings.vocabularyReplacementRules)
    }

    public var conflictingOriginCount: Int {
        conflictingOriginKeys.count
    }

    // MARK: - Editor

    public func startCreatingEntry() {
        editingEntry = nil
        clearEditorState()
        showEntryEditor = true
    }

    public func startEditingEntry(_ entry: VocabularySubstitutionGroup) {
        editingEntry = entry
        clearEditorState()
        showEntryEditor = true
    }

    public func dismissEntryEditor() {
        clearEditorState()
        editingEntry = nil
        showEntryEditor = false
    }

    /// Saves an entry as its consolidated destination plus origins.
    ///
    /// Returns `false` when an origin already belongs to another destination.
    /// That is not persisted silently: `pendingConflicts` lets the interface
    /// ask for the explicit move.
    @discardableResult
    public func saveEntry(origins rawOrigins: String, destination rawDestination: String) -> Bool {
        let origins = VocabularyReplacementRule.normalizedVariants(from: rawOrigins)
        guard !origins.isEmpty else {
            editorValidationError = .emptyOrigins
            return false
        }

        let destination = VocabularyNormalization.spelling(rawDestination)
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
                isQuickTeach: false,
                alsoAddVocabularyTerm: false
            )
            editorValidationError = .originConflict
            return false
        }

        return persist(origins: origins, destination: destination)
    }

    /// Saves a correction from the quick editor: the substitution always, and
    /// the destination spelling as a vocabulary hint only when explicitly
    /// chosen. Validation, conflict handling, and consolidation are shared with
    /// the settings entry editor.
    @discardableResult
    public func saveQuickTeach(
        origins rawOrigins: String,
        destination rawDestination: String,
        alsoAddVocabularyTerm: Bool
    ) -> QuickTeachOutcome {
        let origins = VocabularyReplacementRule.normalizedVariants(from: rawOrigins)
        guard !origins.isEmpty else {
            editorValidationError = .emptyOrigins
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
                    alsoAddVocabularyTerm: alsoAddVocabularyTerm,
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
                alsoAddVocabularyTerm: alsoAddVocabularyTerm
            )
            editorValidationError = .originConflict
            return .conflicts
        }

        return persistQuickTeach(
            origins: origins,
            destination: destination,
            alsoAddVocabularyTerm: alsoAddVocabularyTerm,
            movingOriginKeys: []
        )
    }

    /// Stages the explicit "move to this destination" choice in the quick
    /// editor without writing. Save remains the only step that persists.
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

    /// Discards the quick editor draft, including a staged conflict move.
    /// Nothing is written.
    public func cancelQuickTeachDraft() {
        pendingConflicts = []
        pendingSave = nil
        pendingQuickMovedOriginKeys = nil
        hasPendingQuickMove = false
        editorValidationError = nil
    }

    /// Moves every conflicting origin to the edited destination, removing it
    /// from the entry that owned it before. Entries left without origins are
    /// deleted because they no longer do anything.
    @discardableResult
    public func resolveOriginConflictsByMoving() -> Bool {
        guard let save = pendingSave, !save.isQuickTeach, !pendingConflicts.isEmpty else { return false }

        let movingOriginKeys = Set(pendingConflicts.map { VocabularyNormalization.originKey($0.origin) })
        let targetKey = VocabularyNormalization.destinationKey(save.destination)

        settings.vocabularyReplacementRules = VocabularySubstitutionGroup.movingOrigins(
            movingOriginKeys,
            awayFrom: targetKey,
            in: settings.vocabularyReplacementRules
        )
        let saved = persist(origins: save.origins, destination: save.destination)
        pendingConflicts = []
        pendingSave = nil
        return saved
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

    // MARK: - Variants

    /// Removes one origin from an entry while keeping its other origins and its
    /// identity. Refuses to remove the last origin; deleting that entry goes
    /// through the confirmed entry deletion instead.
    @discardableResult
    public func removeOrigin(_ origin: String, from entry: VocabularySubstitutionGroup) -> Bool {
        let remaining = entry.removingOrigin(origin)
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
        settings.vocabularyReplacementRules = rules
        return true
    }

    // MARK: - Deletion

    public func confirmDelete(_ entry: VocabularySubstitutionGroup) {
        entryToDelete = entry
        showDeleteConfirmation = true
    }

    public func executeDelete() {
        guard let entry = entryToDelete else {
            showDeleteConfirmation = false
            return
        }

        let removedID = entry.id
        settings.vocabularyReplacementRules.removeAll { rule in
            rule.id == removedID
                || VocabularyNormalization.destinationKey(rule.replace) == entry.destinationKey
        }
        if editingEntry?.id == removedID {
            dismissEntryEditor()
        }

        entryToDelete = nil
        showDeleteConfirmation = false
    }

    // MARK: - Private

    private func conflicts(
        forOriginKeys originKeys: Set<String>,
        destinationKey: String
    ) -> [OriginConflict] {
        var conflicts: [OriginConflict] = []

        for entry in groups
            where entry.destinationKey != destinationKey && entry.id != editingEntry?.id
        {
            for origin in entry.origins where originKeys.contains(VocabularyNormalization.originKey(origin)) {
                conflicts.append(OriginConflict(origin: origin, destination: entry.destination))
            }
        }

        return conflicts
    }

    @discardableResult
    private func persist(origins: [String], destination: String) -> Bool {
        settings.vocabularyReplacementRules = VocabularySubstitutionGroup.merging(
            origins: origins,
            destination: destination,
            into: settings.vocabularyReplacementRules,
            replacingEntryID: editingEntry?.id
        )
        dismissEntryEditor()
        return true
    }

    @discardableResult
    private func persistQuickTeach(
        origins: [String],
        destination: String,
        alsoAddVocabularyTerm: Bool,
        movingOriginKeys: Set<String>
    ) -> QuickTeachOutcome {
        do {
            let coordinator = VocabularyTeachCoordinator()
            let plan = try coordinator.prepare(
                origins: origins,
                destination: destination,
                alsoAddVocabularyTerm: alsoAddVocabularyTerm,
                movingOriginKeys: movingOriginKeys,
                store: quickTeachStore
            )
            let vocabularyTermAdded = try coordinator.confirm(plan, into: quickTeachStore)
            dismissEntryEditor()
            return .saved(vocabularyTermAdded: vocabularyTermAdded)
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
