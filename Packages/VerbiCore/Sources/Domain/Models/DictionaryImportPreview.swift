import Foundation
import VerbiCoreCommon

/// Detailed analysis and preview of a dictionary archive before import.
/// Distinguishes between accepted, duplicate, conflicting, and invalid terms and variants,
/// and preserves existing conflicting destinations without silent drops of valid variants.
public struct DictionaryImportPreview: Identifiable, Sendable {
    public let id: UUID
    public let sourceApp: String
    public let exportDate: String

    /// Snapshot of dictionary state when the preview was generated.
    public let baseTermsSnapshot: [VocabularyTerm]
    public let baseRulesSnapshot: [VocabularyReplacementRule]

    /// Summary statistics.
    public let termsSummary: EntrySummary
    public let variantsSummary: EntrySummary

    /// Categorized items.
    public let acceptedTerms: [VocabularyTerm]
    public let duplicateTerms: [DuplicateTermItem]
    public let invalidTerms: [InvalidTermItem]

    public let acceptedVariants: [AcceptedVariantItem]
    public let duplicateVariants: [DuplicateVariantItem]
    public let conflictingVariants: [ConflictingVariantItem]
    public let invalidVariants: [InvalidVariantItem]

    /// Pre-computed merged state ready to persist upon confirmation.
    public let mergedTerms: [VocabularyTerm]
    public let mergedRules: [VocabularyReplacementRule]

    public init(
        id: UUID = UUID(),
        sourceApp: String,
        exportDate: String,
        baseTermsSnapshot: [VocabularyTerm],
        baseRulesSnapshot: [VocabularyReplacementRule],
        termsSummary: EntrySummary,
        variantsSummary: EntrySummary,
        acceptedTerms: [VocabularyTerm],
        duplicateTerms: [DuplicateTermItem],
        invalidTerms: [InvalidTermItem],
        acceptedVariants: [AcceptedVariantItem],
        duplicateVariants: [DuplicateVariantItem],
        conflictingVariants: [ConflictingVariantItem],
        invalidVariants: [InvalidVariantItem],
        mergedTerms: [VocabularyTerm],
        mergedRules: [VocabularyReplacementRule]
    ) {
        self.id = id
        self.sourceApp = sourceApp
        self.exportDate = exportDate
        self.baseTermsSnapshot = baseTermsSnapshot
        self.baseRulesSnapshot = baseRulesSnapshot
        self.termsSummary = termsSummary
        self.variantsSummary = variantsSummary
        self.acceptedTerms = acceptedTerms
        self.duplicateTerms = duplicateTerms
        self.invalidTerms = invalidTerms
        self.acceptedVariants = acceptedVariants
        self.duplicateVariants = duplicateVariants
        self.conflictingVariants = conflictingVariants
        self.invalidVariants = invalidVariants
        self.mergedTerms = mergedTerms
        self.mergedRules = mergedRules
    }

    public var hasImportableChanges: Bool {
        !acceptedTerms.isEmpty || !acceptedVariants.isEmpty
    }

    public var totalAcceptedCount: Int {
        acceptedTerms.count + acceptedVariants.count
    }

    public var totalDuplicatesCount: Int {
        duplicateTerms.count + duplicateVariants.count
    }

    public var totalConflictsCount: Int {
        conflictingVariants.count
    }

    public var totalInvalidCount: Int {
        invalidTerms.count + invalidVariants.count
    }

    public struct EntrySummary: Sendable, Hashable {
        public let acceptedCount: Int
        public let duplicateCount: Int
        public let conflictingCount: Int
        public let invalidCount: Int

        public init(
            acceptedCount: Int = 0,
            duplicateCount: Int = 0,
            conflictingCount: Int = 0,
            invalidCount: Int = 0
        ) {
            self.acceptedCount = acceptedCount
            self.duplicateCount = duplicateCount
            self.conflictingCount = conflictingCount
            self.invalidCount = invalidCount
        }

        public var totalCount: Int {
            acceptedCount + duplicateCount + conflictingCount + invalidCount
        }
    }

