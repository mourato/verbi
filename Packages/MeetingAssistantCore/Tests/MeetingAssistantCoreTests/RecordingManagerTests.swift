import AppKit
import AVFoundation
import Combine
import CryptoKit
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreUI
import XCTest

@MainActor
final class RecordingManagerTests: XCTestCase {
    var manager: RecordingManager?
    var mockMic: MockAudioRecorder?
    var mockSystem: MockAudioRecorder?
    var mockTranscription: MockTranscriptionClient?
    var mockPostProcessing: MockPostProcessingService?
    var mockAudioSilenceCompactor: MockAudioSilenceCompactor?
    var mockStorage: MockStorageService?
    var mockActiveAppContextProvider: MockActiveAppContextProvider?
    var mockCaptureContextResolver: MockCaptureContextResolver?
    var meetingNotesRichTextStore: MeetingNotesRichTextStore?
    var meetingNotesMarkdownStore: MeetingNotesMarkdownDocumentStore?
    var userDefaults: UserDefaults?
    var suiteName: String?
    var markdownRootDirectoryURL: URL?
    var readyRetryProviders: Set<TranscriptionProvider> = []

    override func setUp() async throws {
        try await super.setUp()
        try AppSettingsTestIsolationLock.acquire()
        AppSettingsStore.shared.resetToDefaults()
        // Initialize mocks locally first to ensure they are available for manager init
        let mic = MockAudioRecorder()
        let system = MockAudioRecorder()
        let transcription = MockTranscriptionClient()
        let postProcessing = MockPostProcessingService()
        let audioSilenceCompactor = MockAudioSilenceCompactor()
        let storage = MockStorageService()
        let activeAppContextProvider = MockActiveAppContextProvider()
        let captureContextResolver = MockCaptureContextResolver()
        let suiteName = "RecordingManagerTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create test UserDefaults suite")
            return
        }
        let richTextStore = MeetingNotesRichTextStore(userDefaults: userDefaults)
        let markdownRootDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-manager-markdown-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: markdownRootDirectoryURL, withIntermediateDirectories: true)
        let markdownStore = MeetingNotesMarkdownDocumentStore(
            userDefaults: userDefaults,
            rootDirectoryURL: markdownRootDirectoryURL,
            writesAsynchronously: false,
        )

        mockMic = mic
        mockSystem = system
        mockTranscription = transcription
        mockPostProcessing = postProcessing
        mockAudioSilenceCompactor = audioSilenceCompactor
        mockStorage = storage
        mockActiveAppContextProvider = activeAppContextProvider
        mockCaptureContextResolver = captureContextResolver
        meetingNotesRichTextStore = richTextStore
        meetingNotesMarkdownStore = markdownStore
        self.userDefaults = userDefaults
        self.suiteName = suiteName
        self.markdownRootDirectoryURL = markdownRootDirectoryURL

        manager = RecordingManager(
            micRecorder: mic,
            systemRecorder: system,
            transcriptionClient: transcription,
            postProcessingService: postProcessing,
            audioSilenceCompactor: audioSilenceCompactor,
            storage: storage,
            activeAppContextProvider: activeAppContextProvider,
            captureContextResolver: captureContextResolver,
            meetingNotesRichTextStore: richTextStore,
            meetingNotesMarkdownStore: markdownStore,
            apiKeyExists: { _ in true },
            transcriptionAPIKeyExists: { [weak self] provider in
                self?.readyRetryProviders.contains(provider) == true
            },
            isLocalRetryModelReady: { _ in true },
        )
    }

    override func tearDown() async throws {
        if let manager {
            await manager.reset()
        }

        await RecordingExclusivityCoordinator.shared.endRecording()
        await RecordingExclusivityCoordinator.shared.endAssistant()

        manager = nil
        mockMic = nil
        mockSystem = nil
        mockTranscription = nil
        mockPostProcessing = nil
        mockAudioSilenceCompactor = nil
        mockStorage = nil
        mockActiveAppContextProvider = nil
        mockCaptureContextResolver = nil
        meetingNotesRichTextStore = nil
        meetingNotesMarkdownStore = nil
        if let suiteName {
            userDefaults?.removePersistentDomain(forName: suiteName)
        }
        if let markdownRootDirectoryURL {
            try? FileManager.default.removeItem(at: markdownRootDirectoryURL)
        }
        userDefaults = nil
        suiteName = nil
        markdownRootDirectoryURL = nil
        readyRetryProviders = []
        AppSettingsStore.shared.resetToDefaults()
        AppSettingsTestIsolationLock.release()
        try await super.tearDown()
    }

}

