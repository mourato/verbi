@testable import VerbiCore
import XCTest

final class DictionaryImportPreviewTests: XCTestCase {
    // MARK: - Round-Trip Verbi Archive

    func testVerbiRoundTripImportPreview() throws {
        let terms = [
            VocabularyTerm(term: "SwiftUI", definition: "Apple declarative UI"),
            VocabularyTerm(term: "Metal", definition: "GPU graphics")
        ]
        let rules = [
            VocabularyReplacementRule(find: "swift ui, swift-ui", replace: "SwiftUI"),
            VocabularyReplacementRule(find: "x code", replace: "Xcode")
        ]

        let archive = DictionaryArchive(
            vocabularyTerms: terms,
            substitutionRules: rules
        )

        let data = try JSONEncoder().encode(archive)
        let validationResult = DictionaryArchive.validate(data: data)

        guard case let .success(validatedArchive) = validationResult else {
            return XCTFail("Expected valid archive")
        }

        let preview = validatedArchive.createPreview(existingTerms: [], existingRules: [])

        XCTAssertTrue(preview.hasImportableChanges)
        XCTAssertEqual(preview.acceptedTerms.count, 2)
        XCTAssertEqual(preview.acceptedVariants.count, 3)
        XCTAssertEqual(preview.duplicateTerms.count, 0)
        XCTAssertEqual(preview.duplicateVariants.count, 0)
        XCTAssertEqual(preview.conflictingVariants.count, 0)
        XCTAssertEqual(preview.invalidTerms.count, 0)
        XCTAssertEqual(preview.invalidVariants.count, 0)

        // Merged outputs
        XCTAssertEqual(preview.mergedTerms.count, 2)
        XCTAssertEqual(preview.mergedRules.count, 2)
    }

    // MARK: - VoiceInk Schema Version 1 Format

    func testVoiceInkFormatImportPreview() {
        let voiceInkJSON = """
        {
          "format": "voiceink.dictionary",
          "schemaVersion": 1,
          "appVersion": "1.4.0",
          "exportedAt": "2026-03-24T18:00:00Z",
          "vocabulary": [
            { "term": "Kubernetes", "createdAt": "2026-03-01T10:00:00Z" },
            { "term": "Docker" }
          ],
          "replacements": [
            {
              "sources": ["k8s", "cube netes"],
              "replacement": "Kubernetes",
              "createdAt": "2026-03-01T10:05:00Z"
            },
            {
              "sources": ["dockr"],
              "replacement": "Docker"
            }
          ]
        }
        """

        let data = Data(voiceInkJSON.utf8)
        let validationResult = DictionaryArchive.validate(data: data)

        guard case let .success(archive) = validationResult else {
            return XCTFail("Expected valid VoiceInk archive")
        }

        XCTAssertEqual(archive.sourceApp, "VoiceInk")
        XCTAssertEqual(archive.schemaVersion, "voiceink.dictionary_v1")
        XCTAssertEqual(archive.vocabularyTerms.count, 2)
        XCTAssertEqual(archive.substitutionRules.count, 2)

        let preview = archive.createPreview(existingTerms: [], existingRules: [])

        XCTAssertTrue(preview.hasImportableChanges)
        XCTAssertEqual(preview.acceptedTerms.count, 2)
        XCTAssertEqual(preview.acceptedVariants.count, 3)
        XCTAssertEqual(Set(preview.mergedTerms.map(\.term)), Set(["Kubernetes", "Docker"]))
    }

    // MARK: - Partial Duplicates