    public enum TermDuplicateReason: Sendable, Hashable {
        case alreadyInDictionary
        case duplicateInFile
    }

    public enum VariantDuplicateReason: Sendable, Hashable {
        case alreadyInDictionary
        case duplicateInFile
    }

    public enum VariantConflictSource: Sendable, Hashable {
        case existingDictionary
        case earlierInFile
    }

    public struct DuplicateTermItem: Identifiable, Sendable, Hashable {
        public let id: UUID
        public let term: String
        public let reason: TermDuplicateReason

        public init(id: UUID = UUID(), term: String, reason: TermDuplicateReason) {
            self.id = id
            self.term = term
            self.reason = reason
        }
    }

    public struct InvalidTermItem: Identifiable, Sendable, Hashable {
        public let id: UUID
        public let rawTerm: String
        public let reason: String

        public init(id: UUID = UUID(), rawTerm: String, reason: String) {
            self.id = id
            self.rawTerm = rawTerm
            self.reason = reason
        }
    }

    public struct AcceptedVariantItem: Identifiable, Sendable, Hashable {
        public let id: UUID
        public let origin: String
        public let destination: String
        public let isNewDestination: Bool

        public init(id: UUID = UUID(), origin: String, destination: String, isNewDestination: Bool) {
            self.id = id
            self.origin = origin
            self.destination = destination
            self.isNewDestination = isNewDestination
        }
    }

    public struct DuplicateVariantItem: Identifiable, Sendable, Hashable {
        public let id: UUID
        public let origin: String
        public let destination: String
        public let reason: VariantDuplicateReason

        public init(id: UUID = UUID(), origin: String, destination: String, reason: VariantDuplicateReason) {
            self.id = id
            self.origin = origin
            self.destination = destination
            self.reason = reason
        }
    }

    public struct ConflictingVariantItem: Identifiable, Sendable, Hashable {
        public let id: UUID
        public let origin: String
        public let candidateDestination: String
        public let existingDestination: String
        public let source: VariantConflictSource

        public init(
            id: UUID = UUID(),
            origin: String,
            candidateDestination: String,
            existingDestination: String,
            source: VariantConflictSource
        ) {
            self.id = id
            self.origin = origin
            self.candidateDestination = candidateDestination
            self.existingDestination = existingDestination
            self.source = source
        }
    }

    public struct InvalidVariantItem: Identifiable, Sendable, Hashable {
        public let id: UUID
        public let origin: String
        public let destination: String
        public let reason: String

        public init(id: UUID = UUID(), origin: String, destination: String, reason: String) {
            self.id = id
            self.origin = origin
            self.destination = destination
            self.reason = reason
        }
    }

    /// Creates an import preview by comparing an archive against current dictionary state.
    public static func create(
        from archive: DictionaryArchive,
        existingTerms: [VocabularyTerm],
        existingRules: [VocabularyReplacementRule]
    ) -> DictionaryImportPreview {
        let normalizedExistingTerms = VocabularyTerm.normalized(existingTerms)
        let termsCategorization = categorizeTerms(archive.vocabularyTerms, existingTerms: normalizedExistingTerms)
        let mergedTerms = VocabularyTerm.normalized(normalizedExistingTerms + termsCategorization.accepted)

        let existingGroups = VocabularySubstitutionGroup.groups(from: existingRules)
        let variantsCategorization = categorizeVariants(archive.substitutionRules, existingGroups: existingGroups)

        let termsSummary = EntrySummary(
            acceptedCount: termsCategorization.accepted.count,
            duplicateCount: termsCategorization.duplicates.count,
            conflictingCount: 0,
            invalidCount: termsCategorization.invalids.count
        )
        let variantsSummary = EntrySummary(
            acceptedCount: variantsCategorization.accepted.count,
            duplicateCount: variantsCategorization.duplicates.count,
            conflictingCount: variantsCategorization.conflicts.count,
            invalidCount: variantsCategorization.invalids.count
        )

        return DictionaryImportPreview(
            sourceApp: archive.sourceApp,
            exportDate: archive.exportDate,
            baseTermsSnapshot: existingTerms,
            baseRulesSnapshot: existingRules,
            termsSummary: termsSummary,
            variantsSummary: variantsSummary,
            acceptedTerms: termsCategorization.accepted,
            duplicateTerms: termsCategorization.duplicates,
            invalidTerms: termsCategorization.invalids,
            acceptedVariants: variantsCategorization.accepted,
            duplicateVariants: variantsCategorization.duplicates,
            conflictingVariants: variantsCategorization.conflicts,
            invalidVariants: variantsCategorization.invalids,
            mergedTerms: mergedTerms,
            mergedRules: variantsCategorization.mergedRules
        )
    }

