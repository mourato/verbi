import Foundation

@MainActor
public protocol DictionaryPersistenceStore: AnyObject {
    var vocabularyTerms: [VocabularyTerm] { get }
    var vocabularyReplacementRules: [VocabularyReplacementRule] { get }
    func persistDictionary(terms: [VocabularyTerm], rules: [VocabularyReplacementRule]) throws
}

public enum DictionaryPersistenceError: LocalizedError, Equatable {
    case saveVerificationFailed

    public var errorDescription: String? {
        switch self {
        case .saveVerificationFailed:
            "settings.dictionary.import.error_save_failed".localized
        }
    }
}
