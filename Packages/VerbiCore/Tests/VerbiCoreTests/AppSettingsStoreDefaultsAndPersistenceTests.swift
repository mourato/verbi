@testable import VerbiCore
import XCTest

@MainActor
final class AppSettingsStoreDefaultsAndPersistenceTests: AppSettingsStoreTestCase {
    func testResetDefaultsEnablesMeetingQnA() {
        settings.meetingQnAEnabled = false
        settings.resetToDefaults()

        XCTAssertTrue(settings.meetingQnAEnabled)
    }

    func testResetDefaultsDisablesDictationStructuredPostProcessing() {
        settings.dictationStructuredPostProcessingEnabled = true

        settings.resetToDefaults()

        XCTAssertFalse(settings.dictationStructuredPostProcessingEnabled)
    }

    func testResetDefaultsEnablesSmartSpacingAndCapitalization() {
        settings.smartSpacingAndCapitalizationEnabled = false

        settings.resetToDefaults()

        XCTAssertTrue(settings.smartSpacingAndCapitalizationEnabled)
    }

    func testResetDefaultsEnablesSmartParagraphs() {
        settings.smartParagraphsEnabled = false

        settings.resetToDefaults()

        XCTAssertTrue(settings.smartParagraphsEnabled)
    }

    func testAppearanceModeSettingIsPersistedAndReset() {
        settings.appearanceMode = .dark
        XCTAssertEqual(UserDefaults.standard.string(forKey: "appearanceMode"), "dark")

        settings.resetToDefaults()

        XCTAssertEqual(settings.appearanceMode, .system)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "appearanceMode"), "system")
    }

    func testDictationStructuredPostProcessingSettingIsPersisted() {
        settings.dictationStructuredPostProcessingEnabled = true
        XCTAssertEqual(
            UserDefaults.standard.object(forKey: "dictationStructuredPostProcessingEnabled") as? Bool,
            true,
        )

        settings.dictationStructuredPostProcessingEnabled = false
        XCTAssertEqual(
            UserDefaults.standard.object(forKey: "dictationStructuredPostProcessingEnabled") as? Bool,
            false,
        )
    }

    func testSmartParagraphsSettingIsPersisted() {
        settings.smartParagraphsEnabled = true
        XCTAssertEqual(
            UserDefaults.standard.object(forKey: "smartParagraphsEnabled") as? Bool,
            true,
        )

        settings.smartParagraphsEnabled = false
        XCTAssertEqual(
            UserDefaults.standard.object(forKey: "smartParagraphsEnabled") as? Bool,
            false,
        )
    }

    func testModelResidencyTimeoutDefaultsToThirtyMinutes() {
        XCTAssertEqual(settings.modelResidencyTimeout, .minutes30)
    }

    func testModelResidencyTimeoutResetReturnsToThirtyMinutes() {
        settings.modelResidencyTimeout = .minutes5

        settings.resetToDefaults()

        XCTAssertEqual(settings.modelResidencyTimeout, .minutes30)
    }

    func testModelResidencyTimeoutSettingIsPersisted() {
        settings.modelResidencyTimeout = .minutes60
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "modelResidencyTimeout"),
            AppSettingsStore.ModelResidencyTimeoutOption.minutes60.rawValue,
        )

        settings.modelResidencyTimeout = .never
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "modelResidencyTimeout"),
            AppSettingsStore.ModelResidencyTimeoutOption.never.rawValue,
        )
    }

    func testTranscriptionInputLanguageHintDefaultsToAutomatic() {
        XCTAssertEqual(settings.transcriptionInputLanguageHint, .automatic)
    }

    func testTranscriptionInputLanguageHintSettingIsPersisted() {
        settings.transcriptionInputLanguageHint = .portuguese

        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "transcriptionInputLanguageHint"),
            TranscriptionInputLanguageHint.portuguese.rawValue,
        )
    }

    func testResolvedTranscriptionInputLanguageCode_ResolvesAcrossExecutionModes() {
        settings.transcriptionInputLanguageHint = .portuguese
        settings.updateTranscriptionDictationSelection(
            provider: .groq,
            model: "whisper-large-v3",
        )

        XCTAssertEqual(settings.resolvedTranscriptionInputLanguageCode(for: .meeting), "pt")
        XCTAssertEqual(settings.resolvedTranscriptionInputLanguageCode(for: .dictation), "pt")
        XCTAssertEqual(settings.resolvedTranscriptionInputLanguageCode(for: .assistant), "pt")
    }

    func testResolvedTranscriptionInputLanguageCode_AutomaticReturnsNil() {
        settings.transcriptionInputLanguageHint = .automatic

        XCTAssertNil(settings.resolvedTranscriptionInputLanguageCode(for: .meeting))
        XCTAssertNil(settings.resolvedTranscriptionInputLanguageCode(for: .dictation))
    }

    func testTranscriptionInputLanguageHint_AllCasesMatchSharedProviderSupport() {
        let allCases = TranscriptionInputLanguageHint.allCases
        let expected: [TranscriptionInputLanguageHint] = [
            .automatic,
            .german,
            .english,
            .spanish,
            .french,
            .italian,
            .portuguese,
            .greek,
            .dutch,
            .polish,
        ]

        XCTAssertEqual(allCases, expected)
    }
}