    // MARK: - Helper Methods

    private struct TermsAnalysis {
        var accepted: [VocabularyTerm] = []
        var duplicates: [DuplicateTermItem] = []
        var invalids: [InvalidTermItem] = []
    }

    private struct VariantsAnalysis {
        var accepted: [AcceptedVariantItem] = []
        var duplicates: [DuplicateVariantItem] = []
        var conflicts: [ConflictingVariantItem] = []
        var invalids: [InvalidVariantItem] = []
        var mergedRules: [VocabularyReplacementRule] = []
    }

    private struct DestinationLookup {
        let destination: String
        let destinationKey: String
    }

    private struct VariantClassificationContext {
        let existingLookup: [String: DestinationLookup]
        let existingGroups: [VocabularySubstitutionGroup]
        var seenOriginInFile: [String: DestinationLookup] = [:]
        var acceptedOriginsByDestinationKey: [String: [String]] = [:]
        var acceptedDestinationByKey: [String: String] = [:]
        var accepted: [AcceptedVariantItem] = []
        var duplicates: [DuplicateVariantItem] = []
        var conflicts: [ConflictingVariantItem] = []
    }

    private static func categorizeTerms(
        _ incomingTerms: [VocabularyTerm],
        existingTerms: [VocabularyTerm]
    ) -> TermsAnalysis {
        var existingTermKeys = Set<String>()
        for term in existingTerms {
            existingTermKeys.insert(VocabularyNormalization.termKey(term.term))
        }

        var analysis = TermsAnalysis()
        var seenTermKeysInFile = Set<String>()

        for term in incomingTerms {
            let normalizedTerm = VocabularyNormalization.spelling(term.term)
            if normalizedTerm.isEmpty {
                analysis.invalids.append(InvalidTermItem(
                    rawTerm: term.term,
                    reason: "settings.dictionary.import.reason.empty_term".localized
                ))
                continue
            }

            let key = VocabularyNormalization.termKey(normalizedTerm)
            if existingTermKeys.contains(key) {
                analysis.duplicates.append(DuplicateTermItem(term: normalizedTerm, reason: .alreadyInDictionary))
            } else if seenTermKeysInFile.contains(key) {
                analysis.duplicates.append(DuplicateTermItem(term: normalizedTerm, reason: .duplicateInFile))
            } else {
                seenTermKeysInFile.insert(key)
                let definition = VocabularyNormalization.spelling(term.definition)
                analysis.accepted.append(VocabularyTerm(id: term.id, term: normalizedTerm, definition: definition))
            }
        }

        return analysis
    }

