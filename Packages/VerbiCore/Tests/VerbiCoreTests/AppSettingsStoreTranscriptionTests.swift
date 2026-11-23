@testable import VerbiCore
import XCTest

@MainActor
final class AppSettingsStoreTranscriptionTests: AppSettingsStoreTestCase {
    func testResolvedTranscriptionSelection_MeetingAlwaysUsesLocalProvider() {
        settings.updateTranscriptionDictationSelection(
            provider: .groq,
            model: "whisper-large-v3"
        )

        let resolved = settings.resolvedTranscriptionSelection(for: .meeting)

        XCTAssertEqual(resolved.provider, .local)
        XCTAssertEqual(resolved.selectedModel, VerbiCoreInfrastructure.TranscriptionProvider.localModelID)
    }

    func testResolvedTranscriptionSelection_MeetingUsesDedicatedMeetingLocalModel() {
        settings.updateMeetingTranscriptionLocalModel(.parakeetTdt06BV3)
        settings.updateTranscriptionDictationSelection(
            provider: .groq,
            model: "whisper-large-v3"
        )

        let resolved = settings.resolvedTranscriptionSelection(for: .meeting)

        XCTAssertEqual(resolved.provider, .local)
        XCTAssertEqual(
            resolved.selectedModel,
            VerbiCoreInfrastructure.TranscriptionProvider.localModelID
        )
    }

    func testMeetingTranscriptionLocalModel_IsPersistedIndependently() {
        settings.updateMeetingTranscriptionLocalModel(.parakeetTdt06BV3)
        settings.updateTranscriptionDictationSelection(
            provider: .groq,
            model: "whisper-large-v3"
        )

        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "meetingTranscriptionLocalModel"),
            VerbiCoreInfrastructure.TranscriptionProvider.localModelID
        )
        XCTAssertEqual(
            settings.transcriptionDictationSelection.provider,
            .groq
        )
    }

    func testResolvedTranscriptionSelection_MeetingModelDoesNotChangeWhenDictationProviderChanges() {
        settings.updateMeetingTranscriptionLocalModel(.parakeetTdt06BV3)
        settings.updateTranscriptionDictationSelection(
            provider: .local,
            model: VerbiCoreInfrastructure.TranscriptionProvider.localModelID
        )
        settings.updateTranscriptionDictationSelection(
            provider: .groq,
            model: "whisper-large-v3"
        )

        let resolved = settings.resolvedTranscriptionSelection(for: .meeting)

        XCTAssertEqual(resolved.provider, .local)
        XCTAssertEqual(resolved.selectedModel, VerbiCoreInfrastructure.TranscriptionProvider.localModelID)
    }

    func testNormalizedLocalModelID_FallsBackFromRemovedCohereSelection() {
        let normalized = VerbiCoreInfrastructure.TranscriptionProvider.local
            .normalizedModelID("cohere-transcribe-03-2026-coreml-6bit")

        XCTAssertEqual(normalized, VerbiCoreInfrastructure.TranscriptionProvider.localModelID)
    }

    func testResolvedTranscriptionSelection_DictationFollowsConfiguredProvider() {
        settings.updateTranscriptionDictationSelection(
            provider: .groq,
            model: "whisper-large-v3"
        )

        let resolved = settings.resolvedTranscriptionSelection(for: .dictation)

        XCTAssertEqual(resolved.provider, .groq)
        XCTAssertEqual(resolved.selectedModel, "whisper-large-v3")
    }

    func testResolvedTranscriptionSelection_AssistantFollowsConfiguredProvider() {
        settings.updateTranscriptionDictationSelection(
            provider: .groq,
            model: "whisper-large-v3"
        )

        let resolved = settings.resolvedTranscriptionSelection(for: .assistant)

        XCTAssertEqual(resolved.provider, .groq)
        XCTAssertEqual(resolved.selectedModel, "whisper-large-v3")
    }

    func testSupportsIncrementalTranscription_EnabledForGroqDictationEnabledForMeeting() {
        settings.updateTranscriptionDictationSelection(
            provider: .groq,
            model: "whisper-large-v3-turbo"
        )

        XCTAssertTrue(settings.supportsIncrementalTranscription(for: .dictation))
        XCTAssertTrue(settings.supportsIncrementalTranscription(for: .meeting))
    }

    func testSupportsIncrementalTranscription_DisabledForGroqAssistantEnabledForMeeting() {
        settings.updateTranscriptionDictationSelection(
            provider: .groq,
            model: "whisper-large-v3-turbo"
        )

        XCTAssertFalse(settings.supportsIncrementalTranscription(for: .assistant))
        XCTAssertTrue(settings.supportsIncrementalTranscription(for: .meeting))
    }

    func testResolvedTranscriptionSelection_DictationSupportsElevenLabsProvider() {
        settings.updateTranscriptionDictationSelection(
            provider: .elevenLabs,
            model: "scribe_v2"
        )

        let resolved = settings.resolvedTranscriptionSelection(for: .dictation)

        XCTAssertEqual(resolved.provider, .elevenLabs)
        XCTAssertEqual(resolved.selectedModel, "scribe_v2")
    }

    func testSupportsIncrementalTranscription_EnabledForElevenLabsDictationEnabledForMeeting() {
        settings.updateTranscriptionDictationSelection(
            provider: .elevenLabs,
            model: "scribe_v1"
        )

        XCTAssertTrue(settings.supportsIncrementalTranscription(for: .dictation))
        XCTAssertTrue(settings.supportsIncrementalTranscription(for: .meeting))
    }
}
