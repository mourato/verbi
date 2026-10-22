@testable import VerbiCore
import XCTest

final class MockPasteboardService: PasteboardServiceProtocol {
    var storedString: String?

    func clearContents() {
        storedString = nil
    }

    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) {
        storedString = string
    }
}

struct MockDeliverySettings: DeliverySettingsConfig {
    var autoCopyTranscriptionToClipboard: Bool
    var autoPasteTranscriptionToActiveApp: Bool
    var smartSpacingAndCapitalizationEnabled: Bool
    var smartParagraphsEnabled: Bool
}

struct MockCursorTextContextProvider: CursorTextContextProvider {
    let context: CursorTextContext

    @MainActor
    func fetchCursorTextContext() -> CursorTextContext {
        context
    }
}

@MainActor
final class TranscriptionDeliveryServiceTests: XCTestCase {
    private let kMeetingText = "Detected meeting text"
    private let kDictationText = "Dictation text"
    private let kImportedText = "Imported text"

    private var mockPasteboard: MockPasteboardService!
    private var originalCursorProvider: (any CursorTextContextProvider)!

    override func setUp() async throws {
        mockPasteboard = MockPasteboardService()
        originalCursorProvider = TranscriptionDeliveryService.cursorTextContextProvider
        TranscriptionDeliveryService.cursorTextContextProvider = MockCursorTextContextProvider(
            context: CursorTextContext(
                previousCharacter: nil,
                nextCharacter: nil,
                isEmptyDocument: false,
                support: .unsupported,
            ),
        )
    }

    override func tearDown() async throws {
        TranscriptionDeliveryService.cursorTextContextProvider = originalCursorProvider
    }

    func testDeliver_WithMeetingApp_DoesNotCopyToClipboard() {
        let meeting = CaptureSession(app: .googleMeet)
        let transcription = CaptureArtifact(meeting: meeting, text: kMeetingText, rawText: kMeetingText)
        let settings = makeSettings(autoCopy: true, autoPaste: false)

        TranscriptionDeliveryService.deliver(
            transcription: transcription,
            settings: settings,
            pasteboard: mockPasteboard,
        )

        XCTAssertNil(mockPasteboard.storedString)
    }

    func testDeliver_IsDictation_CopiesToClipboard() {
        let meeting = CaptureSession(app: .unknown)
        let transcription = CaptureArtifact(meeting: meeting, text: kDictationText, rawText: kDictationText)
        let settings = makeSettings(autoCopy: true, autoPaste: false)

        TranscriptionDeliveryService.deliver(
            transcription: transcription,
            settings: settings,
            pasteboard: mockPasteboard,
        )

        XCTAssertEqual(mockPasteboard.storedString, kDictationText)
    }

    func testDeliver_UsesSnapshottedPolicyAfterGlobalSettingsChange() {
        let meeting = CaptureSession(app: .unknown)
        let transcription = CaptureArtifact(meeting: meeting, text: kDictationText, rawText: kDictationText)
        let settings = makeSettings(autoCopy: false, autoPaste: false)
        let policy = DictationTextHandlingPolicy(autoCopyToClipboard: true, autoPasteToActiveApp: false)

        TranscriptionDeliveryService.deliver(
            transcription: transcription,
            textPolicy: policy,
            settings: settings,
            pasteboard: mockPasteboard,
        )

        XCTAssertEqual(mockPasteboard.storedString, kDictationText)
    }

    func testDeliver_UsesDeliverySettingsSnapshotAfterSettingsMutation() {
        let meeting = CaptureSession(app: .unknown)
        let transcription = CaptureArtifact(meeting: meeting, text: kDictationText, rawText: kDictationText)
        var settings = makeSettings(autoCopy: true, autoPaste: false)
        let snapshot = DeliverySettingsSnapshot(settings: settings)
        settings.autoCopyTranscriptionToClipboard = false

        TranscriptionDeliveryService.deliver(
            transcription: transcription,
            settings: snapshot,
            pasteboard: mockPasteboard,
        )

        XCTAssertEqual(mockPasteboard.storedString, kDictationText)
    }

    func testDeliver_SnapshottedPolicyDisablesCopyDespiteGlobalEnabled() {
        let meeting = CaptureSession(app: .unknown)
        let transcription = CaptureArtifact(meeting: meeting, text: kDictationText, rawText: kDictationText)
        let settings = makeSettings(autoCopy: true, autoPaste: false)
        let policy = DictationTextHandlingPolicy(autoCopyToClipboard: false, autoPasteToActiveApp: false)

        TranscriptionDeliveryService.deliver(
            transcription: transcription,
            textPolicy: policy,
            settings: settings,
            pasteboard: mockPasteboard,
        )

        XCTAssertNil(mockPasteboard.storedString)
    }

