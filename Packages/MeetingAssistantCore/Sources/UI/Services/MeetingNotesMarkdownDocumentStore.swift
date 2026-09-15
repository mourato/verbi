import AppKit
import CryptoKit
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain

public enum MeetingNotesDocumentKind: String, Sendable {
    case transcription
    case meeting
    case calendarEvent
}

public enum MeetingNotesDocumentKey: Hashable, Sendable {
    case transcription(UUID)
    case meeting(UUID)
    case calendarEvent(String)
}

public struct MeetingNotesMarkdownDocument: Equatable, Sendable {
    public let schemaVersion: Int
    public let kind: MeetingNotesDocumentKind
    public let documentId: String
    public let transcriptionId: UUID?
    public let meetingId: UUID?
    public let eventIdentifierHash: String?
    public let eventIdentifierRaw: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let markdownBody: String

    public init(
        schemaVersion: Int,
        kind: MeetingNotesDocumentKind,
        documentId: String,
        transcriptionId: UUID?,
        meetingId: UUID?,
        eventIdentifierHash: String?,
        eventIdentifierRaw: String?,
        createdAt: Date,
        updatedAt: Date,
        markdownBody: String
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.documentId = documentId
        self.transcriptionId = transcriptionId
        self.meetingId = meetingId
        self.eventIdentifierHash = eventIdentifierHash
        self.eventIdentifierRaw = eventIdentifierRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.markdownBody = markdownBody
    }
}

@MainActor
public protocol MeetingNotesMarkdownDocumentStoreProtocol: AnyObject {
    func loadTranscriptionNotesContent(for transcriptionID: UUID, legacyContent: MeetingNotesContent) -> MeetingNotesContent
    func saveTranscriptionNotesContent(_ content: MeetingNotesContent, for transcriptionID: UUID)
    func deleteTranscriptionNotesContent(for transcriptionID: UUID)

    func loadMeetingNotesContent(for meetingID: UUID, legacyContent: MeetingNotesContent) -> MeetingNotesContent
    func saveMeetingNotesContent(_ content: MeetingNotesContent, for meetingID: UUID)
    func deleteMeetingNotesContent(for meetingID: UUID)

    func loadCalendarEventNotesContent(for eventIdentifier: String, legacyContent: MeetingNotesContent) -> MeetingNotesContent
    func saveCalendarEventNotesContent(_ content: MeetingNotesContent, for eventIdentifier: String)
    func deleteCalendarEventNotesContent(for eventIdentifier: String)

    func runBackfillIfNeeded(
        storage: any StorageService,
        meetingNotesRichTextStore: any MeetingNotesRichTextStoreProtocol
    ) async
}

@MainActor
public final class MeetingNotesMarkdownDocumentStore: MeetingNotesMarkdownDocumentStoreProtocol {
    public static let shared = MeetingNotesMarkdownDocumentStore()

    private enum Keys {
        static let markdownBackfillCheckpoint = "storage.migrations.meeting_notes_markdown_backfill.v1"
        static let includeRawEventIdentifier = "storage.meeting_notes.markdown.include_raw_event_identifier.v1"
    }

    private enum LegacyKeys {
        static let meetingPrefix = "meetingNotes."
        static let eventPrefix = "meetingNotes.event."
        static let meetingRichPrefix = "meetingNotes.rich."
        static let eventRichPrefix = "meetingNotes.event.rich."
        static let transcriptionRichPrefix = "meetingNotes.transcription.rich."
    }

    private enum Paths {
        static let folder = "meeting-notes"
        static let schemaVersionFolder = "v1"
        static let transcriptions = "transcriptions"
        static let meetings = "meetings"
        static let calendarEvents = "calendar-events"
        static let markdownExtension = "md"
    }

    fileprivate enum StoreError: Error {
        case invalidFrontMatter
        case invalidCalendarEventIdentifier
        case malformedCalendarEventHash
    }

    private static let schemaVersion = 1
    private static let controlCharactersToTrim = CharacterSet.whitespacesAndNewlines

    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let rootDirectoryURL: URL
    private let markdownFormatter = MeetingNotesMarkdownFormatter()
    private let now: () -> Date
    private let writeCoordinator: MeetingNotesMarkdownWriteCoordinator?
    private var nextWriteSequence: UInt64 = 0
    private var pendingWriteSubmissionTasks: [Task<Void, Never>] = []

