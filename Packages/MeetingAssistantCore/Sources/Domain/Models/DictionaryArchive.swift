import Foundation
import MeetingAssistantCoreCommon

/// Versioned archive format for Dictionary import/export.
/// Contains both vocabulary terms and substitution rules.
public struct DictionaryArchive: Codable, Sendable {
    /// Schema version identifier for forward/backward compatibility.
    public let schemaVersion: String

    /// ISO 8601 date when this archive was exported.
    public let exportDate: String

    /// Source application identifier.
    public let sourceApp: String

    /// Exported vocabulary terms.
    public let vocabularyTerms: [VocabularyTerm]

    /// Exported substitution rules.
    public let substitutionRules: [VocabularyReplacementRule]

    public init(
        schemaVersion: String = Self.currentSchemaVersion,
        exportDate: String = Self.currentTimestamp(),
        sourceApp: String = AppIdentity.displayName,
        vocabularyTerms: [VocabularyTerm],
        substitutionRules: [VocabularyReplacementRule]
    ) {
        self.schemaVersion = schemaVersion
        self.exportDate = exportDate
        self.sourceApp = sourceApp
        self.vocabularyTerms = vocabularyTerms
        self.substitutionRules = substitutionRules
    }

    public static let currentSchemaVersion = "dictionary_v1"

    public static func currentTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    /// Result of importing an archive.
    public struct ImportResult: Sendable {
        public let termsImported: Int
        public let rulesImported: Int
        public let duplicateTermCount: Int
        public let duplicateRuleCount: Int

        public init(
            termsImported: Int = 0,
            rulesImported: Int = 0,
            duplicateTermCount: Int = 0,
            duplicateRuleCount: Int = 0
        ) {
            self.termsImported = termsImported
            self.rulesImported = rulesImported
            self.duplicateTermCount = duplicateTermCount
            self.duplicateRuleCount = duplicateRuleCount
        }

        public var totalImported: Int {
            termsImported + rulesImported
        }

        public var totalDuplicates: Int {
            duplicateTermCount + duplicateRuleCount
        }
    }

    /// Applied merge outcome including the collections to persist.
    public struct MergeOutcome: Sendable {
        public let terms: [VocabularyTerm]
        public let rules: [VocabularyReplacementRule]
        public let result: ImportResult

        public init(
            terms: [VocabularyTerm],
            rules: [VocabularyReplacementRule],
            result: ImportResult
        ) {
            self.terms = terms
            self.rules = rules
            self.result = result
        }
    }

    /// Validates that the archive can be decoded.
    /// Returns `.success` if the schema version is known, `.failure` otherwise.
    public static func validate(data: Data) -> Result<DictionaryArchive, Error> {
        do {
            let archive = try JSONDecoder().decode(DictionaryArchive.self, from: data)
            guard archive.schemaVersion == currentSchemaVersion else {
                return .failure(DictionaryArchiveError.unsupportedSchemaVersion(archive.schemaVersion))
            }
            return .success(archive)
        } catch {
            return .failure(error)
        }
    }

    /// Merges archive contents into existing collections, deduplicating by term/find.
    /// Incoming terms are normalized first. Within-archive duplicates are counted once.
    public func merge(
        into existingTerms: [VocabularyTerm],
        existingRules: [VocabularyReplacementRule]
    ) -> MergeOutcome {
        let normalizedExistingTerms = VocabularyTerm.normalized(existingTerms)
        let normalizedIncomingTerms = VocabularyTerm.normalized(vocabularyTerms)

        var termsImported = 0
        var duplicateTermCount = 0
        var mergedTerms = normalizedExistingTerms
        var seenTermKeys = Set(normalizedExistingTerms.map { $0.term.lowercased() })

        for term in normalizedIncomingTerms {
            let key = term.term.lowercased()
            if seenTermKeys.contains(key) {
                duplicateTermCount += 1
            } else {
                seenTermKeys.insert(key)
                mergedTerms.append(term)
                termsImported += 1
            }
        }

        var rulesImported = 0
        var duplicateRuleCount = 0
        var mergedRules = existingRules
        var seenRuleVariants = Set(
            existingRules.flatMap { $0.normalizedFindVariants.map { $0.lowercased() } }
        )

        for rule in substitutionRules {
            let ruleVariants = Set(rule.normalizedFindVariants.map { $0.lowercased() })
            guard !ruleVariants.isEmpty else {
                duplicateRuleCount += 1
                continue
            }

            if !ruleVariants.isDisjoint(with: seenRuleVariants) {
                duplicateRuleCount += 1
                continue
            }

            seenRuleVariants.formUnion(ruleVariants)
            mergedRules.append(rule)
            rulesImported += 1
        }

        return MergeOutcome(
            terms: VocabularyTerm.normalized(mergedTerms),
            rules: mergedRules,
            result: ImportResult(
                termsImported: termsImported,
                rulesImported: rulesImported,
                duplicateTermCount: duplicateTermCount,
                duplicateRuleCount: duplicateRuleCount
            )
        )
    }
}

public enum DictionaryArchiveError: Error, LocalizedError {
    case unsupportedSchemaVersion(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            "Unsupported dictionary archive schema version: \(version)"
        }
    }
}