    func testPartialDuplicatesMergeOnlyNewVariants() {
        let existingTerms = [
            VocabularyTerm(term: "Raycast", definition: "Launcher")
        ]
        let existingRules = [
            VocabularyReplacementRule(find: "ray cast", replace: "Raycast")
        ]

        let incomingArchive = DictionaryArchive(
            vocabularyTerms: [
                VocabularyTerm(term: "Raycast", definition: "Newer definition"), // Duplicate
                VocabularyTerm(term: "Obsidian", definition: "Knowledge base") // New
            ],
            substitutionRules: [
                // "ray cast" is duplicate; "recast" is new variant for same destination!
                VocabularyReplacementRule(find: "ray cast, recast", replace: "Raycast"),
                VocabularyReplacementRule(find: "obsidien", replace: "Obsidian")
            ]
        )

        let preview = incomingArchive.createPreview(
            existingTerms: existingTerms,
            existingRules: existingRules
        )

        // Accepted terms: Obsidian
        XCTAssertEqual(preview.acceptedTerms.count, 1)
        XCTAssertEqual(preview.acceptedTerms.first?.term, "Obsidian")

        // Duplicate terms: Raycast
        XCTAssertEqual(preview.duplicateTerms.count, 1)
        XCTAssertEqual(preview.duplicateTerms.first?.term, "Raycast")
        XCTAssertEqual(preview.duplicateTerms.first?.reason, .alreadyInDictionary)

        // Accepted variants: "recast" (under Raycast) and "obsidien" (under Obsidian)
        XCTAssertEqual(preview.acceptedVariants.count, 2)
        let recastVariant = preview.acceptedVariants.first { $0.origin == "recast" }
        XCTAssertNotNil(recastVariant)
        XCTAssertEqual(recastVariant?.isNewDestination, false) // Merging into existing destination rule

        // Duplicate variants: "ray cast"
        XCTAssertEqual(preview.duplicateVariants.count, 1)
        XCTAssertEqual(preview.duplicateVariants.first?.origin, "ray cast")

        // In merged rules: "Raycast" destination now has BOTH origins without dropping anything
        let raycastRule = preview.mergedRules.first { $0.replace == "Raycast" }
        XCTAssertNotNil(raycastRule)
        XCTAssertTrue(raycastRule?.find.contains("ray cast") == true)
        XCTAssertTrue(raycastRule?.find.contains("recast") == true)
    }

    // MARK: - Conflicting Variants Preserve Existing Destination

    func testConflictingVariantsPreservesExistingDestinationAndExplainsIgnored() {
        // Existing has "recast" -> "Claude"
        let existingRules = [
            VocabularyReplacementRule(find: "recast, recost", replace: "Claude")
        ]

        // Incoming wants "recast" -> "Raycast" and "ray cast" -> "Raycast"
        let incomingArchive = DictionaryArchive(
            vocabularyTerms: [],
            substitutionRules: [
                VocabularyReplacementRule(find: "recast, ray cast", replace: "Raycast")
            ]
        )

        let preview = incomingArchive.createPreview(
            existingTerms: [],
            existingRules: existingRules
        )

        // "recast" is conflicting because it already points to "Claude"
        XCTAssertEqual(preview.conflictingVariants.count, 1)
        let conflict = preview.conflictingVariants.first
        XCTAssertEqual(conflict?.origin, "recast")
        XCTAssertEqual(conflict?.candidateDestination, "Raycast")
        XCTAssertEqual(conflict?.existingDestination, "Claude")

        // "ray cast" is valid and new, so it is accepted!
        XCTAssertEqual(preview.acceptedVariants.count, 1)
        XCTAssertEqual(preview.acceptedVariants.first?.origin, "ray cast")

        // Merged rules: "Claude" keeps "recast, recost" intact!
        let claudeRule = preview.mergedRules.first { $0.replace == "Claude" }
        XCTAssertEqual(claudeRule?.find, "recast, recost")

        // Raycast rule only has "ray cast"
        let raycastRule = preview.mergedRules.first { $0.replace == "Raycast" }
        XCTAssertEqual(raycastRule?.find, "ray cast")
    }

