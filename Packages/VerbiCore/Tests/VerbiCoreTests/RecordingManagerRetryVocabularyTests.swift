import Foundation
@testable import VerbiCore
import VerbiCoreDomain
@testable import VerbiCoreUI
import XCTest

/// Retry vocabulary coverage attached to `RecordingManagerTests`.
/// Run it with `--test RecordingManagerTests`; SwiftPM's file-name filter
/// cannot match extension-only test methods.
@MainActor
extension RecordingManagerTests {
    func testRetryWithCurrentDictionaryAppliesCurrentReplacementRule() async throws {
        let manager = try XCTUnwrap(manager)
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let mockStorage = try XCTUnwrap(mockStorage)
        let settings = AppSettingsStore.shared
        settings.postProcessingEnabled = false

        settings.vocabularyTerms = [VocabularyTerm(term: "Alpha", definition: "Current term")]
        settings.vocabularyReplacementRules = [VocabularyReplacementRule(find: "alpha", replace: "new")]

        let audioURL = try makeRetryVocabularyAudioFile()
        let transcription = makeRetryVocabularyArtifact(
            audioURL: audioURL,
            vocabularySnapshot: VocabularySnapshot(
                terms: [VocabularyTerm(term: "OldTerm", definition: "Old term")],
                replacementRules: [VocabularyReplacementRule(find: "alpha", replace: "old")]
            )
        )
        mockTranscription.mockText = "alpha"

        await manager.retryTranscription(for: transcription, vocabularyIntent: .currentDictionary)

        let saved = try XCTUnwrap(mockStorage.savedTranscriptions.last)
        let configuration = try XCTUnwrap(mockTranscription.lastTranscriptionConfiguration)
        XCTAssertEqual(configuration.providerID, TranscriptionProvider.local.rawValue)
        XCTAssertEqual(configuration.modelID, LocalTranscriptionModel.parakeetTdt06BV3.rawValue)
        XCTAssertEqual(configuration.inputLanguageCode, "en")
        XCTAssertEqual(saved.text, "new")
        XCTAssertEqual(saved.rawText, "alpha")
        XCTAssertEqual(saved.executionProvenance?.vocabularySource, .currentDictionary)
        XCTAssertEqual(saved.executionProvenance?.vocabularySnapshot.terms.map(\.term), ["Alpha"])
        XCTAssertTrue(
            mockTranscription.lastTranscriptionConfiguration?.vocabularyHints?.groqPrompt?.contains("Alpha") == true
        )
    }

    func testRetryWithOriginalSnapshotPreservesPreviousVocabulary() async throws {
        let manager = try XCTUnwrap(manager)
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let mockStorage = try XCTUnwrap(mockStorage)
        let settings = AppSettingsStore.shared
        settings.postProcessingEnabled = false

        settings.vocabularyTerms = [VocabularyTerm(term: "CurrentTerm", definition: "Current term")]
        settings.vocabularyReplacementRules = [VocabularyReplacementRule(find: "alpha", replace: "new")]

        let audioURL = try makeRetryVocabularyAudioFile()
        let transcription = makeRetryVocabularyArtifact(
            audioURL: audioURL,
            vocabularySnapshot: VocabularySnapshot(
                terms: [VocabularyTerm(term: "OldTerm", definition: "Old term")],
                replacementRules: [VocabularyReplacementRule(find: "alpha", replace: "old")]
            )
        )
        mockTranscription.mockText = "alpha"

        await manager.retryTranscription(for: transcription, vocabularyIntent: .originalSnapshot)

        let saved = try XCTUnwrap(mockStorage.savedTranscriptions.last)
        XCTAssertEqual(saved.text, "old")
        XCTAssertEqual(saved.rawText, "alpha")
        XCTAssertEqual(saved.executionProvenance?.vocabularySource, .originalSnapshot)
        XCTAssertEqual(saved.executionProvenance?.vocabularySnapshot.terms.map(\.term), ["OldTerm"])
        XCTAssertTrue(
            mockTranscription.lastTranscriptionConfiguration?.vocabularyHints?.groqPrompt?.contains("OldTerm") == true
        )
    }

    func testRetryWithoutOriginalSnapshotFallsBackToCurrentDictionaryExplicitly() async throws {
        let manager = try XCTUnwrap(manager)
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let mockStorage = try XCTUnwrap(mockStorage)
        let settings = AppSettingsStore.shared
        settings.postProcessingEnabled = false

        settings.vocabularyReplacementRules = [VocabularyReplacementRule(find: "alpha", replace: "current")]

        let audioURL = try makeRetryVocabularyAudioFile()
        let transcription = makeRetryVocabularyArtifact(audioURL: audioURL, vocabularySnapshot: nil)
        mockTranscription.mockText = "alpha"

        await manager.retryTranscription(for: transcription, vocabularyIntent: .originalSnapshot)

        let saved = try XCTUnwrap(mockStorage.savedTranscriptions.last)
        XCTAssertEqual(saved.text, "current")
        XCTAssertEqual(saved.executionProvenance?.vocabularySource, .currentDictionaryFallback)
    }

