import VerbiCoreDomain

/// Explicit vocabulary choice for one transcription retry.
///
/// The choice is independent from the provider/model override: either intent
/// keeps the provider, model, and language already selected for the attempt.
public enum RetryVocabularyIntent: Sendable, Hashable {
    /// Reproduce the vocabulary captured with the original execution.
    /// Artifacts that predate vocabulary snapshots fall back to the current
    /// dictionary, and the retry records that fallback explicitly.
    case originalSnapshot
    /// Apply the dictionary as it exists when the attempt starts.
    case currentDictionary
}

/// Resolves the vocabulary used by one retry attempt.
///
/// Callers capture `current` exactly once, before the attempt performs any
/// work, so later dictionary edits cannot change its result.
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