    func testConflictingVariantsDistinguishesFileVsDictionarySource() {
        // 1. Intra-file conflict: empty existing dictionary, 2 rules in same archive pointing "llm" to different destinations
        let archiveWithFileConflict = DictionaryArchive(
            vocabularyTerms: [],
            substitutionRules: [
                VocabularyReplacementRule(find: "llm", replace: "Large Language Model"),
                VocabularyReplacementRule(find: "llm", replace: "Local Language Model")
            ]
        )

        let previewFile = archiveWithFileConflict.createPreview(existingTerms: [], existingRules: [])
        XCTAssertEqual(previewFile.acceptedVariants.count, 1)
        XCTAssertEqual(previewFile.acceptedVariants.first?.destination, "Large Language Model")
        XCTAssertEqual(previewFile.conflictingVariants.count, 1)

        let fileConflict = previewFile.conflictingVariants[0]
        XCTAssertEqual(fileConflict.origin, "llm")
        XCTAssertEqual(fileConflict.candidateDestination, "Local Language Model")
        XCTAssertEqual(fileConflict.existingDestination, "Large Language Model")
        XCTAssertEqual(fileConflict.source, .earlierInFile)

        // 2. Existing dictionary conflict:
        let existingRules = [
            VocabularyReplacementRule(find: "gpu", replace: "Graphics Processing Unit")
        ]
        let archiveWithDictionaryConflict = DictionaryArchive(
            vocabularyTerms: [],
            substitutionRules: [
                VocabularyReplacementRule(find: "gpu", replace: "General Processing Unit")
            ]
        )

        let previewDict = archiveWithDictionaryConflict.createPreview(existingTerms: [], existingRules: existingRules)
        XCTAssertEqual(previewDict.conflictingVariants.count, 1)
        let dictConflict = previewDict.conflictingVariants[0]
        XCTAssertEqual(dictConflict.origin, "gpu")
        XCTAssertEqual(dictConflict.candidateDestination, "General Processing Unit")
        XCTAssertEqual(dictConflict.existingDestination, "Graphics Processing Unit")
        XCTAssertEqual(dictConflict.source, .existingDictionary)
    }

    // MARK: - Rejection of Unknown Schema Versions and Formats

    func testRejectsUnknownVoiceInkSchemaVersion() {
        let futureVoiceInk = """
        {
          "format": "voiceink.dictionary",
          "schemaVersion": 2,
          "vocabulary": [],
          "replacements": []
        }
        """

        let result = DictionaryArchive.validate(data: Data(futureVoiceInk.utf8))
        switch result {
        case .success:
            XCTFail("Should reject VoiceInk schemaVersion 2")
        case let .failure(error as DictionaryArchiveError):
            guard case let .unsupportedSchemaVersion(version) = error else {
                return XCTFail("Expected unsupportedSchemaVersion error, got \(error)")
            }
            XCTAssertTrue(version.contains("2"))
        case let .failure(other):
            XCTFail("Expected DictionaryArchiveError, got \(other)")
        }
    }

    func testRejectsUnknownVerbiSchemaVersion() {
        let futureVerbi = """
        {
          "schemaVersion": "dictionary_v99",
          "sourceApp": "Verbi",
          "vocabularyTerms": [],
          "substitutionRules": []
        }
        """

        let result = DictionaryArchive.validate(data: Data(futureVerbi.utf8))
        switch result {
        case .success:
            XCTFail("Should reject Verbi schemaVersion dictionary_v99")
        case let .failure(error as DictionaryArchiveError):
            guard case let .unsupportedSchemaVersion(version) = error else {
                return XCTFail("Expected unsupportedSchemaVersion error, got \(error)")
            }
            XCTAssertEqual(version, "dictionary_v99")
        case let .failure(other):
            XCTFail("Expected DictionaryArchiveError, got \(other)")
        }
    }

    func testRejectsUnsupportedFormat() {
        let otherFormat = """
        {
          "format": "super_transcriber_format",
          "schemaVersion": 1
        }
        """

        let result = DictionaryArchive.validate(data: Data(otherFormat.utf8))
        switch result {
        case .success:
            XCTFail("Should reject unsupported format")
        case let .failure(error as DictionaryArchiveError):
            guard case let .unsupportedFormat(format) = error else {
                return XCTFail("Expected unsupportedFormat error, got \(error)")
            }
            XCTAssertEqual(format, "super_transcriber_format")
        case let .failure(other):
            XCTFail("Expected DictionaryArchiveError, got \(other)")
        }
    }

