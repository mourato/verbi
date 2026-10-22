import AppKit
import CryptoKit
import Foundation
@testable import VerbiCore
@testable import VerbiCoreUI
import XCTest

@MainActor
final class MeetingNotesMarkdownDocumentStoreTests: XCTestCase {
    private enum Flags {
        static let backfillCheckpoint = "storage.migrations.meeting_notes_markdown_backfill.v1"
        static let includeRawEventIdentifier = "storage.meeting_notes.markdown.include_raw_event_identifier.v1"
    }

    private var userDefaults: UserDefaults!
    private var suiteName: String!
    private var rootDirectoryURL: URL!
    private var store: MeetingNotesMarkdownDocumentStore!
    private var richTextStore: MeetingNotesRichTextStore!
    private var mockStorage: MockStorageService!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "MeetingNotesMarkdownDocumentStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create test UserDefaults suite")
            return
        }
        userDefaults = defaults
        rootDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-notes-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        store = MeetingNotesMarkdownDocumentStore(
            userDefaults: userDefaults,
            rootDirectoryURL: rootDirectoryURL,
            writesAsynchronously: false,
        )
        richTextStore = MeetingNotesRichTextStore(userDefaults: userDefaults)
        mockStorage = MockStorageService()
    }

    override func tearDown() async throws {
        if let suiteName {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        if let rootDirectoryURL {
            try? FileManager.default.removeItem(at: rootDirectoryURL)
        }
        userDefaults = nil
        suiteName = nil
        rootDirectoryURL = nil
        store = nil
        richTextStore = nil
        mockStorage = nil
        try await super.tearDown()
    }

    func testSaveTranscriptionNotesContent_WritesMarkdownDocumentWithFrontMatterAndBody() throws {
        let transcriptionID = UUID()
        store.saveTranscriptionNotesContent(
            MeetingNotesContent(plainText: "Line 1\nLine 2"),
            for: transcriptionID,
        )

        let content = try XCTUnwrap(try readFile(at: transcriptionURL(for: transcriptionID)))
        XCTAssertTrue(content.contains("schemaVersion: 1"))
        XCTAssertTrue(content.contains("kind: transcription"))
        XCTAssertTrue(content.contains("transcriptionId: \(transcriptionID.uuidString)"))
        XCTAssertTrue(content.contains("Line 1"))
        XCTAssertTrue(content.contains("Line 2"))
    }

    func testSaveTranscriptionNotesContent_PreservesRichTextAsMarkdownAndFallsBackToPlainText() throws {
        let transcriptionID = UUID()
        let richAttributed = NSMutableAttributedString(string: "OpenAI")
        richAttributed.addAttribute(
            .link,
            value: URL(string: "https://openai.com") as Any,
            range: NSRange(location: 0, length: richAttributed.length),
        )
        let richRTF = try richAttributed.data(
            from: NSRange(location: 0, length: richAttributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
        )

        store.saveTranscriptionNotesContent(
            MeetingNotesContent(plainText: "OpenAI", richTextRTFData: richRTF),
            for: transcriptionID,
        )

        let richContent = try XCTUnwrap(try readFile(at: transcriptionURL(for: transcriptionID)))
        XCTAssertTrue(richContent.contains("[OpenAI](https://openai.com)"))

        let invalidRichContent = MeetingNotesContent(
            plainText: "Plain fallback",
            richTextRTFData: Data([0x01, 0x02, 0x03]),
        )
        store.saveTranscriptionNotesContent(invalidRichContent, for: transcriptionID)

        let fallbackContent = try XCTUnwrap(try readFile(at: transcriptionURL(for: transcriptionID)))
        XCTAssertTrue(fallbackContent.contains("Plain fallback"))
    }

    func testLoadMeetingNotesContent_UsesLegacyFallbackBeforeBackfillCheckpoint() throws {
        let meetingID = UUID()
        let loaded = store.loadMeetingNotesContent(
            for: meetingID,
            legacyContent: MeetingNotesContent(plainText: "Legacy source"),
        )

        XCTAssertEqual(loaded.plainText, "Legacy source")
        let healed = try XCTUnwrap(readFile(at: meetingURL(for: meetingID)))
        XCTAssertTrue(healed.contains("Legacy source"))
    }

    func testLoadMeetingNotesContent_PrefersMarkdownAndStopsUsingLegacyFallbackAfterBackfillCheckpoint() throws {
        let meetingID = UUID()
        userDefaults.set(true, forKey: Flags.backfillCheckpoint)
        store.saveMeetingNotesContent(MeetingNotesContent(plainText: "Markdown source"), for: meetingID)

        let preferred = store.loadMeetingNotesContent(
            for: meetingID,
            legacyContent: MeetingNotesContent(plainText: "Legacy source"),
        )
        XCTAssertEqual(preferred.plainText, "Markdown source")

        let meetingFileURL = meetingURL(for: meetingID)
        try "invalid-front-matter".write(to: meetingFileURL, atomically: true, encoding: .utf8)
        let fallback = store.loadMeetingNotesContent(
            for: meetingID,
            legacyContent: MeetingNotesContent(plainText: "Legacy fallback"),
        )
        XCTAssertEqual(fallback, .empty)
    }

    func testRunBackfillIfNeeded_CreatesDocumentsClearsLegacyPlainTextAndIsIdempotent() async throws {
        let transcriptionID = UUID()
        let meetingID = UUID()
        let eventIdentifier = "event-\(UUID().uuidString)"
        mockStorage.mockTranscriptions = [
            makeTranscription(
                id: transcriptionID,
                meetingID: meetingID,
                contextItems: [.init(source: .meetingNotes, text: "Transcription legacy note")],
            ),
        ]
        richTextStore.saveTranscriptionNotesRTFData(Data([0x7b, 0x5c, 0x72, 0x74, 0x66]), for: transcriptionID)

        userDefaults.set("Meeting legacy note", forKey: "meetingNotes.\(meetingID.uuidString)")
        userDefaults.set("Event legacy note", forKey: "meetingNotes.event.\(eventIdentifier)")
        richTextStore.saveMeetingNotesRTFData(Data([0x7b, 0x5c, 0x72, 0x74, 0x66]), for: meetingID)
        richTextStore.saveCalendarEventNotesRTFData(Data([0x7b, 0x5c, 0x72, 0x74, 0x66]), for: eventIdentifier)

        await store.runBackfillIfNeeded(storage: mockStorage, meetingNotesRichTextStore: richTextStore)

        let transcriptionFileURL = transcriptionURL(for: transcriptionID)
        let meetingFileURL = meetingURL(for: meetingID)
        let eventFileURL = eventURL(for: eventIdentifier)
        XCTAssertTrue(FileManager.default.fileExists(atPath: transcriptionFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: meetingFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: eventFileURL.path))
        XCTAssertTrue(userDefaults.bool(forKey: Flags.backfillCheckpoint))
        XCTAssertNil(userDefaults.string(forKey: "meetingNotes.\(meetingID.uuidString)"))
        XCTAssertNil(userDefaults.string(forKey: "meetingNotes.event.\(eventIdentifier)"))

        let firstTranscriptionSnapshot = try XCTUnwrap(try readFile(at: transcriptionFileURL))
        userDefaults.set("Changed legacy value", forKey: "meetingNotes.\(meetingID.uuidString)")
        await store.runBackfillIfNeeded(storage: mockStorage, meetingNotesRichTextStore: richTextStore)
        let secondTranscriptionSnapshot = try XCTUnwrap(try readFile(at: transcriptionFileURL))
        XCTAssertEqual(firstTranscriptionSnapshot, secondTranscriptionSnapshot)
    }

    func testSaveCalendarEventNotesContent_UsesStableHashAndOptionalRawIdentifier() throws {
        let eventIdentifier = "event-\(UUID().uuidString)"
        let expectedHash = sha256Hex(eventIdentifier)

        store.saveCalendarEventNotesContent(
            MeetingNotesContent(plainText: "Event markdown note"),
            for: eventIdentifier,
        )
        let defaultFileContent = try XCTUnwrap(try readFile(at: eventURL(for: eventIdentifier)))
        XCTAssertTrue(defaultFileContent.contains("eventIdentifierHash: \(expectedHash)"))
        XCTAssertFalse(defaultFileContent.contains("eventIdentifierRaw:"))

        userDefaults.set(true, forKey: Flags.includeRawEventIdentifier)
        store.saveCalendarEventNotesContent(
            MeetingNotesContent(plainText: "Event markdown note"),
            for: eventIdentifier,
        )
        let fileWithRawIdentifier = try XCTUnwrap(try readFile(at: eventURL(for: eventIdentifier)))
        XCTAssertTrue(fileWithRawIdentifier.contains("eventIdentifierRaw: \"\(eventIdentifier)\""))
    }

    func testDeleteTranscriptionNotesContent_RemovesFile() {
        let transcriptionID = UUID()
        store.saveTranscriptionNotesContent(MeetingNotesContent(plainText: "to-delete"), for: transcriptionID)
        let fileURL = transcriptionURL(for: transcriptionID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        store.deleteTranscriptionNotesContent(for: transcriptionID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testAsynchronousWrites_LastWriteWinsDeterministically() async throws {
        let asyncStore = MeetingNotesMarkdownDocumentStore(
            userDefaults: userDefaults,
            rootDirectoryURL: rootDirectoryURL,
            writesAsynchronously: true,
            writeCoalescingNanoseconds: 50_000_000,
        )
        let meetingID = UUID()

        asyncStore.saveMeetingNotesContent(MeetingNotesContent(plainText: "first"), for: meetingID)
        asyncStore.saveMeetingNotesContent(MeetingNotesContent(plainText: "second"), for: meetingID)
        await asyncStore.flushPendingWritesForTests()

        let content = try XCTUnwrap(try readFile(at: meetingURL(for: meetingID)))
        XCTAssertTrue(content.contains("second"))
        XCTAssertFalse(content.contains("first"))
    }

    private func transcriptionURL(for transcriptionID: UUID) -> URL {
        rootDirectoryURL
            .appendingPathComponent("transcriptions", isDirectory: true)
            .appendingPathComponent("\(transcriptionID.uuidString).md", isDirectory: false)
    }

    private func meetingURL(for meetingID: UUID) -> URL {
        rootDirectoryURL
            .appendingPathComponent("meetings", isDirectory: true)
            .appendingPathComponent("\(meetingID.uuidString).md", isDirectory: false)
    }

    private func eventURL(for eventIdentifier: String) -> URL {
        rootDirectoryURL
            .appendingPathComponent("calendar-events", isDirectory: true)
            .appendingPathComponent("\(sha256Hex(eventIdentifier)).md", isDirectory: false)
    }

    private func readFile(at url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func makeTranscription(
        id: UUID,
        meetingID: UUID,
        contextItems: [TranscriptionContextItem],
    ) -> CaptureArtifact {
        CaptureArtifact(
            id: id,
            meeting: CaptureSession(
                id: meetingID,
                app: .zoom,
                capturePurpose: .meeting,
                startTime: Date(),
                endTime: Date().addingTimeInterval(60),
            ),
            contextItems: contextItems,
            segments: [.init(speaker: "Speaker 1", text: "content", startTime: 0, endTime: 1)],
            text: "content",
            rawText: "content",
        )
    }
}
