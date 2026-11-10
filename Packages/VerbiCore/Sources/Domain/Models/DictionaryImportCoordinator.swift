import Foundation

public struct DictionaryImportSuccessResult: Equatable, Sendable {
    public let importedTermsCount: Int
    public let importedVariantsCount: Int
    public let duplicatesCount: Int
    public let conflictsCount: Int

    public init(
        importedTermsCount: Int,
        importedVariantsCount: Int,
        duplicatesCount: Int,
        conflictsCount: Int
    ) {
        self.importedTermsCount = importedTermsCount
        self.importedVariantsCount = importedVariantsCount
        self.duplicatesCount = duplicatesCount
        self.conflictsCount = conflictsCount
    }
}

public enum DictionaryImportError: LocalizedError, Equatable {
    case staleDictionary
    case persistenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .staleDictionary:
            "settings.dictionary.import.error_changed".localized
        case let .persistenceFailed(reason):
            "settings.dictionary.import.error_save".localized(with: reason)
        }
    }
}

@MainActor
public struct DictionaryImportCoordinator {
    public init() {}

    public func prepareImportPreview(
        from data: Data,
        store: DictionaryPersistenceStore
    ) throws -> DictionaryImportPreview {
        switch DictionaryArchive.validate(data: data) {
        case let .success(archive):
            archive.createPreview(
                existingTerms: store.vocabularyTerms,
                existingRules: store.vocabularyReplacementRules
            )
        case let .failure(error):
            throw error
        }
    }

    @discardableResult
    public func confirmImport(
        preview: DictionaryImportPreview,
        into store: DictionaryPersistenceStore
    ) throws -> DictionaryImportSuccessResult {
        guard store.vocabularyTerms == preview.baseTermsSnapshot,
              store.vocabularyReplacementRules == preview.baseRulesSnapshot
        else {
            throw DictionaryImportError.staleDictionary
        }

        do {
            try store.persistDictionary(
                terms: preview.mergedTerms,
                rules: preview.mergedRules
            )
        } catch {
            throw DictionaryImportError.persistenceFailed(error.localizedDescription)
        }

        return DictionaryImportSuccessResult(
            importedTermsCount: preview.acceptedTerms.count,
            importedVariantsCount: preview.acceptedVariants.count,
            duplicatesCount: preview.duplicateTerms.count + preview.duplicateVariants.count,
            conflictsCount: preview.conflictingVariants.count
        )
    }

    public func cancelImport(preview: DictionaryImportPreview) {
        _ = preview
    }
}
