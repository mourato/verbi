import Foundation
import VerbiCoreCommon

public struct DictionaryArchive: Codable, Sendable {
    public let schemaVersion: String

    public let exportDate: String

    public let sourceApp: String

    public let vocabularyTerms: [VocabularyTerm]

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

    public func createPreview(
        existingTerms: [VocabularyTerm],
        existingRules: [VocabularyReplacementRule]
    ) -> DictionaryImportPreview {
        DictionaryImportPreview.create(
            from: self,
            existingTerms: existingTerms,
            existingRules: existingRules
        )
    }

    public static func validate(data: Data) -> Result<DictionaryArchive, Error> {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(DictionaryArchiveError.invalidFile)
        }

        if let format = jsonObject["format"] as? String {
            guard format == "voiceink.dictionary" else {
                return .failure(DictionaryArchiveError.unsupportedFormat(format))
            }
            guard let version = jsonObject["schemaVersion"] as? Int else {
                return .failure(DictionaryArchiveError.unsupportedSchemaVersion("unknown"))
            }
            guard version == 1 else {
                return .failure(DictionaryArchiveError.unsupportedSchemaVersion("voiceink.dictionary schemaVersion \(version)"))
            }

            do {
                let voiceInkArchive = try JSONDecoder().decode(VoiceInkArchivePayload.self, from: data)
                let terms = voiceInkArchive.vocabulary.map {
                    VocabularyTerm(term: $0.term, definition: "")
                }
                let rules = voiceInkArchive.replacements.map { entry in
                    VocabularyReplacementRule(
                        find: entry.sources.joined(separator: ", "),
                        replace: entry.replacement
                    )
                }
                let archive = DictionaryArchive(
                    schemaVersion: "voiceink.dictionary_v1",
                    exportDate: voiceInkArchive.exportedAt ?? Self.currentTimestamp(),
                    sourceApp: "VoiceInk",
                    vocabularyTerms: terms,
                    substitutionRules: rules
                )
                return .success(archive)
            } catch {
                return .failure(DictionaryArchiveError.invalidFile)
            }
        }

        if let schemaVersion = jsonObject["schemaVersion"] as? String {
            guard schemaVersion == currentSchemaVersion else {
                return .failure(DictionaryArchiveError.unsupportedSchemaVersion(schemaVersion))
            }

            do {
                let archive = try JSONDecoder().decode(DictionaryArchive.self, from: data)
                return .success(archive)
            } catch {
                return .failure(DictionaryArchiveError.invalidFile)
            }
        }

        return .failure(DictionaryArchiveError.invalidFile)
    }

    public func merge(
        into existingTerms: [VocabularyTerm],
        existingRules: [VocabularyReplacementRule]
    ) -> MergeOutcome {
        let preview = createPreview(existingTerms: existingTerms, existingRules: existingRules)

        let affectedDestinations = Set(preview.acceptedVariants.map { VocabularyNormalization.destinationKey($0.destination) })
        let rulesImportedCount = affectedDestinations.count
        let duplicateRuleCount = preview.duplicateVariants.count + preview.conflictingVariants.count + preview.invalidVariants.count

        return MergeOutcome(
            terms: preview.mergedTerms,
            rules: preview.mergedRules,
            result: ImportResult(
                termsImported: preview.acceptedTerms.count,
                rulesImported: rulesImportedCount,
                duplicateTermCount: preview.duplicateTerms.count,
                duplicateRuleCount: duplicateRuleCount
            )
        )
    }
}

private struct VoiceInkArchivePayload: Decodable {
    let format: String
    let schemaVersion: Int
    let exportedAt: String?
    let appVersion: String?
    let vocabulary: [VoiceInkVocabularyEntry]
    let replacements: [VoiceInkReplacementEntry]

    enum CodingKeys: String, CodingKey {
        case format
        case schemaVersion
        case exportedAt
        case appVersion
        case vocabulary
        case replacements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        vocabulary = try container.decodeIfPresent([VoiceInkVocabularyEntry].self, forKey: .vocabulary) ?? []
        replacements = try container.decodeIfPresent([VoiceInkReplacementEntry].self, forKey: .replacements) ?? []
        if let stringVal = try? container.decodeIfPresent(String.self, forKey: .exportedAt) {
            exportedAt = stringVal
        } else {
            exportedAt = nil
        }
    }
}

private struct VoiceInkVocabularyEntry: Decodable {
    let term: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case term
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        term = try container.decode(String.self, forKey: .term)
        if let stringVal = try? container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = stringVal
        } else {
            createdAt = nil
        }
    }
}

private struct VoiceInkReplacementEntry: Decodable {
    let sources: [String]
    let replacement: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case sources
        case replacement
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sources = try container.decode([String].self, forKey: .sources)
        replacement = try container.decode(String.self, forKey: .replacement)
        if let stringVal = try? container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = stringVal
        } else {
            createdAt = nil
        }
    }
}

public enum DictionaryArchiveError: Error, LocalizedError, Equatable {
    case unsupportedSchemaVersion(String)
    case unsupportedFormat(String)
    case invalidFile
    case dictionaryChanged

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            "settings.dictionary.archive.error.unsupported_version".localized(with: version)
        case let .unsupportedFormat(format):
            "settings.dictionary.archive.error.unsupported_format".localized(with: format)
        case .invalidFile:
            "settings.dictionary.archive.error.invalid_file".localized
        case .dictionaryChanged:
            "settings.dictionary.archive.error.dictionary_changed".localized
        }
    }
}
