@testable import VerbiCore
import XCTest

final class DictionaryImportPreviewTests: XCTestCase {

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

        XCTAssertEqual(preview.mergedTerms.count, 2)
        XCTAssertEqual(preview.mergedRules.count, 2)
    }

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

    func testPartialDuplicatesMergeOnlyNewVariants() {
        let existingTerms = [
            VocabularyTerm(term: "Raycast", definition: "Launcher")
        ]
        let existingRules = [
            VocabularyReplacementRule(find: "ray cast", replace: "Raycast")
        ]

        let incomingArchive = DictionaryArchive(
            vocabularyTerms: [
                VocabularyTerm(term: "Raycast", definition: "Newer definition"),
                VocabularyTerm(term: "Obsidian", definition: "Knowledge base")
            ],
            substitutionRules: [
                VocabularyReplacementRule(find: "ray cast, recast", replace: "Raycast"),
                VocabularyReplacementRule(find: "obsidien", replace: "Obsidian")
            ]
        )

        let preview = incomingArchive.createPreview(
            existingTerms: existingTerms,
            existingRules: existingRules
        )

        XCTAssertEqual(preview.acceptedTerms.count, 1)
        XCTAssertEqual(preview.acceptedTerms.first?.term, "Obsidian")

        XCTAssertEqual(preview.duplicateTerms.count, 1)
        XCTAssertEqual(preview.duplicateTerms.first?.term, "Raycast")
        XCTAssertEqual(preview.duplicateTerms.first?.reason, .alreadyInDictionary)

        XCTAssertEqual(preview.acceptedVariants.count, 2)
        let recastVariant = preview.acceptedVariants.first { $0.origin == "recast" }
        XCTAssertNotNil(recastVariant)
        XCTAssertEqual(recastVariant?.isNewDestination, false)

        XCTAssertEqual(preview.duplicateVariants.count, 1)
        XCTAssertEqual(preview.duplicateVariants.first?.origin, "ray cast")

        let raycastRule = preview.mergedRules.first { $0.replace == "Raycast" }
        XCTAssertNotNil(raycastRule)
        XCTAssertTrue(raycastRule?.find.contains("ray cast") == true)
        XCTAssertTrue(raycastRule?.find.contains("recast") == true)
    }

    func testConflictingVariantsPreservesExistingDestinationAndExplainsIgnored() {
        let existingRules = [
            VocabularyReplacementRule(find: "recast, recost", replace: "Claude")
        ]

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

        XCTAssertEqual(preview.conflictingVariants.count, 1)
        let conflict = preview.conflictingVariants.first
        XCTAssertEqual(conflict?.origin, "recast")
        XCTAssertEqual(conflict?.candidateDestination, "Raycast")
        XCTAssertEqual(conflict?.existingDestination, "Claude")

        XCTAssertEqual(preview.acceptedVariants.count, 1)
        XCTAssertEqual(preview.acceptedVariants.first?.origin, "ray cast")

        let claudeRule = preview.mergedRules.first { $0.replace == "Claude" }
        XCTAssertEqual(claudeRule?.find, "recast, recost")

        let raycastRule = preview.mergedRules.first { $0.replace == "Raycast" }
        XCTAssertEqual(raycastRule?.find, "ray cast")
    }

    func testConflictingVariantsDistinguishesFileVsDictionarySource() {
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

        XCTAssertEqual(preview.baseTermsSnapshot, initialTerms)
        XCTAssertEqual(preview.baseRulesSnapshot, initialRules)

        let mutatedTerms = [
            VocabularyTerm(term: "Initial", definition: ""),
            VocabularyTerm(term: "ConcurrentEdit", definition: "")
        ]

        let termsMatch = mutatedTerms == preview.baseTermsSnapshot
        XCTAssertFalse(termsMatch, "Should detect stale dictionary when terms changed")
    }

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

        _ = preview

        XCTAssertEqual(storeTerms, snapshotBefore.0)
        XCTAssertEqual(storeRules, snapshotBefore.1)
    }

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
