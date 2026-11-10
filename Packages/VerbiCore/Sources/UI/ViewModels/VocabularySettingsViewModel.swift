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

    private struct PendingSave {
        let origins: [String]
        let destination: String
    }

    private let settings: AppSettingsStore
    private var pendingSave: PendingSave?
    private var cancellables = Set<AnyCancellable>()

    public init(settings: AppSettingsStore = .shared) {
        self.settings = settings

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
            pendingSave = PendingSave(origins: origins, destination: destination)
            editorValidationError = .originConflict
            return false
        }

        return persist(origins: origins, destination: destination)
    }

    /// Moves every conflicting origin to the edited destination, removing it
    /// from the entry that owned it before. Entries left without origins are
    /// deleted because they no longer do anything.
    @discardableResult
    public func resolveOriginConflictsByMoving() -> Bool {
        guard let save = pendingSave, !pendingConflicts.isEmpty else { return false }

        let movingOriginKeys = Set(pendingConflicts.map { VocabularyNormalization.originKey($0.origin) })
        let targetKey = VocabularyNormalization.destinationKey(save.destination)

        let updatedRules = settings.vocabularyReplacementRules.compactMap { rule -> VocabularyReplacementRule? in
            guard VocabularyNormalization.destinationKey(rule.replace) != targetKey else {
                return rule
            }

            let remaining = rule.normalizedFindVariants.filter {
                !movingOriginKeys.contains(VocabularyNormalization.originKey($0))
            }
            guard !remaining.isEmpty else { return nil }

            return VocabularyReplacementRule(
                id: rule.id,
                find: remaining.joined(separator: ", "),
                replace: rule.replace
            )
        }

        settings.vocabularyReplacementRules = updatedRules
        let saved = persist(origins: save.origins, destination: save.destination)
        pendingConflicts = []
        pendingSave = nil
        return saved
    }

    public func cancelOriginConflicts() {
        pendingConflicts = []
        pendingSave = nil
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
        let destinationKey = VocabularyNormalization.destinationKey(destination)
        let existingRules = settings.vocabularyReplacementRules
        let targetID = editingEntry?.id
            ?? existingRules.first(where: {
                VocabularyNormalization.destinationKey($0.replace) == destinationKey
            })?.id
            ?? UUID()

        var mergedOrigins = origins
        var remainingRules: [VocabularyReplacementRule] = []
        var insertionIndex: Int?

        for rule in existingRules {
            let isEditedRule = rule.id == editingEntry?.id
            let sharesDestination = VocabularyNormalization.destinationKey(rule.replace) == destinationKey

            guard isEditedRule || sharesDestination else {
                remainingRules.append(rule)
                continue
            }

            if insertionIndex == nil {
                insertionIndex = remainingRules.count
            }
            if !isEditedRule {
                mergedOrigins.append(contentsOf: rule.normalizedFindVariants)
            }
        }

        remainingRules.insert(
            VocabularyReplacementRule(
                id: targetID,
                find: mergedOrigins.joined(separator: ", "),
                replace: destination
            ),
            at: insertionIndex ?? remainingRules.count
        )

        settings.vocabularyReplacementRules = remainingRules
        dismissEntryEditor()
        return true
    }

    private func clearEditorState() {
        editorValidationError = nil
        pendingConflicts = []
        pendingSave = nil
    }
}
