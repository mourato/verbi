import CoreData
@testable import VerbiCore
@testable import VerbiCoreUI
import XCTest

/// Proves that deleting dictionary entries uses the real settings use cases and
/// leaves already persisted artifacts untouched through the real repository.
@MainActor
final class RetryVocabularyPersistenceTests: XCTestCase {
    private var stack: CoreDataStack!
    private var repository: CoreDataTranscriptionStorageRepository!

    override func setUp() async throws {
        try await super.setUp()
        try AppSettingsTestIsolationLock.acquire()
        AppSettingsStore.shared.resetToDefaults()
        stack = CoreDataStack(name: "RetryVocabularyPersistenceTests", inMemory: true)
        repository = CoreDataTranscriptionStorageRepository(stack: stack)
    }

    override func tearDown() async throws {
        repository = nil
        stack = nil
        AppSettingsStore.shared.resetToDefaults()
        AppSettingsTestIsolationLock.release()
        try await super.tearDown()
    }

    func testDeletingDictionaryEntriesDoesNotRewriteStoredSnapshot() async throws {
        let term = VocabularyTerm(term: "Alpha", definition: "Saved with the artifact")
        let rule = VocabularyReplacementRule(find: "alpha", replace: "Beta")
        let settings = AppSettingsStore.shared
        settings.vocabularyTerms = [term]
        settings.vocabularyReplacementRules = [rule]

        let entity = makeEntity(
            snapshot: VocabularySnapshot(terms: [term], replacementRules: [rule])
        )
        try await repository.saveTranscription(entity)

        VocabularyTermsSettingsViewModel(settings: settings).removeTerm(term)

        let rulesViewModel = VocabularySettingsViewModel(settings: settings)
        let group = try XCTUnwrap(
            rulesViewModel.groups.first { $0.destinationKey == VocabularyNormalization.destinationKey("Beta") }
        )
        rulesViewModel.confirmDelete(group)
        rulesViewModel.executeDelete()

        XCTAssertTrue(settings.vocabularyTerms.isEmpty)
        XCTAssertTrue(settings.vocabularyReplacementRules.isEmpty)

        let fetched = try await repository.fetchTranscription(by: entity.id)
        let reloaded = try XCTUnwrap(fetched)
        let snapshot = try XCTUnwrap(reloaded.executionProvenance?.vocabularySnapshot)
        XCTAssertEqual(snapshot.terms.map(\.term), ["Alpha"])
        XCTAssertEqual(snapshot.replacementRules.map(\.find), ["alpha"])
        XCTAssertEqual(reloaded.executionProvenance?.vocabularySource, .originalSnapshot)
    }

    private func makeEntity(snapshot: VocabularySnapshot) -> CaptureArtifactEntity {
        var config = CaptureArtifactEntity.Configuration(
            text: "Original text",
            language: "en"
        )
        config.modelName = "parakeet-tdt-0.6b-v3-coreml"
        config.executionProvenance = ExecutionProvenance(
            transcriptionRequest: DomainTranscriptionRequestConfiguration(
                providerID: TranscriptionProvider.local.rawValue,
                modelID: LocalTranscriptionModel.parakeetTdt06BV3.rawValue,
                inputLanguageCode: "en"
            ),
            vocabularySnapshot: snapshot,
            vocabularySource: .originalSnapshot,
            transcriptionModelIdentity: TranscriptionProvider.local.modelPerformanceIdentity(
                modelID: LocalTranscriptionModel.parakeetTdt06BV3.rawValue
            )
        )
        return CaptureArtifactEntity(
            meeting: CaptureSessionEntity(app: .zoom, capturePurpose: .meeting),
            config: config
        )
    }
}