    func testRejectsCorruptJSONWithoutPartialModification() {
        let garbage = Data("<<<NOT JSON>>>".utf8)
        let result = DictionaryArchive.validate(data: garbage)
        switch result {
        case .success:
            XCTFail("Should reject corrupt data")
        case let .failure(error as DictionaryArchiveError):
            guard case .invalidFile = error else {
                return XCTFail("Expected invalidFile, got \(error)")
            }
        case let .failure(other):
            XCTFail("Expected DictionaryArchiveError, got \(other)")
        }
    }

    // MARK: - Stale Dictionary Snapshot Detection

    func testStaleDictionaryDetection() {
        let initialTerms = [VocabularyTerm(term: "Initial", definition: "")]
        let initialRules = [VocabularyReplacementRule(find: "init", replace: "Initial")]

        let incomingArchive = DictionaryArchive(
            vocabularyTerms: [VocabularyTerm(term: "Incoming", definition: "")],
            substitutionRules: []
        )

        let preview = incomingArchive.createPreview(
            existingTerms: initialTerms,
            existingRules: initialRules
        )

        // Snapshot recorded in preview matches initial
        XCTAssertEqual(preview.baseTermsSnapshot, initialTerms)
        XCTAssertEqual(preview.baseRulesSnapshot, initialRules)

        // If the dictionary changed before confirmation:
        let mutatedTerms = [
            VocabularyTerm(term: "Initial", definition: ""),
            VocabularyTerm(term: "ConcurrentEdit", definition: "")
        ]

        let termsMatch = mutatedTerms == preview.baseTermsSnapshot
        XCTAssertFalse(termsMatch, "Should detect stale dictionary when terms changed")
    }

    // MARK: - Cancellation Leaves Dictionary Untouched

    func testCancellationModifiesNothing() {
        let storeTerms = [VocabularyTerm(term: "Original", definition: "Original definition")]
        let storeRules = [VocabularyReplacementRule(find: "orig", replace: "Original")]

        let snapshotBefore = (storeTerms, storeRules)

        let incomingArchive = DictionaryArchive(
            vocabularyTerms: [VocabularyTerm(term: "ShouldNotApply", definition: "")],
            substitutionRules: [VocabularyReplacementRule(find: "nope", replace: "Nope")]
        )

        let preview = incomingArchive.createPreview(
            existingTerms: storeTerms,
            existingRules: storeRules
        )

        XCTAssertTrue(preview.hasImportableChanges)

        // Simulate Cancel action: we dismiss preview and do not touch store
        _ = preview // Cancel simply drops the preview

        XCTAssertEqual(storeTerms, snapshotBefore.0)
        XCTAssertEqual(storeRules, snapshotBefore.1)
    }

    // MARK: - Invalid Entries Ignored

    func testInvalidEntriesAreFiltered() {
        let archive = DictionaryArchive(
            vocabularyTerms: [
                VocabularyTerm(term: "   ", definition: "blank term"),
                VocabularyTerm(term: "ValidTerm", definition: "")
            ],
            substitutionRules: [
                VocabularyReplacementRule(find: "  ,  ", replace: "EmptyOrigins"),
                VocabularyReplacementRule(find: "ok", replace: "ValidRule")
            ]
        )

        let preview = archive.createPreview(existingTerms: [], existingRules: [])

        XCTAssertEqual(preview.invalidTerms.count, 1)
        XCTAssertEqual(preview.acceptedTerms.count, 1)
        XCTAssertEqual(preview.acceptedTerms.first?.term, "ValidTerm")

        XCTAssertEqual(preview.invalidVariants.count, 1)
        XCTAssertEqual(preview.acceptedVariants.count, 1)
        XCTAssertEqual(preview.acceptedVariants.first?.destination, "ValidRule")
    }
}
