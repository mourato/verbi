import Combine
import Foundation
import VerbiCoreDomain
import VerbiCoreInfrastructure

@MainActor
public final class VocabularyTermsSettingsViewModel: ObservableObject {
    public enum ValidationError: Equatable {
        case emptyTerm
        case duplicatedTerm(String)
    }

    @Published public var terms: [VocabularyTerm] = []
    @Published public var bulkInputText = ""
    @Published public var validationError: ValidationError?
    @Published public var showDeleteConfirmation = false
    @Published public var termToDelete: VocabularyTerm?
    @Published public var addedTermsCount = 0
    @Published public var showTermEditor = false
    @Published public var editingTerm: VocabularyTerm?

    private let settings: AppSettingsStore
    private var cancellables = Set<AnyCancellable>()

    public init(settings: AppSettingsStore = .shared) {
        self.settings = settings
        terms = settings.vocabularyTerms

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reloadFromStore()
            }
            .store(in: &cancellables)
    }

    public func reloadFromStore() {
        terms = settings.vocabularyTerms
    }

    /// Adds comma-separated terms from `bulkInputText`. Returns the count of terms added.
    @discardableResult
    public func addTermsFromBulkInput() -> Int {
        let rawInput = bulkInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else {
            validationError = .emptyTerm
            return 0
        }

        let rawTerms = rawInput
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rawTerms.isEmpty else {
            validationError = .emptyTerm
            return 0
        }

        var addedCount = 0
        var updatedTerms = settings.vocabularyTerms
        var lastDuplicate: String?

        for rawTerm in rawTerms {
            let normalizedTerm = VocabularyNormalization.spelling(rawTerm)
            let key = VocabularyNormalization.termKey(normalizedTerm)
            let isDuplicate = updatedTerms.contains { VocabularyNormalization.termKey($0.term) == key }
            guard !isDuplicate else {
                lastDuplicate = normalizedTerm
                continue
            }

            updatedTerms.append(VocabularyTerm(term: normalizedTerm, definition: ""))
            addedCount += 1
        }

        guard addedCount > 0 else {
            if let lastDuplicate {
                validationError = .duplicatedTerm(lastDuplicate)
            }
            return 0
        }

        settings.vocabularyTerms = updatedTerms
        terms = settings.vocabularyTerms
        bulkInputText = ""
        validationError = lastDuplicate.map { .duplicatedTerm($0) }
        addedTermsCount = addedCount
        return addedCount
    }

    public func confirmDelete(_ term: VocabularyTerm) {
        termToDelete = term
        showDeleteConfirmation = true
    }

    // MARK: - Term editor

    /// Opens the editor for a new entry, or for `term` when editing. Editing
    /// keeps the persisted identity so the entry is updated in place.
    public func startEditingTerm(_ term: VocabularyTerm? = nil) {
        editingTerm = term
        validationError = nil
        showTermEditor = true
    }

    public func dismissTermEditor() {
        editingTerm = nil
        showTermEditor = false
        if validationError != nil {
            validationError = nil
        }
    }

    /// Saves the recognition hint spelled `term`, keeping its identifier on
    /// edit. The definition stays optional.
    @discardableResult
    public func saveTerm(term: String, definition: String) -> Bool {
        let normalizedTerm = VocabularyNormalization.spelling(term)
        guard !normalizedTerm.isEmpty else {
            validationError = .emptyTerm
            return false
        }

        let key = VocabularyNormalization.termKey(normalizedTerm)
        let hasDuplicate = settings.vocabularyTerms.contains { existing in
            existing.id != editingTerm?.id && VocabularyNormalization.termKey(existing.term) == key
        }
        guard !hasDuplicate else {
            validationError = .duplicatedTerm(normalizedTerm)
            return false
        }

        let updatedTerm = VocabularyTerm(
            id: editingTerm?.id ?? UUID(),
            term: normalizedTerm,
            definition: VocabularyNormalization.spelling(definition)
        )

        var updatedTerms = settings.vocabularyTerms
        if let index = updatedTerms.firstIndex(where: { $0.id == updatedTerm.id }) {
            updatedTerms[index] = updatedTerm
        } else {
            updatedTerms.append(updatedTerm)
        }

        settings.vocabularyTerms = updatedTerms
        terms = settings.vocabularyTerms
        editingTerm = nil
        showTermEditor = false
        validationError = nil
        return true
    }

    public func executeDelete() {
        guard let term = termToDelete else {
            showDeleteConfirmation = false
            return
        }

        removeTerm(term)
        if editingTerm?.id == term.id {
            dismissTermEditor()
        }
        termToDelete = nil
        showDeleteConfirmation = false
    }

    public func removeTerm(_ term: VocabularyTerm) {
        var updatedTerms = settings.vocabularyTerms
        updatedTerms.removeAll { $0.id == term.id }
        settings.vocabularyTerms = updatedTerms
        terms = settings.vocabularyTerms
    }
}