    func testRetryModelOverrideKeepsProviderAndUsesSelectedModelWithCurrentDictionary() async throws {
        let manager = try XCTUnwrap(manager)
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let mockStorage = try XCTUnwrap(mockStorage)
        let settings = AppSettingsStore.shared
        settings.postProcessingEnabled = false

        readyRetryProviders = [.groq]
        settings.vocabularyReplacementRules = [VocabularyReplacementRule(find: "alpha", replace: "current")]

        let audioURL = try makeRetryVocabularyAudioFile()
        let persistedModelID = LocalTranscriptionModel.parakeetTdt06BV3.rawValue
        let overrideModelID = TranscriptionProvider.groqPresetModelIDs[0]
        let transcription = makeRetryVocabularyArtifact(
            audioURL: audioURL,
            vocabularySnapshot: .empty,
            provider: .local,
            modelID: persistedModelID,
            capturePurpose: .dictation
        )
        mockTranscription.mockText = "alpha"

        await manager.retryTranscription(
            for: transcription,
            vocabularyIntent: .currentDictionary,
            selectionOverride: TranscriptionProviderSelection(provider: .groq, selectedModel: overrideModelID)
        )

        let configuration = try XCTUnwrap(mockTranscription.lastTranscriptionConfiguration)
        XCTAssertEqual(configuration.providerID, TranscriptionProvider.groq.rawValue)
        XCTAssertEqual(configuration.modelID, overrideModelID)

        let saved = try XCTUnwrap(mockStorage.savedTranscriptions.last)
        XCTAssertEqual(saved.executionProvenance?.transcriptionModelIdentity.providerID, TranscriptionProvider.groq.rawValue)
        XCTAssertEqual(saved.executionProvenance?.transcriptionModelIdentity.modelID, overrideModelID)
        XCTAssertEqual(saved.executionProvenance?.vocabularySource, .currentDictionary)
    }

    func testRetryFailurePreservesArtifactAndRecordsEffectiveVocabularySource() async throws {
        let manager = try XCTUnwrap(manager)
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let mockStorage = try XCTUnwrap(mockStorage)
        let settings = AppSettingsStore.shared
        settings.postProcessingEnabled = false

        settings.vocabularyReplacementRules = [VocabularyReplacementRule(find: "alpha", replace: "current")]

        let audioURL = try makeRetryVocabularyAudioFile()
        let transcription = makeRetryVocabularyArtifact(
            audioURL: audioURL,
            vocabularySnapshot: VocabularySnapshot(
                terms: [],
                replacementRules: [VocabularyReplacementRule(find: "alpha", replace: "old")]
            ),
            text: "Original text"
        )
        mockTranscription.shouldFailTranscription = true

        await manager.retryTranscription(for: transcription, vocabularyIntent: .currentDictionary)

        XCTAssertTrue(mockStorage.savedTranscriptions.isEmpty)
        XCTAssertEqual(transcription.text, "Original text")

        let failedAttempt = try XCTUnwrap(
            mockStorage.savedModelPerformanceAttempts.last { $0.attemptKind == .retry }
        )
        XCTAssertEqual(failedAttempt.status, .failed)
        XCTAssertEqual(failedAttempt.executionProvenance?.vocabularySource, .currentDictionary)
        XCTAssertNotNil(manager.lastError)
    }

