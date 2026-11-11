import Foundation

/// One correction the user reviewed in the quick editor, merged with the
/// current dictionary but not yet written.
public struct VocabularyTeachPlan: Equatable, Sendable {
    public let terms: [VocabularyTerm]
    public let rules: [VocabularyReplacementRule]
    public let baseTerms: [VocabularyTerm]
    public let baseRules: [VocabularyReplacementRule]

    public init(
        terms: [VocabularyTerm],
        rules: [VocabularyReplacementRule],
        baseTerms: [VocabularyTerm],
        baseRules: [VocabularyReplacementRule]
    ) {
        self.terms = terms
        self.rules = rules
        self.baseTerms = baseTerms
        self.baseRules = baseRules
    }
}

public enum VocabularyTeachError: LocalizedError, Equatable {
    case emptyOrigin
    case staleDictionary
    case persistenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyOrigin:
            "settings.dictionary.words.validation.heard_as_required".localized
        case .staleDictionary:
            "settings.dictionary.quick_teach.error_changed".localized
        case let .persistenceFailed(reason):
            "settings.dictionary.import.error_save".localized(with: reason)
        }
    }
}

/// Builds and writes one reviewed spelling correction.
///
/// The substitution is persisted through the same atomic
/// `DictionaryPersistenceStore` path used by archive import, so a storage
/// failure leaves the in-memory dictionary untouched. Merge shape is shared
/// with the settings entry editor through `VocabularySubstitutionGroup`. The
/// corrected spelling needs no separate vocabulary term: it reaches future
/// snapshots as a hint through the unified hint list.
@MainActor
public struct VocabularyTeachCoordinator {
    public init() {}

    /// Merges `origins` and `destination` into `store`'s current dictionary.
    /// Nothing is written; the returned plan is the reviewed state.
    public func prepare(
        origins rawOrigins: [String],
        destination rawDestination: String,
        movingOriginKeys: Set<String> = [],
        store: DictionaryPersistenceStore
    ) throws -> VocabularyTeachPlan {
        var seenOriginKeys = Set<String>()
        let origins = rawOrigins.compactMap { rawOrigin -> String? in
            let origin = VocabularyNormalization.spelling(rawOrigin)
            guard !origin.isEmpty,
                  seenOriginKeys.insert(VocabularyNormalization.originKey(origin)).inserted
            else {
                return nil
            }
            return origin
        }
        guard !origins.isEmpty else {
            throw VocabularyTeachError.emptyOrigin
        }

        let destination = VocabularyNormalization.spelling(rawDestination)
        let baseTerms = store.vocabularyTerms
        let baseRules = store.vocabularyReplacementRules

        let relocatedRules = VocabularySubstitutionGroup.movingOrigins(
            movingOriginKeys,
            awayFrom: VocabularyNormalization.destinationKey(destination),
            in: baseRules
        )
        let mergedRules = VocabularySubstitutionGroup.merging(
            origins: origins,
            destination: destination,
            into: relocatedRules
        )

        return VocabularyTeachPlan(
            terms: baseTerms,
            rules: mergedRules,
            baseTerms: baseTerms,
            baseRules: baseRules
        )
    }

    /// Persists a reviewed plan. A dictionary changed after preparation is
    /// rejected instead of overwriting the newer state.
    public func confirm(
        _ plan: VocabularyTeachPlan,
        into store: DictionaryPersistenceStore
    ) throws {
        guard store.vocabularyTerms == plan.baseTerms,
              store.vocabularyReplacementRules == plan.baseRules
        else {
            throw VocabularyTeachError.staleDictionary
        }

        do {
            try store.persistDictionary(terms: plan.terms, rules: plan.rules)
        } catch {
            throw VocabularyTeachError.persistenceFailed(error.localizedDescription)
        }
    }
}