    private static func categorizeVariants(
        _ incomingRules: [VocabularyReplacementRule],
        existingGroups: [VocabularySubstitutionGroup]
    ) -> VariantsAnalysis {
        var existingLookup: [String: DestinationLookup] = [:]
        for group in existingGroups {
            for origin in group.origins {
                let key = VocabularyNormalization.originKey(origin)
                existingLookup[key] = DestinationLookup(destination: group.destination, destinationKey: group.destinationKey)
            }
        }

        var context = VariantClassificationContext(
            existingLookup: existingLookup,
            existingGroups: existingGroups
        )
        var invalids: [InvalidVariantItem] = []

        for rule in incomingRules {
            let destination = VocabularyNormalization.spelling(rule.replace)
            let destinationKey = VocabularyNormalization.destinationKey(destination)

            let rawVariants = rule.find.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            let nonEmptyRaw = rawVariants.filter { !VocabularyNormalization.spelling($0).isEmpty }
            if rawVariants.isEmpty || nonEmptyRaw.isEmpty {
                invalids.append(InvalidVariantItem(
                    origin: rule.find,
                    destination: destination,
                    reason: "settings.dictionary.import.reason.empty_origin".localized
                ))
                continue
            }

            for rawVariant in rawVariants {
                let origin = VocabularyNormalization.spelling(rawVariant)
                if origin.isEmpty {
                    invalids.append(InvalidVariantItem(
                        origin: rawVariant,
                        destination: destination,
                        reason: "settings.dictionary.import.reason.empty_origin".localized
                    ))
                    continue
                }

                let originKey = VocabularyNormalization.originKey(origin)
                classifyVariant(
                    origin: origin,
                    originKey: originKey,
                    destination: destination,
                    destinationKey: destinationKey,
                    context: &context
                )
            }
        }

        let mergedRules = buildMergedRules(
            existingGroups: existingGroups,
            acceptedOriginsByDestinationKey: context.acceptedOriginsByDestinationKey,
            acceptedDestinationByKey: context.acceptedDestinationByKey
        )

        return VariantsAnalysis(
            accepted: context.accepted,
            duplicates: context.duplicates,
            conflicts: context.conflicts,
            invalids: invalids,
            mergedRules: mergedRules
        )
    }

    private static func classifyVariant(
        origin: String,
        originKey: String,
        destination: String,
        destinationKey: String,
        context: inout VariantClassificationContext
    ) {
        if let existing = context.existingLookup[originKey] {
            if existing.destinationKey == destinationKey {
                context.duplicates.append(DuplicateVariantItem(origin: origin, destination: destination, reason: .alreadyInDictionary))
            } else {
                context.conflicts.append(ConflictingVariantItem(
                    origin: origin,
                    candidateDestination: destination,
                    existingDestination: existing.destination,
                    source: .existingDictionary
                ))
            }
            return
        }

        if let earlier = context.seenOriginInFile[originKey] {
            if earlier.destinationKey == destinationKey {
                context.duplicates.append(DuplicateVariantItem(origin: origin, destination: destination, reason: .duplicateInFile))
            } else {
                context.conflicts.append(ConflictingVariantItem(
                    origin: origin,
                    candidateDestination: destination,
                    existingDestination: earlier.destination,
                    source: .earlierInFile
                ))
            }
            return
        }

        context.seenOriginInFile[originKey] = DestinationLookup(destination: destination, destinationKey: destinationKey)
        context.acceptedDestinationByKey[destinationKey] = destination
        context.acceptedOriginsByDestinationKey[destinationKey, default: []].append(origin)

        let isNewDest = !context.existingGroups.contains(where: { $0.destinationKey == destinationKey })
        context.accepted.append(AcceptedVariantItem(
            origin: origin,
            destination: destination,
            isNewDestination: isNewDest
        ))
    }

    private static func buildMergedRules(
        existingGroups: [VocabularySubstitutionGroup],
        acceptedOriginsByDestinationKey: [String: [String]],
        acceptedDestinationByKey: [String: String]
    ) -> [VocabularyReplacementRule] {
        var updatedGroups = existingGroups
        let sortedDestinationKeys = acceptedOriginsByDestinationKey.keys.sorted()
        for destKey in sortedDestinationKeys {
            let newOrigins = acceptedOriginsByDestinationKey[destKey] ?? []
            if let index = updatedGroups.firstIndex(where: { $0.destinationKey == destKey }) {
                updatedGroups[index] = updatedGroups[index].appendingOrigins(newOrigins)
            } else if let destination = acceptedDestinationByKey[destKey] {
                updatedGroups.append(VocabularySubstitutionGroup(destination: destination, origins: newOrigins))
            }
        }
        return VocabularySubstitutionGroup.rules(from: updatedGroups)
    }
}