    func testRetryOriginalSnapshotWithModelOverrideKeepsSelectedModelAndLanguage() async throws {
        let manager = try XCTUnwrap(manager)
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let mockStorage = try XCTUnwrap(mockStorage)
        let settings = AppSettingsStore.shared
        settings.postProcessingEnabled = false

        readyRetryProviders = [.groq]
        settings.vocabularyReplacementRules = [VocabularyReplacementRule(find: "alpha", replace: "new")]

        let audioURL = try makeRetryVocabularyAudioFile()
        let overrideModelID = TranscriptionProvider.groqPresetModelIDs[0]
        let transcription = makeRetryVocabularyArtifact(
            audioURL: audioURL,
            vocabularySnapshot: VocabularySnapshot(
                terms: [VocabularyTerm(term: "OldTerm", definition: "Old term")],
                replacementRules: [VocabularyReplacementRule(find: "alpha", replace: "old")]
            ),
            capturePurpose: .dictation
        )
        mockTranscription.mockText = "alpha"

        await manager.retryTranscription(
            for: transcription,
            vocabularyIntent: .originalSnapshot,
            selectionOverride: TranscriptionProviderSelection(provider: .groq, selectedModel: overrideModelID)
        )

        let configuration = try XCTUnwrap(mockTranscription.lastTranscriptionConfiguration)
        XCTAssertEqual(configuration.providerID, TranscriptionProvider.groq.rawValue)
        XCTAssertEqual(configuration.modelID, overrideModelID)
        XCTAssertEqual(configuration.inputLanguageCode, "en")

        let saved = try XCTUnwrap(mockStorage.savedTranscriptions.last)
        XCTAssertEqual(saved.text, "old")
        XCTAssertEqual(saved.executionProvenance?.vocabularySource, .originalSnapshot)
        XCTAssertEqual(saved.executionProvenance?.transcriptionModelIdentity.providerID, TranscriptionProvider.groq.rawValue)
        XCTAssertEqual(saved.executionProvenance?.transcriptionModelIdentity.modelID, overrideModelID)
    }

    func testRetryAfterReprocessingLegacyArtifactFallsBackToCurrentDictionary() async throws {
        let manager = try XCTUnwrap(manager)
        let mockTranscription = try XCTUnwrap(mockTranscription)
        let mockStorage = try XCTUnwrap(mockStorage)
        let settings = AppSettingsStore.shared
        settings.postProcessingEnabled = false

        settings.vocabularyReplacementRules = [VocabularyReplacementRule(find: "alpha", replace: "current")]

        let audioURL = try makeRetryVocabularyAudioFile()
        let legacyArtifact = makeRetryVocabularyArtifact(audioURL: audioURL, vocabularySnapshot: nil)
        let reprocessedProvenance = TranscriptionLibraryViewModel.makeReprocessProvenance(
            transcription: legacyArtifact,
            prompt: PostProcessingPrompt(title: "Prompt", promptText: "Prompt text", isActive: true),
            selection: EnhancementsAISelection(provider: .openai, selectedModel: "gpt-4o-mini"),
            identity: ModelPerformanceModelIdentity(
                providerID: "openai",
                providerDisplayName: "OpenAI",
                modelID: "gpt-4o-mini",
                modelDisplayName: "GPT-4o mini",
                runtimeKind: .unknown
            ),
            mode: .meeting,
            useStructuredPipeline: true
        )
        XCTAssertEqual(reprocessedProvenance.vocabularySource, .notRecorded)

        let reprocessedArtifact = CaptureArtifact(
            id: legacyArtifact.id,
            meeting: legacyArtifact.meeting,
            text: legacyArtifact.text,
            rawText: legacyArtifact.rawText,
            language: legacyArtifact.language,
            modelName: legacyArtifact.modelName,
            executionProvenance: reprocessedProvenance
        )
        mockTranscription.mockText = "alpha"
        mockTranscription.mockSegments = [
            CaptureArtifact.Segment(speaker: "Speaker", text: "alpha", startTime: 0, endTime: 1)
        ]

        await manager.retryTranscription(for: reprocessedArtifact, vocabularyIntent: .originalSnapshot)

        let saved = try XCTUnwrap(mockStorage.savedTranscriptions.last)
        XCTAssertEqual(saved.segments.first?.text, "current")
        XCTAssertEqual(saved.executionProvenance?.vocabularySource, .currentDictionaryFallback)
    }

    // MARK: - Helpers

    private func makeRetryVocabularyArtifact(
        audioURL: URL,
        vocabularySnapshot: VocabularySnapshot?,
        provider: TranscriptionProvider = .local,
        modelID: String? = nil,
        capturePurpose: CapturePurpose = .meeting,
        text: String = "Existing"
    ) -> CaptureArtifact {
        let resolvedModelID = modelID ?? LocalTranscriptionModel.parakeetTdt06BV3.rawValue
        let provenance = vocabularySnapshot.map { snapshot in
            ExecutionProvenance(
                transcriptionRequest: DomainTranscriptionRequestConfiguration(
                    providerID: provider.rawValue,
                    modelID: resolvedModelID,
                    inputLanguageCode: "en"
                ),
                vocabularySnapshot: snapshot,
                transcriptionModelIdentity: provider.modelPerformanceIdentity(modelID: resolvedModelID)
            )
        }
        return CaptureArtifact(
            meeting: CaptureSession(app: .zoom, capturePurpose: capturePurpose, audioFilePath: audioURL.path),
            text: text,
            rawText: text,
            language: "en",
            modelName: resolvedModelID,
            executionProvenance: provenance
        )
    }

    private func makeRetryVocabularyAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try Data(repeating: 0, count: 256).write(to: url)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