    private let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let isoFormatterWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        rootDirectoryURL: URL? = nil,
        now: @escaping () -> Date = Date.init,
        writesAsynchronously: Bool = true,
        writeCoalescingNanoseconds: UInt64 = 120_000_000
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.now = now
        if let rootDirectoryURL {
            self.rootDirectoryURL = rootDirectoryURL
        } else {
            self.rootDirectoryURL = AppIdentity
                .appSupportBaseDirectory(fileManager: fileManager)
                .appendingPathComponent(Paths.folder, isDirectory: true)
                .appendingPathComponent(Paths.schemaVersionFolder, isDirectory: true)
        }
        if writesAsynchronously {
            writeCoordinator = MeetingNotesMarkdownWriteCoordinator(
                rootDirectoryURL: self.rootDirectoryURL,
                coalescingNanoseconds: writeCoalescingNanoseconds
            )
        } else {
            writeCoordinator = nil
        }
    }

    public func loadTranscriptionNotesContent(
        for transcriptionID: UUID,
        legacyContent: MeetingNotesContent
    ) -> MeetingNotesContent {
        loadContent(for: .transcription(transcriptionID), legacyContent: legacyContent)
    }

    public func saveTranscriptionNotesContent(_ content: MeetingNotesContent, for transcriptionID: UUID) {
        saveContent(content, for: .transcription(transcriptionID))
    }

    public func deleteTranscriptionNotesContent(for transcriptionID: UUID) {
        deleteContent(for: .transcription(transcriptionID))
    }

    public func loadMeetingNotesContent(
        for meetingID: UUID,
        legacyContent: MeetingNotesContent
    ) -> MeetingNotesContent {
        loadContent(for: .meeting(meetingID), legacyContent: legacyContent)
    }

    public func saveMeetingNotesContent(_ content: MeetingNotesContent, for meetingID: UUID) {
        saveContent(content, for: .meeting(meetingID))
    }

    public func deleteMeetingNotesContent(for meetingID: UUID) {
        deleteContent(for: .meeting(meetingID))
    }

    public func loadCalendarEventNotesContent(
        for eventIdentifier: String,
        legacyContent: MeetingNotesContent
    ) -> MeetingNotesContent {
        loadContent(for: .calendarEvent(eventIdentifier), legacyContent: legacyContent)
    }

    public func saveCalendarEventNotesContent(_ content: MeetingNotesContent, for eventIdentifier: String) {
        saveContent(content, for: .calendarEvent(eventIdentifier))
    }

    public func deleteCalendarEventNotesContent(for eventIdentifier: String) {
        deleteContent(for: .calendarEvent(eventIdentifier))
    }

    public func runBackfillIfNeeded(
        storage: any StorageService,
        meetingNotesRichTextStore: any MeetingNotesRichTextStoreProtocol
    ) async {
        guard !userDefaults.bool(forKey: Keys.markdownBackfillCheckpoint) else { return }

        var hasFailures = false
        var didAttemptWrite = false

        do {
            let transcriptions = try await storage.loadTranscriptions()
            let richOnlyTranscriptionIDs = legacyTranscriptionIDsFromRichSidecar()
            let plainByTranscriptionID = Dictionary(
                uniqueKeysWithValues: transcriptions.map { transcription in
                    (
                        transcription.id,
                        transcription.contextItems.first(where: { $0.source == .meetingNotes })?.text ?? ""
                    )
                }
            )
            let transcriptionIDs = Set(transcriptions.map(\.id)).union(richOnlyTranscriptionIDs)

            for transcriptionID in transcriptionIDs {
                let content = MeetingNotesContent(
                    plainText: plainByTranscriptionID[transcriptionID] ?? "",
                    richTextRTFData: meetingNotesRichTextStore.transcriptionNotesRTFData(for: transcriptionID)
                )
                didAttemptWrite = didAttemptWrite || hasPersistedContent(content)
                if !backfillIfMissing(content, for: .transcription(transcriptionID)) {
                    hasFailures = true
                }
            }
        } catch {
            hasFailures = true
            AppLogger.error(
                "Meeting notes markdown backfill failed to load transcriptions",
                category: .storage,
                error: error
            )
        }

        for meetingID in legacyMeetingIDs() {
            let content = MeetingNotesContent(
                plainText: userDefaults.string(forKey: LegacyKeys.meetingPrefix + meetingID.uuidString) ?? "",
                richTextRTFData: meetingNotesRichTextStore.meetingNotesRTFData(for: meetingID)
            )
            didAttemptWrite = didAttemptWrite || hasPersistedContent(content)
            if !backfillIfMissing(content, for: .meeting(meetingID)) {
                hasFailures = true
            }
        }

        for eventIdentifier in legacyEventIdentifiers() {
            let content = MeetingNotesContent(
                plainText: userDefaults.string(forKey: LegacyKeys.eventPrefix + eventIdentifier) ?? "",
                richTextRTFData: meetingNotesRichTextStore.calendarEventNotesRTFData(for: eventIdentifier)
            )
            didAttemptWrite = didAttemptWrite || hasPersistedContent(content)
            if !backfillIfMissing(content, for: .calendarEvent(eventIdentifier)) {
                hasFailures = true
            }
        }

        if !hasFailures {
            clearLegacyPlainTextKeys()
            userDefaults.set(true, forKey: Keys.markdownBackfillCheckpoint)
            AppLogger.info(
                "Meeting notes markdown backfill completed",
                category: .storage,
                extra: ["wroteDocuments": didAttemptWrite]
            )
        }
    }

    private func loadContent(
        for key: MeetingNotesDocumentKey,
        legacyContent: MeetingNotesContent
    ) -> MeetingNotesContent {
        do {
            guard let document = try readDocument(for: key) else {
                if shouldUseLegacyFallback(for: legacyContent) {
                    writeContent(legacyContent, for: key, overwriteExisting: false)
                    return legacyContent
                }
                return .empty
            }
            return content(from: document, richTextRTFData: legacyContent.richTextRTFData)
        } catch {
            AppLogger.error(
                "Failed to parse meeting notes markdown document; using legacy fallback",
                category: .storage,
                error: error
            )
            if shouldUseLegacyFallback(for: legacyContent) {
                writeContent(legacyContent, for: key, overwriteExisting: true)
                return legacyContent
            }
            return .empty
        }
    }

    private func shouldUseLegacyFallback(for legacyContent: MeetingNotesContent) -> Bool {
        !userDefaults.bool(forKey: Keys.markdownBackfillCheckpoint) && hasPersistedContent(legacyContent)
    }

    private func saveContent(_ content: MeetingNotesContent, for key: MeetingNotesDocumentKey) {
        if let writeCoordinator {
            let sequence = consumeNextWriteSequence()
            let submissionTask = writeCoordinator.enqueueSaveFromAnyThread(
                content: content,
                for: key,
                sequence: sequence,
                overwriteExisting: true,
                includeRawEventIdentifier: userDefaults.bool(forKey: Keys.includeRawEventIdentifier),
                timestamp: now()
            )
            pendingWriteSubmissionTasks.append(submissionTask)
            return
        }
        writeContent(content, for: key, overwriteExisting: true)
    }

    private func deleteContent(for key: MeetingNotesDocumentKey) {
        if let writeCoordinator {
            let sequence = consumeNextWriteSequence()
            let submissionTask = writeCoordinator.enqueueDeleteFromAnyThread(for: key, sequence: sequence)
            pendingWriteSubmissionTasks.append(submissionTask)
            return
        }

        let documentURL: URL
        do {
            documentURL = try fileURL(for: key)
        } catch {
            AppLogger.error("Failed to resolve markdown notes path for deletion", category: .storage, error: error)
            return
        }

        guard fileManager.fileExists(atPath: documentURL.path) else { return }
        do {
            try fileManager.removeItem(at: documentURL)
        } catch {
            AppLogger.error("Failed to delete markdown notes document", category: .storage, error: error)
        }
    }

    func flushPendingWritesForTests() async {
        while !pendingWriteSubmissionTasks.isEmpty {
            let tasks = pendingWriteSubmissionTasks
            pendingWriteSubmissionTasks.removeAll(keepingCapacity: true)
            for task in tasks {
                await task.value
            }
        }
        await writeCoordinator?.flush()
    }

    private func consumeNextWriteSequence() -> UInt64 {
        nextWriteSequence &+= 1
        return nextWriteSequence
    }

    private func backfillIfMissing(_ content: MeetingNotesContent, for key: MeetingNotesDocumentKey) -> Bool {
        guard hasPersistedContent(content) else { return true }

        let documentURL: URL
        do {
            documentURL = try fileURL(for: key)
        } catch {
            AppLogger.error("Failed to resolve markdown notes path during backfill", category: .storage, error: error)
            return false
        }

        guard !fileManager.fileExists(atPath: documentURL.path) else {
            return true
        }

        do {
            try writeContentOrThrow(content, for: key, overwriteExisting: false)
            return true
        } catch {
            AppLogger.error("Failed to write markdown notes backfill file", category: .storage, error: error)
            return false
        }
    }

    private func writeContent(
        _ content: MeetingNotesContent,
        for key: MeetingNotesDocumentKey,
        overwriteExisting: Bool
    ) {
        do {
            try writeContentOrThrow(content, for: key, overwriteExisting: overwriteExisting)
        } catch {
            AppLogger.error("Failed to write markdown notes document", category: .storage, error: error)
        }
    }

    private func writeContentOrThrow(
        _ content: MeetingNotesContent,
        for key: MeetingNotesDocumentKey,
        overwriteExisting: Bool
    ) throws {
        let fileURL = try fileURL(for: key)
        if !overwriteExisting, fileManager.fileExists(atPath: fileURL.path) {
            return
        }

        guard hasPersistedContent(content) else {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            return
        }

        try ensureDirectoryStructure(for: fileURL)
        let existingDocument = try? readDocument(for: key)
        let timestamp = now()
        let document = makeDocument(
            for: key,
            content: content,
            createdAt: existingDocument?.createdAt ?? timestamp,
            updatedAt: timestamp
        )
        let serialized = serialize(document)
        try serialized.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func hasPersistedContent(_ content: MeetingNotesContent) -> Bool {
        if !content.plainText.trimmingCharacters(in: Self.controlCharactersToTrim).isEmpty {
            return true
        }
        if let richTextRTFData = content.richTextRTFData, !richTextRTFData.isEmpty {
            return true
        }
        return false
    }

    private func content(from document: MeetingNotesMarkdownDocument, richTextRTFData: Data? = nil) -> MeetingNotesContent {
        MeetingNotesContent(plainText: document.markdownBody, richTextRTFData: richTextRTFData)
    }

    private func makeDocument(
        for key: MeetingNotesDocumentKey,
        content: MeetingNotesContent,
        createdAt: Date,
        updatedAt: Date
    ) -> MeetingNotesMarkdownDocument {
        let markdownBody = markdownBodyForPersistence(from: content)
        let eventIdentifierHash: String? = if case let .calendarEvent(eventIdentifier) = key {
            normalizedCalendarEventIdentifier(eventIdentifier).map(Self.sha256Hex)
        } else {
            nil
        }
        let eventIdentifierRaw: String? = if case let .calendarEvent(eventIdentifier) = key,
                                             userDefaults.bool(forKey: Keys.includeRawEventIdentifier)
        {
            normalizedCalendarEventIdentifier(eventIdentifier)
        } else {
            nil
        }

        return MeetingNotesMarkdownDocument(
            schemaVersion: Self.schemaVersion,
            kind: key.documentKind,
            documentId: key.documentId,
            transcriptionId: key.transcriptionID,
            meetingId: key.meetingID,
            eventIdentifierHash: eventIdentifierHash,
            eventIdentifierRaw: eventIdentifierRaw,
            createdAt: createdAt,
            updatedAt: updatedAt,
            markdownBody: markdownBody
        )
    }

    private func markdownBodyForPersistence(from content: MeetingNotesContent) -> String {
        if let richTextRTFData = content.richTextRTFData,
           !richTextRTFData.isEmpty,
           let attributedText = try? NSAttributedString(
               data: richTextRTFData,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           )
        {
            let markdown = markdownFormatter.markdownForPersistence(from: attributedText)
            let trimmedMarkdown = markdown.trimmingCharacters(in: Self.controlCharactersToTrim)
            if !trimmedMarkdown.isEmpty {
                return trimmedMarkdown
            }
        }

        return MeetingNotesMarkdownSanitizer
            .sanitizeForMarkdownRendering(content.plainText)
            .trimmingCharacters(in: Self.controlCharactersToTrim)
    }

    private func readDocument(for key: MeetingNotesDocumentKey) throws -> MeetingNotesMarkdownDocument? {
        let fileURL = try fileURL(for: key)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        return try deserialize(raw)
    }

    private func serialize(_ document: MeetingNotesMarkdownDocument) -> String {
        var lines: [String] = [
            "---",
            "schemaVersion: \(document.schemaVersion)",
            "kind: \(document.kind.rawValue)",
            "documentId: \(quoted(document.documentId))"
        ]

        if let transcriptionId = document.transcriptionId {
            lines.append("transcriptionId: \(transcriptionId.uuidString)")
        }
        if let meetingId = document.meetingId {
            lines.append("meetingId: \(meetingId.uuidString)")
        }
        if let eventIdentifierHash = document.eventIdentifierHash {
            lines.append("eventIdentifierHash: \(eventIdentifierHash)")
        }
        if let eventIdentifierRaw = document.eventIdentifierRaw {
            lines.append("eventIdentifierRaw: \(quoted(eventIdentifierRaw))")
        }
        lines.append("createdAt: \(isoFormatterWithFractionalSeconds.string(from: document.createdAt))")
        lines.append("updatedAt: \(isoFormatterWithFractionalSeconds.string(from: document.updatedAt))")
        lines.append("---")
        lines.append(document.markdownBody)
        return lines.joined(separator: "\n")
    }

    private func deserialize(_ rawDocument: String) throws -> MeetingNotesMarkdownDocument {
        let normalized = rawDocument
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard normalized.hasPrefix("---\n") else {
            throw StoreError.invalidFrontMatter
        }

        guard let closingRange = normalized.range(of: "\n---\n") else {
            throw StoreError.invalidFrontMatter
        }

        let frontMatterStart = normalized.index(normalized.startIndex, offsetBy: 4)
        let frontMatter = String(normalized[frontMatterStart ..< closingRange.lowerBound])
        let bodyStart = closingRange.upperBound
        let markdownBody = String(normalized[bodyStart...])

        var values: [String: String] = [:]
        for line in frontMatter.split(separator: "\n", omittingEmptySubsequences: true) {
            let rawLine = String(line)
            guard let separatorIndex = rawLine.firstIndex(of: ":") else {
                continue
            }

            let key = String(rawLine[..<separatorIndex]).trimmingCharacters(in: Self.controlCharactersToTrim)
            var value = String(rawLine[rawLine.index(after: separatorIndex)...])
                .trimmingCharacters(in: Self.controlCharactersToTrim)
            value = unquoted(value)
            values[key] = value
        }

        guard let schemaVersionText = values["schemaVersion"],
              let schemaVersion = Int(schemaVersionText),
              let kindRawValue = values["kind"],
              let kind = MeetingNotesDocumentKind(rawValue: kindRawValue),
              let documentId = values["documentId"],
              let createdAtText = values["createdAt"],
              let updatedAtText = values["updatedAt"],
              let createdAt = parseISODate(createdAtText),
              let updatedAt = parseISODate(updatedAtText)
        else {
            throw StoreError.invalidFrontMatter
        }

        let transcriptionID = values["transcriptionId"].flatMap(UUID.init(uuidString:))
        let meetingID = values["meetingId"].flatMap(UUID.init(uuidString:))
        let eventIdentifierHash = values["eventIdentifierHash"]
        if let eventIdentifierHash, !isValidHash(eventIdentifierHash) {
            throw StoreError.malformedCalendarEventHash
        }

        return MeetingNotesMarkdownDocument(
            schemaVersion: schemaVersion,
            kind: kind,
            documentId: documentId,
            transcriptionId: transcriptionID,
            meetingId: meetingID,
            eventIdentifierHash: eventIdentifierHash,
            eventIdentifierRaw: values["eventIdentifierRaw"],
            createdAt: createdAt,
            updatedAt: updatedAt,
            markdownBody: markdownBody
        )
    }

    private func parseISODate(_ value: String) -> Date? {
        if let date = isoFormatterWithFractionalSeconds.date(from: value) {
            return date
        }
        return isoFormatterWithoutFractionalSeconds.date(from: value)
    }

    private func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else {
            return value
        }
        let startIndex = value.index(after: value.startIndex)
        let endIndex = value.index(before: value.endIndex)
        return value[startIndex ..< endIndex]
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private func ensureDirectoryStructure(for fileURL: URL) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func fileURL(for key: MeetingNotesDocumentKey) throws -> URL {
        let directoryURL = directoryURL(for: key.documentKind)
        let filename = try key.filenameComponent + "." + Paths.markdownExtension
        return directoryURL.appendingPathComponent(filename, isDirectory: false)
    }

    private func directoryURL(for kind: MeetingNotesDocumentKind) -> URL {
        switch kind {
        case .transcription:
            rootDirectoryURL.appendingPathComponent(Paths.transcriptions, isDirectory: true)
        case .meeting:
            rootDirectoryURL.appendingPathComponent(Paths.meetings, isDirectory: true)
        case .calendarEvent:
            rootDirectoryURL.appendingPathComponent(Paths.calendarEvents, isDirectory: true)
        }
    }

    private func legacyMeetingIDs() -> Set<UUID> {
        var ids: Set<UUID> = []
        for key in userDefaults.dictionaryRepresentation().keys {
            if let meetingID = parseUUIDSuffix(forKey: key, prefix: LegacyKeys.meetingPrefix) {
                ids.insert(meetingID)
                continue
            }
            if let meetingID = parseUUIDSuffix(forKey: key, prefix: LegacyKeys.meetingRichPrefix) {
                ids.insert(meetingID)
            }
        }
        return ids
    }

    private func legacyEventIdentifiers() -> Set<String> {
        var identifiers: Set<String> = []
        for key in userDefaults.dictionaryRepresentation().keys {
            if let identifier = parseEventIdentifierSuffix(forKey: key, prefix: LegacyKeys.eventPrefix) {
                identifiers.insert(identifier)
                continue
            }
            if let identifier = parseEventIdentifierSuffix(forKey: key, prefix: LegacyKeys.eventRichPrefix) {
                identifiers.insert(identifier)
            }
        }
        return identifiers
    }

    private func legacyTranscriptionIDsFromRichSidecar() -> Set<UUID> {
        var ids: Set<UUID> = []
        for key in userDefaults.dictionaryRepresentation().keys {
            if let transcriptionID = parseUUIDSuffix(forKey: key, prefix: LegacyKeys.transcriptionRichPrefix) {
                ids.insert(transcriptionID)
            }
        }
        return ids
    }

    private func parseUUIDSuffix(forKey key: String, prefix: String) -> UUID? {
        guard key.hasPrefix(prefix) else { return nil }
        let suffix = String(key.dropFirst(prefix.count))
        return UUID(uuidString: suffix)
    }

    private func parseEventIdentifierSuffix(forKey key: String, prefix: String) -> String? {
        guard key.hasPrefix(prefix) else { return nil }
        let suffix = String(key.dropFirst(prefix.count))
        return normalizedCalendarEventIdentifier(suffix)
    }

    private func normalizedCalendarEventIdentifier(_ identifier: String) -> String? {
        let normalized = identifier.trimmingCharacters(in: Self.controlCharactersToTrim)
        return normalized.isEmpty ? nil : normalized
    }

    private func isValidHash(_ value: String) -> Bool {
        value.range(of: "^[A-Fa-f0-9]{64}$", options: .regularExpression) != nil
    }

    nonisolated static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func clearLegacyPlainTextKeys() {
        for key in userDefaults.dictionaryRepresentation().keys where key.hasPrefix(LegacyKeys.meetingPrefix) || key.hasPrefix(LegacyKeys.eventPrefix) {
            userDefaults.removeObject(forKey: key)
        }
    }
}