extension RecordingManagerTests {

    // MARK: - Basic Tests

    func testInitialization() throws {
        let manager = try XCTUnwrap(manager)
        XCTAssertNotNil(manager)
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isTranscribing)
    }

    func testStorageServiceUsage() async throws {
        let manager = try XCTUnwrap(manager)
        let mockStorage = try XCTUnwrap(mockStorage)

        await manager.startRecording()
        XCTAssertTrue(mockStorage.createRecordingURLCalled)
    }

    func testCheckPermissions_WhenBothGranted() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockSystem = try XCTUnwrap(mockSystem)

        mockMic.permissionGranted = true
        mockSystem.permissionGranted = true

        await manager.checkPermission()

        XCTAssertTrue(manager.hasRequiredPermissions)
    }

    func testCheckPermissions_WhenOneDenied() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockSystem = try XCTUnwrap(mockSystem)

        mockMic.permissionGranted = true
        mockSystem.permissionGranted = false

        await manager.checkPermission(for: .all)

        XCTAssertFalse(manager.hasRequiredPermissions)
    }

    func testStartRecording_Success() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockSystem = try XCTUnwrap(mockSystem)

        mockMic.permissionGranted = true
        mockSystem.permissionGranted = true

        await manager.startRecording()

        XCTAssertTrue(manager.isRecording)
        XCTAssertTrue(mockMic.startRecordingCalled)
    }

    func testStartRecording_FailsIfAlreadyRecording() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)

        await manager.startRecording()

        mockMic.startRecordingCalled = false

        await manager.startRecording()

        XCTAssertFalse(mockMic.startRecordingCalled)
    }

    func testSharedRecorderState_DoesNotMarkRecordingWhenManagerHasNoOwnedCapture() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)

        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isStartingRecording)
        XCTAssertNil(manager.currentCapturePurpose)

        mockMic.isRecording = true
        await Task.yield()
        await waitUntil(message: "Shared recorder state should not mark the manager as recording.") {
            !manager.isRecording
        }

        XCTAssertFalse(manager.isRecording)
    }

    func testShouldApplyEnhancementsPostProcessing_ReturnsFalseWhenModelIsMissing() {
        let settings = AppSettingsStore.shared
        let originalPostProcessing = settings.postProcessingEnabled
        let originalSelection = settings.enhancementsAISelection

        defer {
            settings.postProcessingEnabled = originalPostProcessing
            settings.enhancementsAISelection = originalSelection
        }

        settings.postProcessingEnabled = true
        settings.enhancementsAISelection = EnhancementsAISelection(provider: .openai, selectedModel: " ")

        let shouldApply = RecordingManager.shouldApplyEnhancementsPostProcessing(
            settings: settings,
            kernelMode: .meeting,
            apiKeyExists: { _ in true },
        )

        XCTAssertFalse(shouldApply)
    }

    func testShouldApplyEnhancementsPostProcessing_ReturnsTrueWhenConfigurationIsReady() {
        let settings = AppSettingsStore.shared
        let originalPostProcessing = settings.postProcessingEnabled
        let originalSelection = settings.enhancementsAISelection

        defer {
            settings.postProcessingEnabled = originalPostProcessing
            settings.enhancementsAISelection = originalSelection
        }

        settings.postProcessingEnabled = true
        settings.enhancementsAISelection = EnhancementsAISelection(provider: .openai, selectedModel: "gpt-4o-mini")

        let shouldApply = RecordingManager.shouldApplyEnhancementsPostProcessing(
            settings: settings,
            kernelMode: .meeting,
            apiKeyExists: { _ in true },
        )

        XCTAssertTrue(shouldApply)
    }

    func testShouldApplyEnhancementsPostProcessing_AllowsDictationWhenConfigurationIsReady() {
        let settings = AppSettingsStore.shared
        let originalPostProcessing = settings.postProcessingEnabled
        let originalMeetingSelection = settings.enhancementsAISelection
        let originalDictationSelection = settings.enhancementsDictationAISelection

        defer {
            settings.postProcessingEnabled = originalPostProcessing
            settings.enhancementsAISelection = originalMeetingSelection
            settings.enhancementsDictationAISelection = originalDictationSelection
        }

        settings.postProcessingEnabled = true
        settings.enhancementsDictationAISelection = EnhancementsAISelection(
            provider: .openai,
            selectedModel: "gpt-4o-mini",
        )

        let shouldApply = RecordingManager.shouldApplyEnhancementsPostProcessing(
            settings: settings,
            kernelMode: .dictation,
            apiKeyExists: { _ in true },
        )

        XCTAssertTrue(shouldApply)
    }

    func testShouldApplyEnhancementsPostProcessing_DictationIgnoresMeetingGlobalToggle() {
        let settings = AppSettingsStore.shared
        let originalPostProcessing = settings.postProcessingEnabled
        let originalDictationSelection = settings.enhancementsDictationAISelection

        defer {
            settings.postProcessingEnabled = originalPostProcessing
            settings.enhancementsDictationAISelection = originalDictationSelection
        }

        settings.postProcessingEnabled = false
        settings.enhancementsDictationAISelection = EnhancementsAISelection(
            provider: .openai,
            selectedModel: "gpt-4o-mini",
        )

        let shouldApply = RecordingManager.shouldApplyEnhancementsPostProcessing(
            settings: settings,
            kernelMode: .dictation,
            apiKeyExists: { _ in true },
        )

        XCTAssertTrue(shouldApply)
    }

    func testPromptWithDictationRuleOverrides_EmbedsLanguageAndCustomInstructionsAsPriorityBlock() throws {
        let manager = try XCTUnwrap(manager)
        let settings = AppSettingsStore.shared
        let originalStyles = settings.dictationStyles

        defer {
            settings.dictationStyles = originalStyles
            manager.dictationStartBundleIdentifier = nil
        }

        settings.dictationStyles = [
            DictationStyle(
                name: "Engineering notes",
                iconSymbol: "chevron.left.forwardslash.chevron.right",
                promptInstructions: "Keep terminology concise and developer-focused.",
                forceMarkdownOutput: false,
                replaceBasePrompt: false,
                outputLanguage: .english,
                targets: [
                    .app(bundleIdentifier: "com.microsoft.VSCode"),
                ],
            ),
        ]
        manager.dictationStartBundleIdentifier = "com.microsoft.VSCode"

        let basePrompt = PostProcessingPrompt(
            title: "Dictation",
            promptText: "Base dictation prompt",
        )
        let resolvedPrompt = manager.promptWithDictationRuleOverrides(prompt: basePrompt, settings: settings)

        XCTAssertTrue(
            resolvedPrompt.promptText.contains("<\(AIPromptTemplates.siteOrAppPriorityTag)>"),
            "Expected site/app priority wrapper in prompt",
        )
        XCTAssertTrue(
            resolvedPrompt.promptText.contains("<OUTPUT_LANGUAGE>"),
            "Expected output language instruction to be included",
        )
        XCTAssertTrue(
            resolvedPrompt.promptText.contains("Translate the final output to English."),
            "Expected explicit translation requirement",
        )
        XCTAssertTrue(
            resolvedPrompt.promptText.contains("Keep terminology concise and developer-focused."),
            "Expected custom app instructions to be included",
        )
    }

    func testPromptWithDictationRuleOverrides_ReplacesBasePromptWhenStyleRequiresReplacement() throws {
        let manager = try XCTUnwrap(manager)
        let settings = AppSettingsStore.shared
        let originalStyles = settings.dictationStyles

        defer {
            settings.dictationStyles = originalStyles
            manager.dictationStartBundleIdentifier = nil
        }

        settings.dictationStyles = [
            DictationStyle(
                name: "Direct output",
                iconSymbol: "text.quote",
                promptInstructions: "Use a direct style prompt as the full instruction set.",
                forceMarkdownOutput: false,
                replaceBasePrompt: true,
                outputLanguage: .original,
                targets: [
                    .app(bundleIdentifier: "com.microsoft.VSCode"),
                ],
            ),
        ]
        manager.dictationStartBundleIdentifier = "com.microsoft.VSCode"

        let basePrompt = PostProcessingPrompt(
            title: "Dictation",
            promptText: "Base dictation prompt",
        )
        let resolvedPrompt = manager.promptWithDictationRuleOverrides(prompt: basePrompt, settings: settings)

        XCTAssertEqual(
            resolvedPrompt.promptText,
            "Use a direct style prompt as the full instruction set.",
            "Expected style prompt to replace the original base prompt",
        )
        XCTAssertFalse(
            resolvedPrompt.promptText.contains("Base dictation prompt"),
            "Expected original prompt content to be replaced",
        )
    }

    func testRefreshPostProcessingReadinessWarning_SetsIssueForMeetingMode() throws {
        let manager = try XCTUnwrap(manager)
        let settings = AppSettingsStore.shared
        let originalPostProcessing = settings.postProcessingEnabled
        let originalMeetingSelection = settings.enhancementsAISelection

        defer {
            settings.postProcessingEnabled = originalPostProcessing
            settings.enhancementsAISelection = originalMeetingSelection
            manager.clearPostProcessingReadinessWarning()
        }

        settings.postProcessingEnabled = true
        settings.enhancementsAISelection = EnhancementsAISelection(provider: .openai, selectedModel: " ")

        manager.refreshPostProcessingReadinessWarning(for: .meeting, settings: settings, apiKeyExists: { _ in true })

        XCTAssertEqual(manager.postProcessingReadinessWarningIssue, .missingModel)
        XCTAssertEqual(manager.postProcessingReadinessWarningMode, .meeting)
    }

    func testRefreshPostProcessingReadinessWarning_SetsIssueForAssistantMode() throws {
        let manager = try XCTUnwrap(manager)
        let settings = AppSettingsStore.shared
        let originalPostProcessing = settings.postProcessingEnabled
        let originalDictationSelection = settings.enhancementsDictationAISelection

        defer {
            settings.postProcessingEnabled = originalPostProcessing
            settings.enhancementsDictationAISelection = originalDictationSelection
            manager.clearPostProcessingReadinessWarning()
        }

        settings.postProcessingEnabled = true
        settings.enhancementsDictationAISelection = EnhancementsAISelection(provider: .openai, selectedModel: "")

        manager.refreshPostProcessingReadinessWarning(for: .assistant, settings: settings, apiKeyExists: { _ in true })

        XCTAssertEqual(manager.postProcessingReadinessWarningIssue, .missingModel)
        XCTAssertEqual(manager.postProcessingReadinessWarningMode, .assistant)
    }

    func testMeetingNotes_AutosaveAndRestore_ByMeetingID() throws {
        let manager = try XCTUnwrap(manager)
        let meetingID = UUID()
        manager.currentCapturePurpose = .meeting
        manager.currentMeeting = Meeting(id: meetingID, app: .zoom, capturePurpose: .meeting)
        let richData = Data([0x7b, 0x5c, 0x72, 0x74, 0x66])

        manager.updateMeetingNotes(MeetingNotesContent(plainText: "Important note", richTextRTFData: richData))
        XCTAssertTrue(markdownMeetingFileExists(for: meetingID))
        manager.currentMeetingNotesText = ""
        manager.currentMeetingNotesRichTextData = nil
        manager.restoreMeetingNotesIfNeeded(for: meetingID)

        XCTAssertEqual(manager.currentMeetingNotesText, "Important note")
        XCTAssertEqual(manager.currentMeetingNotesRichTextData, richData)

        manager.clearMeetingNotesState(removePersistedValue: true)
        manager.currentMeeting = Meeting(id: meetingID, app: .zoom, capturePurpose: .meeting)
        manager.restoreMeetingNotesIfNeeded(for: meetingID)
        XCTAssertEqual(manager.currentMeetingNotesText, "")
        XCTAssertNil(manager.currentMeetingNotesRichTextData)
    }

    func testCalendarEventNotes_SaveAndRestore_ByEventIdentifier() throws {
        let manager = try XCTUnwrap(manager)
        let eventIdentifier = "event-\(UUID().uuidString)"
        let richData = Data([0x7b, 0x5c, 0x72, 0x74, 0x66])

        manager.updateCalendarEventNotes(
            MeetingNotesContent(plainText: "Event note", richTextRTFData: richData),
            for: eventIdentifier,
        )
        XCTAssertTrue(markdownEventFileExists(for: eventIdentifier))
        XCTAssertEqual(manager.loadCalendarEventNotesText(for: eventIdentifier), "Event note")
        XCTAssertEqual(manager.loadCalendarEventNotesContent(for: eventIdentifier).richTextRTFData, richData)

        manager.updateCalendarEventNotesText("   ", for: eventIdentifier)
        XCTAssertEqual(manager.loadCalendarEventNotesText(for: eventIdentifier), "")
        XCTAssertNil(manager.loadCalendarEventNotesContent(for: eventIdentifier).richTextRTFData)
    }

    func testUpdateCalendarEventNotes_SyncsToLinkedActiveMeeting() throws {
        let manager = try XCTUnwrap(manager)
        let meetingID = UUID()
        let eventIdentifier = "event-\(UUID().uuidString)"
        let linkedEvent = MeetingCalendarEventSnapshot(
            eventIdentifier: eventIdentifier,
            title: "Design review",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3_600),
        )
        manager.currentCapturePurpose = .meeting
        manager.currentMeeting = Meeting(
            id: meetingID,
            app: .zoom,
            capturePurpose: .meeting,
            linkedCalendarEvent: linkedEvent,
        )

        manager.updateCalendarEventNotesText("Synced from event", for: eventIdentifier)

        XCTAssertEqual(manager.currentMeetingNotesText, "Synced from event")
        manager.currentMeetingNotesText = ""
        manager.restoreMeetingNotesIfNeeded(for: meetingID)
        XCTAssertEqual(manager.currentMeetingNotesText, "Synced from event")

        manager.updateCalendarEventNotesText("   ", for: eventIdentifier)
        manager.clearMeetingNotesState(removePersistedValue: true)
    }

    func testUpdateMeetingNotes_SyncsToLinkedCalendarEvent() throws {
        let manager = try XCTUnwrap(manager)
        let meetingID = UUID()
        let eventIdentifier = "event-\(UUID().uuidString)"
        let linkedEvent = MeetingCalendarEventSnapshot(
            eventIdentifier: eventIdentifier,
            title: "Team sync",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3_600),
        )
        manager.currentCapturePurpose = .meeting
        manager.currentMeeting = Meeting(
            id: meetingID,
            app: .zoom,
            capturePurpose: .meeting,
            linkedCalendarEvent: linkedEvent,
        )

        manager.updateMeetingNotesText("Synced from meeting")

        XCTAssertEqual(manager.loadCalendarEventNotesText(for: eventIdentifier), "Synced from meeting")

        manager.updateMeetingNotesText("   ")
        manager.updateCalendarEventNotesText("   ", for: eventIdentifier)
    }

    func testLinkCurrentMeeting_MergesEventAndMeetingNotes_EventFirst() async throws {
        let manager = try XCTUnwrap(manager)
        let meetingID = UUID()
        let eventIdentifier = "event-\(UUID().uuidString)"
        manager.currentCapturePurpose = .meeting
        manager.currentMeeting = Meeting(id: meetingID, app: .zoom, capturePurpose: .meeting)

        manager.updateMeetingNotes(
            MeetingNotesContent(plainText: "Meeting note", richTextRTFData: Data([0x01, 0x02])),
        )
        manager.updateCalendarEventNotes(
            MeetingNotesContent(plainText: "Event note", richTextRTFData: Data([0x03, 0x04])),
            for: eventIdentifier,
        )
        XCTAssertEqual(manager.loadCalendarEventNotesText(for: eventIdentifier), "Event note")

        let linkedEvent = MeetingCalendarEventSnapshot(
            eventIdentifier: eventIdentifier,
            title: "Merged notes check",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3_600),
        )
        manager.linkCurrentMeeting(to: linkedEvent)

        let expected = "Event note\n\n---\n\nMeeting note"
        XCTAssertEqual(manager.currentMeetingNotesText, expected)
        XCTAssertEqual(manager.loadCalendarEventNotesText(for: eventIdentifier), expected)
        XCTAssertNotNil(manager.currentMeetingNotesRichTextData)
        let mergedEventContent = manager.loadCalendarEventNotesContent(for: eventIdentifier)
        XCTAssertNotNil(mergedEventContent.richTextRTFData)
        if let mergedRTF = mergedEventContent.richTextRTFData,
           let mergedAttributedText = try? NSAttributedString(
               data: mergedRTF,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil,
           )
        {
            XCTAssertTrue(mergedAttributedText.string.contains("Event note"))
            XCTAssertTrue(mergedAttributedText.string.contains("Meeting note"))
        } else {
            XCTFail("Expected merged rich-text notes to be decodable from RTF data")
        }

        manager.currentMeetingNotesText = ""
        manager.restoreMeetingNotesIfNeeded(for: meetingID)
        XCTAssertEqual(manager.currentMeetingNotesText, expected)

        manager.updateMeetingNotesText("   ")
        manager.updateCalendarEventNotesText("   ", for: eventIdentifier)
    }

    func testMergedPostProcessingInput_IncludesMeetingNotesBlock() {
        let qualityProfile = TranscriptionQualityProfile(
            normalizedTextForIntelligence: "Normalized text",
            overallConfidence: 0.9,
            containsUncertainty: false,
            markers: [],
        )

        let input = PostProcessingInputComposer.compose(
            transcriptionText: qualityProfile.normalizedTextForIntelligence,
            qualityProfile: qualityProfile,
            context: nil,
            meetingNotes: "User highlight",
            includeQualityMetadata: true,
        )

        XCTAssertTrue(input.contains("<MEETING_NOTES>"))
        XCTAssertTrue(input.contains("User highlight"))
        XCTAssertTrue(input.contains("</MEETING_NOTES>"))
    }

    func testPersistCurrentMeetingNotesForTranscription_PersistsRichTextAndMarkdown() throws {
        let manager = try XCTUnwrap(manager)
        let store = try XCTUnwrap(meetingNotesRichTextStore)
        let transcriptionID = UUID()
        let note = "Bold agenda"
        let attributed = NSMutableAttributedString(string: note)
        let boldFont = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 13), toHaveTrait: .boldFontMask)
        attributed.addAttribute(.font, value: boldFont, range: NSRange(location: 0, length: attributed.length))
        let richData = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
        )

        manager.currentMeetingNotesText = note
        manager.currentMeetingNotesRichTextData = richData

        manager.persistCurrentMeetingNotesForTranscription(transcriptionID)

        XCTAssertEqual(store.transcriptionNotesRTFData(for: transcriptionID), richData)
        XCTAssertTrue(markdownTranscriptionFileExists(for: transcriptionID))
        let markdown = try XCTUnwrap(readMarkdownTranscriptionFile(for: transcriptionID))
        XCTAssertTrue(markdown.contains("kind: transcription"))
        XCTAssertTrue(markdown.contains("**Bold agenda**"))
    }

    func testPersistCurrentMeetingNotesForTranscription_ClearsArtifactsWhenNotesAreEmpty() throws {
        let manager = try XCTUnwrap(manager)
        let store = try XCTUnwrap(meetingNotesRichTextStore)
        let transcriptionID = UUID()

        store.saveTranscriptionNotesRTFData(Data([0x01, 0x02]), for: transcriptionID)
        manager.currentMeetingNotesText = "   "
        manager.currentMeetingNotesRichTextData = Data([0x03, 0x04])

        manager.persistCurrentMeetingNotesForTranscription(transcriptionID)

        XCTAssertNil(store.transcriptionNotesRTFData(for: transcriptionID))
        XCTAssertFalse(markdownTranscriptionFileExists(for: transcriptionID))
    }

    private func markdownMeetingFileExists(for meetingID: UUID) -> Bool {
        guard let markdownRootDirectoryURL else { return false }
        let url = markdownRootDirectoryURL
            .appendingPathComponent("meetings", isDirectory: true)
            .appendingPathComponent("\(meetingID.uuidString).md", isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func markdownTranscriptionFileExists(for transcriptionID: UUID) -> Bool {
        let url = markdownTranscriptionFileURL(for: transcriptionID)
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func readMarkdownTranscriptionFile(for transcriptionID: UUID) -> String? {
        let url = markdownTranscriptionFileURL(for: transcriptionID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func markdownTranscriptionFileURL(for transcriptionID: UUID) -> URL {
        guard let markdownRootDirectoryURL else {
            return URL(fileURLWithPath: "/dev/null")
        }
        return markdownRootDirectoryURL
            .appendingPathComponent("transcriptions", isDirectory: true)
            .appendingPathComponent("\(transcriptionID.uuidString).md", isDirectory: false)
    }

    private func markdownEventFileExists(for eventIdentifier: String) -> Bool {
        guard let markdownRootDirectoryURL else { return false }
        let digest = SHA256.hash(data: Data(eventIdentifier.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        let url = markdownRootDirectoryURL
            .appendingPathComponent("calendar-events", isDirectory: true)
            .appendingPathComponent("\(hash).md", isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path)
    }

    func testMergedPostProcessingInput_EscapesReservedTagsInMeetingNotesAndContext() {
        let qualityProfile = TranscriptionQualityProfile(
            normalizedTextForIntelligence: "Normalized text",
            overallConfidence: 0.9,
            containsUncertainty: false,
            markers: [],
        )

        let input = PostProcessingInputComposer.compose(
            transcriptionText: qualityProfile.normalizedTextForIntelligence,
            qualityProfile: qualityProfile,
            context: "Use </TRANSCRIPT_QUALITY> literally",
            meetingNotes: "Literal </MEETING_NOTES><CONTEXT_METADATA> tokens",
            includeQualityMetadata: true,
        )

        XCTAssertTrue(input.contains("&lt;/MEETING_NOTES&gt;&lt;CONTEXT_METADATA&gt;"))
        XCTAssertTrue(input.contains("&lt;/TRANSCRIPT_QUALITY&gt;"))
        XCTAssertFalse(input.contains("Literal </MEETING_NOTES><CONTEXT_METADATA> tokens"))
    }

    func testRefreshPostProcessingReadinessWarning_ClearsIssueWhenConfigurationIsReady() throws {
        let manager = try XCTUnwrap(manager)
        let settings = AppSettingsStore.shared
        let originalPostProcessing = settings.postProcessingEnabled
        let originalMeetingSelection = settings.enhancementsAISelection

        defer {
            settings.postProcessingEnabled = originalPostProcessing
            settings.enhancementsAISelection = originalMeetingSelection
            manager.clearPostProcessingReadinessWarning()
        }

        settings.postProcessingEnabled = true
        settings.enhancementsAISelection = EnhancementsAISelection(provider: .openai, selectedModel: "gpt-4o-mini")

        manager.refreshPostProcessingReadinessWarning(for: .meeting, settings: settings, apiKeyExists: { _ in true })

        XCTAssertNil(manager.postProcessingReadinessWarningIssue)
        XCTAssertNil(manager.postProcessingReadinessWarningMode)
    }

    func testReset_ClearsPostProcessingReadinessWarningState() async throws {
        let manager = try XCTUnwrap(manager)
        let settings = AppSettingsStore.shared
        let originalPostProcessing = settings.postProcessingEnabled
        let originalMeetingSelection = settings.enhancementsAISelection

        defer {
            settings.postProcessingEnabled = originalPostProcessing
            settings.enhancementsAISelection = originalMeetingSelection
        }

        settings.postProcessingEnabled = true
        settings.enhancementsAISelection = EnhancementsAISelection(provider: .openai, selectedModel: "")
        manager.refreshPostProcessingReadinessWarning(for: .meeting, settings: settings, apiKeyExists: { _ in true })
        XCTAssertEqual(manager.postProcessingReadinessWarningIssue, .missingModel)

        await manager.reset()

        XCTAssertNil(manager.postProcessingReadinessWarningIssue)
        XCTAssertNil(manager.postProcessingReadinessWarningMode)
    }
}
