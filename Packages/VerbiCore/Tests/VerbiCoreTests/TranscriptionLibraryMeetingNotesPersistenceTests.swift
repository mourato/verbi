import Foundation
@testable import VerbiCore
@testable import VerbiCoreUI
import XCTest

@MainActor
final class MeetingNotesPersistenceTests: XCTestCase {
    private var viewModel: TranscriptionLibraryViewModel!
    private var recordingManager: RecordingManager!
    private var storage: MockStorageService!
    private var meetingRepository: MockMeetingRepository!
    private var meetingQAService: MockMeetingQAService!
    private var mockMic: MockAudioRecorder!
    private var mockSystem: MockAudioRecorder!
    private var mockTranscriptionClient: MockTranscriptionClient!
    private var mockPostProcessingService: MockPostProcessingService!
    private var mockActiveAppContextProvider: MockActiveAppContextProvider!
    private var mockCaptureContextResolver: MockCaptureContextResolver!
    private var richTextStore: MeetingNotesRichTextStore!
    private var markdownStore: MeetingNotesMarkdownDocumentStore!
    private var userDefaults: UserDefaults!
    private var suiteName: String!
    private var markdownRootDirectoryURL: URL!

    override func setUp() async throws {
        storage = MockStorageService()
        meetingRepository = MockMeetingRepository()
        meetingQAService = MockMeetingQAService()
        mockMic = MockAudioRecorder()
        mockSystem = MockAudioRecorder()
        mockTranscriptionClient = MockTranscriptionClient()
        mockPostProcessingService = MockPostProcessingService()
        mockActiveAppContextProvider = MockActiveAppContextProvider()
        mockCaptureContextResolver = MockCaptureContextResolver()
        suiteName = "MeetingNotesPersistenceTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        richTextStore = MeetingNotesRichTextStore(userDefaults: userDefaults)
        markdownRootDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-notes-persistence-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: markdownRootDirectoryURL, withIntermediateDirectories: true)
        markdownStore = MeetingNotesMarkdownDocumentStore(
            userDefaults: userDefaults,
            rootDirectoryURL: markdownRootDirectoryURL,
            writesAsynchronously: false,
        )
        recordingManager = RecordingManager(
            micRecorder: mockMic,
            systemRecorder: mockSystem,
            transcriptionClient: mockTranscriptionClient,
            postProcessingService: mockPostProcessingService,
            storage: storage,
            activeAppContextProvider: mockActiveAppContextProvider,
            captureContextResolver: mockCaptureContextResolver,
            meetingNotesRichTextStore: richTextStore,
            meetingNotesMarkdownStore: markdownStore,
            apiKeyExists: { _ in true },
        )
        viewModel = TranscriptionLibraryViewModel(
            storage: storage,
            recordingManager: recordingManager,
            meetingRepository: meetingRepository,
            meetingQAService: meetingQAService,
            meetingNotesRichTextStore: richTextStore,
            meetingNotesMarkdownStore: markdownStore,
        )
    }

    override func tearDown() async throws {
        if let suiteName {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        if let markdownRootDirectoryURL {
            try? FileManager.default.removeItem(at: markdownRootDirectoryURL)
        }
        suiteName = nil
        viewModel = nil
        recordingManager = nil
        storage = nil
        meetingRepository = nil
        meetingQAService = nil
        mockMic = nil
        mockSystem = nil
        mockTranscriptionClient = nil
        mockPostProcessingService = nil
        mockActiveAppContextProvider = nil
        mockCaptureContextResolver = nil
        richTextStore = nil
        markdownStore = nil
        userDefaults = nil
        markdownRootDirectoryURL = nil
    }

    func testUpdateMeetingNotes_UpdatesExistingEntryAndPersists() async throws {
        let transcription = makeTranscription(
            contextItems: [
                .init(source: .meetingNotes, text: "Old notes"),
                .init(source: .clipboard, text: "Clipboard context"),
            ],
        )
        storage.mockTranscriptions = [transcription]
        viewModel.selectedTranscription = transcription

        await viewModel.updateMeetingNotes("Updated notes", in: transcription.id)

        let saved = try XCTUnwrap(storage.savedTranscriptions.last)
        let meetingNotes = saved.contextItems.filter { $0.source == .meetingNotes }
        XCTAssertEqual(meetingNotes.count, 1)
        XCTAssertEqual(meetingNotes.first?.text, "Updated notes")
        XCTAssertTrue(saved.contextItems.contains { $0.source == .clipboard && $0.text == "Clipboard context" })
    }

    func testUpdateMeetingNotes_CreatesEntryWhenMissing() async throws {
        let transcription = makeTranscription(
            contextItems: [
                .init(source: .activeApp, text: "Zoom"),
            ],
        )
        storage.mockTranscriptions = [transcription]
        viewModel.selectedTranscription = transcription

        await viewModel.updateMeetingNotes("New notes", in: transcription.id)

        let saved = try XCTUnwrap(storage.savedTranscriptions.last)
        let meetingNotes = saved.contextItems.filter { $0.source == .meetingNotes }
        XCTAssertEqual(meetingNotes.count, 1)
        XCTAssertEqual(meetingNotes.first?.text, "New notes")
        XCTAssertTrue(saved.contextItems.contains { $0.source == .activeApp && $0.text == "Zoom" })
    }

    func testUpdateMeetingNotes_RemovesEntriesWhenCleared() async throws {
        let transcription = makeTranscription(
            contextItems: [
                .init(source: .meetingNotes, text: "Meeting notes"),
                .init(source: .focusedText, text: "Focused context"),
            ],
        )
        storage.mockTranscriptions = [transcription]
        viewModel.selectedTranscription = transcription

        await viewModel.updateMeetingNotes("   ", in: transcription.id)

        let saved = try XCTUnwrap(storage.savedTranscriptions.last)
        XCTAssertTrue(saved.contextItems.allSatisfy { $0.source != .meetingNotes })
        XCTAssertTrue(saved.contextItems.contains { $0.source == .focusedText && $0.text == "Focused context" })
    }

    func testUpdateMeetingNotes_CollapsesDuplicateEntriesIntoSingleItem() async throws {
        let transcription = makeTranscription(
            contextItems: [
                .init(source: .meetingNotes, text: "Old notes 1"),
                .init(source: .activeApp, text: "Slack"),
                .init(source: .meetingNotes, text: "Old notes 2"),
            ],
        )
        storage.mockTranscriptions = [transcription]
        viewModel.selectedTranscription = transcription

        await viewModel.updateMeetingNotes("Canonical notes", in: transcription.id)

        let saved = try XCTUnwrap(storage.savedTranscriptions.last)
        let meetingNotes = saved.contextItems.filter { $0.source == .meetingNotes }
        XCTAssertEqual(meetingNotes.count, 1)
        XCTAssertEqual(meetingNotes.first?.text, "Canonical notes")
        XCTAssertTrue(saved.contextItems.contains { $0.source == .activeApp && $0.text == "Slack" })
    }

    func testUpdateMeetingNotes_UpdatesSelectedTranscriptionAndPreservesOtherContextItems() async throws {
        let transcription = makeTranscription(
            contextItems: [
                .init(source: .meetingNotes, text: "Old notes"),
                .init(source: .calendarEvent, text: "Planning sync"),
                .init(source: .windowTitle, text: "Roadmap"),
            ],
        )
        storage.mockTranscriptions = [transcription]
        viewModel.selectedId = transcription.id
        viewModel.selectedTranscription = transcription

        await viewModel.updateMeetingNotes("Refined notes", in: transcription.id)

        let selected = try XCTUnwrap(viewModel.selectedTranscription)
        XCTAssertEqual(selected.id, transcription.id)
        XCTAssertEqual(selected.contextItems.filter { $0.source == .meetingNotes }.count, 1)
        XCTAssertEqual(
            selected.contextItems.first(where: { $0.source == .meetingNotes })?.text,
            "Refined notes",
        )
        XCTAssertTrue(selected.contextItems.contains { $0.source == .calendarEvent && $0.text == "Planning sync" })
        XCTAssertTrue(selected.contextItems.contains { $0.source == .windowTitle && $0.text == "Roadmap" })
    }

    func testUpdateMeetingNotes_PersistsRichTextSidecar() async throws {
        let transcription = makeTranscription(
            contextItems: [
                .init(source: .meetingNotes, text: "Old notes"),
            ],
        )
        storage.mockTranscriptions = [transcription]
        viewModel.selectedTranscription = transcription

        let richData = Data([0x7b, 0x5c, 0x72, 0x74, 0x66])
        await viewModel.updateMeetingNotes(
            MeetingNotesContent(plainText: "Rich notes", richTextRTFData: richData),
            in: transcription.id,
        )

        XCTAssertEqual(richTextStore.transcriptionNotesRTFData(for: transcription.id), richData)
        let markdownContent = try XCTUnwrap(readMarkdownDocument(for: transcription.id))
        XCTAssertTrue(markdownContent.contains("kind: transcription"))
        XCTAssertTrue(markdownContent.contains("Rich notes"))
    }

    func testUpdateMeetingNotes_ClearsRichTextSidecarWhenNotesAreCleared() async {
        let transcription = makeTranscription(
            contextItems: [
                .init(source: .meetingNotes, text: "Old notes"),
            ],
        )
        storage.mockTranscriptions = [transcription]
        viewModel.selectedTranscription = transcription

        richTextStore.saveTranscriptionNotesRTFData(Data([0x7b, 0x5c, 0x72, 0x74, 0x66]), for: transcription.id)

        await viewModel.updateMeetingNotes(
            MeetingNotesContent(plainText: "   ", richTextRTFData: Data([0x01, 0x02])),
            in: transcription.id,
        )

        XCTAssertNil(richTextStore.transcriptionNotesRTFData(for: transcription.id))
    }

    func testMeetingNotesContent_PrefersSharedCalendarEventNotesForLinkedMeeting() {
        let eventIdentifier = "calendar-event-123"
        let linkedEvent = MeetingCalendarEventSnapshot(
            eventIdentifier: eventIdentifier,
            title: "Weekly Sync",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3_600),
        )
        let transcription = makeTranscription(
            contextItems: [.init(source: .meetingNotes, text: "Legacy transcription notes")],
            linkedCalendarEvent: linkedEvent,
        )
        storage.mockTranscriptions = [transcription]

        let sharedContent = MeetingNotesContent(
            plainText: "Shared calendar notes",
            richTextRTFData: Data([0x7b, 0x5c, 0x72, 0x74, 0x66, 0x31]),
        )
        recordingManager.updateCalendarEventNotes(sharedContent, for: eventIdentifier)

        let loaded = viewModel.meetingNotesContent(for: transcription)
        XCTAssertEqual(loaded, sharedContent)
    }

    func testUpdateMeetingNotes_LinkedMeeting_SyncsMeetingAndCalendarEventStores() async {
        let eventIdentifier = "calendar-event-xyz"
        let linkedEvent = MeetingCalendarEventSnapshot(
            eventIdentifier: eventIdentifier,
            title: "Planning",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1_800),
        )
        let transcription = makeTranscription(
            contextItems: [.init(source: .meetingNotes, text: "Old notes")],
            linkedCalendarEvent: linkedEvent,
        )
        storage.mockTranscriptions = [transcription]
        viewModel.selectedTranscription = transcription

        let richData = Data([0x7b, 0x5c, 0x72, 0x74, 0x66, 0x32])
        await viewModel.updateMeetingNotes(
            MeetingNotesContent(plainText: "Unified notes", richTextRTFData: richData),
            in: transcription.id,
        )

        XCTAssertEqual(richTextStore.meetingNotesRTFData(for: transcription.meeting.id), richData)
        XCTAssertEqual(richTextStore.calendarEventNotesRTFData(for: eventIdentifier), richData)
        XCTAssertNil(userDefaults.string(forKey: "meetingNotes.\(transcription.meeting.id.uuidString)"))
        XCTAssertNil(userDefaults.string(forKey: "meetingNotes.event.\(eventIdentifier)"))
    }

    func testUpdateMeetingNotes_WithoutLinkedEvent_DoesNotWriteCalendarEventStore() async {
        let transcription = makeTranscription(
            contextItems: [.init(source: .meetingNotes, text: "Initial notes")],
            linkedCalendarEvent: nil,
        )
        storage.mockTranscriptions = [transcription]
        viewModel.selectedTranscription = transcription

        let richData = Data([0x7b, 0x5c, 0x72, 0x74, 0x66, 0x33])
        await viewModel.updateMeetingNotes(
            MeetingNotesContent(plainText: "Meeting-only notes", richTextRTFData: richData),
            in: transcription.id,
        )

        XCTAssertEqual(richTextStore.meetingNotesRTFData(for: transcription.meeting.id), richData)
        XCTAssertNil(richTextStore.calendarEventNotesRTFData(for: "non-existent-event"))
    }

    func testMeetingNotesContent_FallsBackToTranscriptionWhenSharedStoresAreEmpty() {
        let transcription = makeTranscription(
            contextItems: [.init(source: .meetingNotes, text: "Transcription fallback notes")],
            linkedCalendarEvent: nil,
        )
        storage.mockTranscriptions = [transcription]

        let loaded = viewModel.meetingNotesContent(for: transcription)
        XCTAssertEqual(loaded.plainText, "Transcription fallback notes")
    }

    func testExecuteDeleteTranscription_RemovesMarkdownDocument() async {
        let transcription = makeTranscription(
            contextItems: [
                .init(source: .meetingNotes, text: "Delete me"),
            ],
        )
        storage.mockTranscriptions = [transcription]
        viewModel.selectedId = transcription.id
        viewModel.selectedTranscription = transcription

        await viewModel.updateMeetingNotes("Delete me", in: transcription.id)
        XCTAssertNotNil(readMarkdownDocument(for: transcription.id))

        let metadata = TranscriptionMetadata(
            id: transcription.id,
            meetingId: transcription.meeting.id,
            meetingTitle: transcription.meeting.preferredTitle,
            appName: transcription.meeting.appName,
            appRawValue: transcription.meeting.app.rawValue,
            capturePurpose: transcription.capturePurpose,
            appBundleIdentifier: transcription.meeting.appBundleIdentifier,
            startTime: transcription.meeting.startTime,
            createdAt: transcription.createdAt,
            previewText: transcription.preview,
            wordCount: transcription.wordCount,
            language: transcription.language,
            isPostProcessed: transcription.isPostProcessed,
            duration: transcription.meeting.duration,
            audioFilePath: transcription.meeting.audioFilePath,
            inputSource: transcription.inputSource,
        )

        viewModel.confirmDeleteTranscription(metadata)
        await viewModel.executeDeleteTranscription()

        XCTAssertNil(readMarkdownDocument(for: transcription.id))
    }

    private func makeTranscription(
        contextItems: [TranscriptionContextItem],
        linkedCalendarEvent: MeetingCalendarEventSnapshot? = nil,
    ) -> CaptureArtifact {
        let id = UUID()
        return CaptureArtifact(
            id: id,
            meeting: CaptureSession(
                id: id,
                app: .zoom,
                linkedCalendarEvent: linkedCalendarEvent,
                startTime: Date(),
                endTime: Date().addingTimeInterval(60),
            ),
            contextItems: contextItems,
            segments: [.init(speaker: "Speaker 1", text: "Content", startTime: 0, endTime: 5)],
            text: "Content",
            rawText: "Content",
        )
    }

    private func readMarkdownDocument(for transcriptionID: UUID) -> String? {
        let fileURL = markdownRootDirectoryURL
            .appendingPathComponent("transcriptions", isDirectory: true)
            .appendingPathComponent("\(transcriptionID.uuidString).md", isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }
}
