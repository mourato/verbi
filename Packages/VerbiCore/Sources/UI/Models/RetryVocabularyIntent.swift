import VerbiCoreDomain

public enum RetryVocabularyIntent: Sendable, Hashable {
    case originalSnapshot
    case currentDictionary
}

enum RetryVocabularyResolver {
    struct Resolution: Equatable, Sendable {
        let snapshot: VocabularySnapshot
        let source: ExecutionVocabularySource
    }

    static func resolve(
        intent: RetryVocabularyIntent,
        persistedSnapshot: VocabularySnapshot?,
        persistedSource: ExecutionVocabularySource?,
        current: VocabularySnapshot
    ) -> Resolution {
        switch intent {
        case .currentDictionary:
            return Resolution(snapshot: current, source: .currentDictionary)
        case .originalSnapshot:
            guard persistedSource != .notRecorded, let persistedSnapshot else {
                return Resolution(snapshot: current, source: .currentDictionaryFallback)
            }
            return Resolution(snapshot: persistedSnapshot, source: .originalSnapshot)
        }
    }
}