    func testDeliver_UnknownAppWithMeetingSource_DoesNotCopyToClipboard() {
        let meeting = CaptureSession(app: .unknown)
        let transcription = CaptureArtifact(meeting: meeting, text: kMeetingText, rawText: kMeetingText)
        let settings = makeSettings(autoCopy: true, autoPaste: false)

        TranscriptionDeliveryService.deliver(
            transcription: transcription,
            recordingSource: .all,
            settings: settings,
            pasteboard: mockPasteboard,
        )

        XCTAssertNil(mockPasteboard.storedString)
    }

    func testDeliver_WithImportedFile_DoesNotCopyToClipboard() {
        let meeting = CaptureSession(app: .importedFile, capturePurpose: .meeting)
        let transcription = CaptureArtifact(meeting: meeting, text: kImportedText, rawText: kImportedText)
        let settings = makeSettings(autoCopy: true, autoPaste: false)

        TranscriptionDeliveryService.deliver(
            transcription: transcription,
            settings: settings,
            pasteboard: mockPasteboard,
        )

        XCTAssertNil(mockPasteboard.storedString)
    }

    func testDeliver_SettingsDisabled_DoesNotCopyToClipboard() {
        let meeting = CaptureSession(app: .unknown)
        let transcription = CaptureArtifact(meeting: meeting, text: kDictationText, rawText: kDictationText)
        let settings = makeSettings(autoCopy: false, autoPaste: false)

        TranscriptionDeliveryService.deliver(
            transcription: transcription,
            settings: settings,
            pasteboard: mockPasteboard,
        )

        XCTAssertNil(mockPasteboard.storedString)
    }

    func testDeliver_WithLeakedContextBlock_StripsMetadataAndCopiesCleanProcessedText() {
        let meeting = CaptureSession(app: .unknown)
        let transcription = CaptureArtifact(
            meeting: meeting,
            text: "Clean result",
            rawText: kDictationText,
            processedContent: "Clean result\n\n<CONTEXT_METADATA>\n- Active window OCR: leaked\n</CONTEXT_METADATA>",
        )
        let settings = makeSettings(autoCopy: true, autoPaste: false)

        TranscriptionDeliveryService.deliver(
            transcription: transcription,
            settings: settings,
            pasteboard: mockPasteboard,
        )

        XCTAssertEqual(mockPasteboard.storedString, "Clean result")
    }

    func testDeliver_WithOnlyLeakedContextBlock_FallsBackToRawText() {
        let meeting = CaptureSession(app: .unknown)
        let transcription = CaptureArtifact(
            meeting: meeting,
            text: kDictationText,
            rawText: kDictationText,
            processedContent: "<CONTEXT_METADATA>\n- Active window OCR: leaked\n</CONTEXT_METADATA>",
        )
        let settings = makeSettings(autoCopy: true, autoPaste: false)

        TranscriptionDeliveryService.deliver(
            transcription: transcription,
            settings: settings,
            pasteboard: mockPasteboard,
        )

        XCTAssertEqual(mockPasteboard.storedString, kDictationText)
    }

    func testDeliver_WithSmartSpacingEnabled_UsesTransformedDeliveredText() {
        let meeting = CaptureSession(app: .unknown)
        let transcription = CaptureArtifact(meeting: meeting, text: kDictationText, rawText: "Store today")
        let settings = makeSettings(autoCopy: true, autoPaste: false, smartSpacingEnabled: true)
        TranscriptionDeliveryService.cursorTextContextProvider = MockCursorTextContextProvider(
            context: CursorTextContext(
                previousCharacter: "e",
                nextCharacter: nil,
                isEmptyDocument: false,
                support: .supported,
            ),
        )

        TranscriptionDeliveryService.deliver(
            transcription: transcription,
            settings: settings,
            pasteboard: mockPasteboard,
        )

        XCTAssertEqual(mockPasteboard.storedString, " store today")
    }

    func testDeliver_WithSentenceTerminatorBeforeCursor_PrependsSpace() {
        let meeting = CaptureSession(app: .unknown)
        let transcription = CaptureArtifact(meeting: meeting, text: kDictationText, rawText: "Next step starts now")
        let settings = makeSettings(autoCopy: true, autoPaste: false, smartSpacingEnabled: true)
        TranscriptionDeliveryService.cursorTextContextProvider = MockCursorTextContextProvider(
            context: CursorTextContext(
                previousCharacter: ".",
                nextCharacter: nil,
                isEmptyDocument: false,
                support: .supported,
            ),
        )

        TranscriptionDeliveryService.deliver(
            transcription: transcription,
            settings: settings,
            pasteboard: mockPasteboard,
        )

        XCTAssertEqual(mockPasteboard.storedString, " Next step starts now")
    }

