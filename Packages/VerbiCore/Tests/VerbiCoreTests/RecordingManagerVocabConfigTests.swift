@testable import VerbiCoreDomain
@testable import VerbiCoreInfrastructure
@testable import VerbiCoreUI
import XCTest

@MainActor
final class RecordingManagerVocabConfigTests: XCTestCase {
    func testMakeDomainTranscriptionConfiguration_AttachesNonEmptyHints() throws {
        let manager = RecordingManager.shared
        let hints = VocabularyProviderHints(
            groqPrompt: "SwiftUI, Metal",
            elevenLabsKeyterms: ["SwiftUI", "Metal"],
        )

        let configuration = manager.makeDomainTranscriptionConfiguration(
            from: nil,
            vocabularyHints: hints,
            capturePurpose: .meeting,
        )

        let resolved = try XCTUnwrap(configuration)
        XCTAssertEqual(resolved.vocabularyHints?.groqPrompt, "SwiftUI, Metal")
        XCTAssertEqual(resolved.vocabularyHints?.elevenLabsKeyterms, ["SwiftUI", "Metal"])
        XCTAssertFalse(resolved.providerID.isEmpty)
        XCTAssertFalse(resolved.modelID.isEmpty)
    }

    func testMakeDomainTranscriptionConfiguration_OmitsEmptyHintsWithoutDictationConfig() {
        let manager = RecordingManager.shared
        let configuration = manager.makeDomainTranscriptionConfiguration(
            from: nil,
            vocabularyHints: .empty,
            capturePurpose: .meeting,
        )
        XCTAssertNil(configuration)
    }

    func testMakeDomainTranscriptionConfiguration_PreservesDictationSelectionWithHints() throws {
        let manager = RecordingManager.shared
        let dictationConfiguration = DictationTranscriptionConfiguration(
            selection: TranscriptionProviderSelection(provider: .groq, selectedModel: "whisper-large-v3-turbo"),
            inputLanguageCode: "en",
        )
        let hints = VocabularyProviderHints(groqPrompt: "Prisma", elevenLabsKeyterms: ["Prisma"])

        let configuration = manager.makeDomainTranscriptionConfiguration(
            from: dictationConfiguration,
            vocabularyHints: hints,
            capturePurpose: .dictation,
        )

        let resolved = try XCTUnwrap(configuration)
        XCTAssertEqual(resolved.providerID, TranscriptionProvider.groq.rawValue)
        XCTAssertEqual(resolved.modelID, "whisper-large-v3-turbo")
        XCTAssertEqual(resolved.inputLanguageCode, "en")
        XCTAssertEqual(resolved.vocabularyHints?.groqPrompt, "Prisma")
    }
}