extension MeetingNotesDocumentKey {
    var documentKind: MeetingNotesDocumentKind {
        switch self {
        case .transcription:
            .transcription
        case .meeting:
            .meeting
        case .calendarEvent:
            .calendarEvent
        }
    }

    var documentId: String {
        switch self {
        case let .transcription(transcriptionID):
            transcriptionID.uuidString
        case let .meeting(meetingID):
            meetingID.uuidString
        case let .calendarEvent(eventIdentifier):
            MeetingNotesMarkdownDocumentStore.sha256Hex(eventIdentifier.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    var transcriptionID: UUID? {
        if case let .transcription(transcriptionID) = self {
            return transcriptionID
        }
        return nil
    }

    var meetingID: UUID? {
        if case let .meeting(meetingID) = self {
            return meetingID
        }
        return nil
    }

    var filenameComponent: String {
        get throws {
            switch self {
            case let .transcription(transcriptionID):
                return transcriptionID.uuidString
            case let .meeting(meetingID):
                return meetingID.uuidString
            case let .calendarEvent(eventIdentifier):
                let normalized = eventIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else {
                    throw MeetingNotesMarkdownDocumentStore.StoreError.invalidCalendarEventIdentifier
                }
                return MeetingNotesMarkdownDocumentStore.sha256Hex(normalized)
            }
        }
    }
}