    func testDeliver_WithSmartParagraphsEnabled_ParagraphizesBeforeSpacing() {
        let meeting = CaptureSession(app: .unknown)
        let text = [
            "We reviewed the roadmap and captured all launch blockers.",
            "The design team confirmed the new sidebar and toolbar direction.",
            "Engineering agreed to finish the migration before the beta cutoff.",
            "Support prepared the updated macros for customer rollout questions.",
            "Marketing will publish the announcement once the release build is ready.",
        ].joined(separator: " ")
        let transcription = CaptureArtifact(meeting: meeting, text: text, rawText: text)
        let settings = makeSettings(autoCopy: true, autoPaste: false, smartSpacingEnabled: true, smartParagraphsEnabled: true)
        TranscriptionDeliveryService.cursorTextContextProvider = MockCursorTextContextProvider(
            context: CursorTextContext(
                previousCharacter: nil,
                nextCharacter: nil,
                isEmptyDocument: false,
                support: .supported,
            ),
        )

        TranscriptionDeliveryService.deliver(
            transcription: transcription,
            settings: settings,
            pasteboard: mockPasteboard,
        )

        XCTAssertEqual(
            mockPasteboard.storedString,
            [
                "We reviewed the roadmap and captured all launch blockers. The design team confirmed the new sidebar and toolbar direction. Engineering agreed to finish the migration before the beta cutoff. Support prepared the updated macros for customer rollout questions.",
                "Marketing will publish the announcement once the release build is ready.",
            ].joined(separator: "\n\n"),
        )
    }

    func testDeliver_WithSmartParagraphsDisabled_KeepsSingleBlockText() {
        let meeting = CaptureSession(app: .unknown)
        let text = [
            "We reviewed the roadmap and captured all launch blockers.",
            "The design team confirmed the new sidebar and toolbar direction.",
            "Engineering agreed to finish the migration before the beta cutoff.",
            "Support prepared the updated macros for customer rollout questions.",
            "Marketing will publish the announcement once the release build is ready.",
        ].joined(separator: " ")
        let transcription = CaptureArtifact(meeting: meeting, text: text, rawText: text)
        let settings = makeSettings(autoCopy: true, autoPaste: false, smartSpacingEnabled: false, smartParagraphsEnabled: false)

        TranscriptionDeliveryService.deliver(
            transcription: transcription,
            settings: settings,
            pasteboard: mockPasteboard,
        )

        XCTAssertEqual(mockPasteboard.storedString, text)
    }

    func testDeliver_WithPermissionDeniedFallback_AppendsTrailingSpace() {
        let meeting = CaptureSession(app: .unknown)
        let transcription = CaptureArtifact(meeting: meeting, text: kDictationText, rawText: "Hello")
        let settings = makeSettings(autoCopy: true, autoPaste: false, smartSpacingEnabled: true)
        TranscriptionDeliveryService.cursorTextContextProvider = MockCursorTextContextProvider(
            context: CursorTextContext(
                previousCharacter: nil,
                nextCharacter: nil,
                isEmptyDocument: false,
                support: .permissionDenied,
            ),
        )

        TranscriptionDeliveryService.deliver(
            transcription: transcription,
            settings: settings,
            pasteboard: mockPasteboard,
        )

        XCTAssertEqual(mockPasteboard.storedString, "Hello ")
    }

    func testDeliver_WithSmartSpacingDisabled_KeepsOriginalText() {
        let meeting = CaptureSession(app: .unknown)
        let transcription = CaptureArtifact(meeting: meeting, text: kDictationText, rawText: "Store today")
        let settings = makeSettings(autoCopy: true, autoPaste: false, smartSpacingEnabled: false)
        TranscriptionDeliveryService.cursorTextContextProvider = MockCursorTextContextProvider(
            context: CursorTextContext(
                previousCharacter: "e",
                nextCharacter: nil,
                isEmptyDocument: false,
                support: .supported,
            ),
        )

        TranscriptionDeliveryService.deliver(
            transcription: transcription,
            settings: settings,
            pasteboard: mockPasteboard,
        )

        XCTAssertEqual(mockPasteboard.storedString, "Store today")
    }

    private func makeSettings(
        autoCopy: Bool,
        autoPaste: Bool,
        smartSpacingEnabled: Bool = true,
        smartParagraphsEnabled: Bool = true,
    ) -> MockDeliverySettings {
        MockDeliverySettings(
            autoCopyTranscriptionToClipboard: autoCopy,
            autoPasteTranscriptionToActiveApp: autoPaste,
            smartSpacingAndCapitalizationEnabled: smartSpacingEnabled,
            smartParagraphsEnabled: smartParagraphsEnabled,
        )
    }
}
