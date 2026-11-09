// The vocabulary capability mapping follows the resolved transcription
// selection per capture mode: meeting transcription always resolves to
// local ASR, so it reports `.none` regardless of the configured dictation
// provider, while dictation and assistant report the configured provider's
// mapping. This guards the support shown in Settings > Dictionary for the
// mode the user actually records.
@testable import VerbiCore
import VerbiCoreInfrastructure
import XCTest

@MainActor
final class TranscriptionVocabularyModeTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        try AppSettingsTestIsolationLock.acquire()
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
        AppSettingsTestIsolationLock.release()
    }

    func testVocabularyHelper_FollowsResolvedSelectionPerMode() {
        settings.updateTranscriptionDictationSelection(
            provider: .elevenLabs,
            model: "scribe_v2"
        )

        XCTAssertEqual(
            settings.resolvedTranscriptionSelection(for: .meeting).provider.vocabularyHelper,
            .none
        )
        XCTAssertFalse(settings.shouldUseRemoteTranscription(for: .meeting))
        XCTAssertEqual(
            settings.resolvedTranscriptionSelection(for: .dictation).provider.vocabularyHelper,
            .keyterms
        )
        XCTAssertEqual(
            settings.resolvedTranscriptionSelection(for: .assistant).provider.vocabularyHelper,
            .keyterms
        )

        settings.updateTranscriptionDictationSelection(
            provider: .groq,
            model: "whisper-large-v3"
        )

        XCTAssertEqual(
            settings.resolvedTranscriptionSelection(for: .dictation).provider.vocabularyHelper,
            .prompt
        )
        XCTAssertEqual(
            settings.resolvedTranscriptionSelection(for: .assistant).provider.vocabularyHelper,
            .prompt
        )
        XCTAssertEqual(
            settings.resolvedTranscriptionSelection(for: .meeting).provider.vocabularyHelper,
            .none
        )
    }
}
