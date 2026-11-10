import Foundation
@testable import VerbiCore
import VerbiCoreDomain
import VerbiCoreInfrastructure
@testable import VerbiCoreUI
import XCTest

final class RetryVocabularyIntentTests: XCTestCase {
    private let persistedSnapshot = VocabularySnapshot(
        terms: [VocabularyTerm(term: "Persisted", definition: "Saved with the capture")],
        replacementRules: [VocabularyReplacementRule(find: "old", replace: "previous")]
    )
    private let currentSnapshot = VocabularySnapshot(
        terms: [VocabularyTerm(term: "Current", definition: "Present now")],
        replacementRules: [VocabularyReplacementRule(find: "new", replace: "today")]
    )

    func testCurrentDictionaryIntentUsesCurrentSnapshot() {
        let resolution = RetryVocabularyResolver.resolve(
            intent: .currentDictionary,
            persistedSnapshot: persistedSnapshot,
            persistedSource: .originalSnapshot,
            current: currentSnapshot
        )

        XCTAssertEqual(resolution.snapshot, currentSnapshot)
        XCTAssertEqual(resolution.source, .currentDictionary)
    }

    func testOriginalSnapshotIntentUsesPersistedSnapshot() {
        let resolution = RetryVocabularyResolver.resolve(
            intent: .originalSnapshot,
            persistedSnapshot: persistedSnapshot,
            persistedSource: .originalSnapshot,
            current: currentSnapshot
        )

        XCTAssertEqual(resolution.snapshot, persistedSnapshot)
        XCTAssertEqual(resolution.source, .originalSnapshot)
    }

    func testOriginalSnapshotIntentFallsBackExplicitlyWhenArtifactHasNoSnapshot() {
        let resolution = RetryVocabularyResolver.resolve(
            intent: .originalSnapshot,
            persistedSnapshot: nil,
            persistedSource: nil,
            current: currentSnapshot
        )

        XCTAssertEqual(resolution.snapshot, currentSnapshot)
        XCTAssertEqual(resolution.source, .currentDictionaryFallback)
    }

    func testOriginalSnapshotIntentFallsBackWhenSourceIsNotRecorded() {
        let resolution = RetryVocabularyResolver.resolve(
            intent: .originalSnapshot,
            persistedSnapshot: .empty,
            persistedSource: .notRecorded,
            current: currentSnapshot
        )

        XCTAssertEqual(resolution.snapshot, currentSnapshot)
        XCTAssertEqual(resolution.source, .currentDictionaryFallback)
    }

    func testPendingRetryReportsOriginalUnavailableWithoutSnapshot() {
        let metadata = makeMetadata()
        let withoutSnapshot = PendingRetryTranscription(
            metadata: metadata,
            selectionOverride: nil,
            originalVocabulary: nil,
            originalVocabularySource: nil
        )
        let withSnapshot = PendingRetryTranscription(
            metadata: metadata,
            selectionOverride: nil,
            originalVocabulary: persistedSnapshot,
            originalVocabularySource: .originalSnapshot
        )
        let notRecorded = PendingRetryTranscription(
            metadata: metadata,
            selectionOverride: nil,
            originalVocabulary: .empty,
            originalVocabularySource: .notRecorded
        )

        XCTAssertFalse(withoutSnapshot.hasOriginalVocabulary)
        XCTAssertTrue(withSnapshot.hasOriginalVocabulary)
        XCTAssertFalse(notRecorded.hasOriginalVocabulary)
    }

    func testExecutionProvenanceDecodesLegacyJSONWithoutVocabularySource() throws {
        let provenance = makeProvenance(vocabularySource: .originalSnapshot)
        let encoded = try JSONEncoder().encode(provenance)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNotNil(object.removeValue(forKey: "vocabularySource"))

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(ExecutionProvenance.self, from: legacyData)

        XCTAssertNil(decoded.vocabularySource)
        XCTAssertEqual(decoded.vocabularySnapshot, provenance.vocabularySnapshot)
    }

    func testExecutionProvenanceRoundTripsVocabularySource() throws {
        for source in [
            ExecutionVocabularySource.originalSnapshot,
            .currentDictionary,
            .currentDictionaryFallback,
            .notRecorded
        ] {
            let provenance = makeProvenance(vocabularySource: source)
            let decoded = try JSONDecoder().decode(
                ExecutionProvenance.self,
                from: JSONEncoder().encode(provenance)
            )
            XCTAssertEqual(decoded.vocabularySource, source)
        }
    }

    private func makeProvenance(vocabularySource: ExecutionVocabularySource) -> ExecutionProvenance {
        ExecutionProvenance(
            transcriptionRequest: DomainTranscriptionRequestConfiguration(
                providerID: TranscriptionProvider.local.rawValue,
                modelID: LocalTranscriptionModel.parakeetTdt06BV3.rawValue,
                inputLanguageCode: "en"
            ),
            vocabularySnapshot: persistedSnapshot,
            vocabularySource: vocabularySource,
            transcriptionModelIdentity: ModelPerformanceModelIdentity(
                providerID: "local",
                providerDisplayName: "Local",
                modelID: "parakeet",
                modelDisplayName: "Parakeet",
                runtimeKind: .unknown
            )
        )
    }

    private func makeMetadata() -> TranscriptionMetadata {
        TranscriptionMetadata(
            id: UUID(),
            meetingId: UUID(),
            appName: "Zoom",
            appRawValue: CaptureOrigin.zoom.rawValue,
            appBundleIdentifier: "us.zoom.xos",
            startTime: Date(),
            createdAt: Date(),
            previewText: "preview",
            wordCount: 1,
            language: "en",
            isPostProcessed: false,
            duration: 10,
            audioFilePath: nil,
            inputSource: nil
        )
    }
}
