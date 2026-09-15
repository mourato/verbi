import AppKit
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain

// MARK: - Markdown Write Coordination

actor MeetingNotesMarkdownWriteCoordinator {
    private enum PendingOperation {
        case save(
            sequence: UInt64,
            content: MeetingNotesContent,
            overwriteExisting: Bool,
            includeRawEventIdentifier: Bool,
            timestamp: Date
        )
        case delete(sequence: UInt64)

        var sequence: UInt64 {
            switch self {
            case let .save(sequence, _, _, _, _):
                sequence
            case let .delete(sequence):
                sequence
            }
        }
    }

    private let rootDirectoryURL: URL
    private let coalescingNanoseconds: UInt64
    private let fileManager: FileManager = .default
    private let markdownFormatter = MeetingNotesMarkdownFormatter()
    private let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let trimCharacters = CharacterSet.whitespacesAndNewlines

    private var pendingOperations: [MeetingNotesDocumentKey: PendingOperation] = [:]
    private var workers: [MeetingNotesDocumentKey: Task<Void, Never>] = [:]

    init(rootDirectoryURL: URL, coalescingNanoseconds: UInt64) {
        self.rootDirectoryURL = rootDirectoryURL
        self.coalescingNanoseconds = coalescingNanoseconds
    }

    @discardableResult
    nonisolated func enqueueSaveFromAnyThread(
        content: MeetingNotesContent,
        for key: MeetingNotesDocumentKey,
        sequence: UInt64,
        overwriteExisting: Bool,
        includeRawEventIdentifier: Bool,
        timestamp: Date
    ) -> Task<Void, Never> {
        Task {
            await enqueueSave(
                content: content,
                for: key,
                sequence: sequence,
                overwriteExisting: overwriteExisting,
                includeRawEventIdentifier: includeRawEventIdentifier,
                timestamp: timestamp
            )
        }
    }

    @discardableResult
    nonisolated func enqueueDeleteFromAnyThread(for key: MeetingNotesDocumentKey, sequence: UInt64) -> Task<Void, Never> {
        Task {
            await enqueueDelete(for: key, sequence: sequence)
        }
    }

    private func enqueueSave(
        content: MeetingNotesContent,
        for key: MeetingNotesDocumentKey,
        sequence: UInt64,
        overwriteExisting: Bool,
        includeRawEventIdentifier: Bool,
        timestamp: Date
    ) {
        upsertPendingOperation(
            .save(
                sequence: sequence,
                content: content,
                overwriteExisting: overwriteExisting,
                includeRawEventIdentifier: includeRawEventIdentifier,
                timestamp: timestamp
            ),
            for: key
        )
        ensureWorker(for: key)
    }

    private func enqueueDelete(for key: MeetingNotesDocumentKey, sequence: UInt64) {
        upsertPendingOperation(.delete(sequence: sequence), for: key)
        ensureWorker(for: key)
    }

    private func upsertPendingOperation(_ operation: PendingOperation, for key: MeetingNotesDocumentKey) {
        if let existing = pendingOperations[key], existing.sequence > operation.sequence {
            return
        }
        pendingOperations[key] = operation
    }

    func flush() async {
        while !workers.isEmpty {
            let tasks = Array(workers.values)
            for task in tasks {
                await task.value
            }
        }
    }

    private func ensureWorker(for key: MeetingNotesDocumentKey) {
        guard workers[key] == nil else { return }
        workers[key] = Task { [weak self] in
            await self?.runWorker(for: key)
        }
    }

    private func runWorker(for key: MeetingNotesDocumentKey) async {
        while true {
            if coalescingNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: coalescingNanoseconds)
            } else {
                await Task.yield()
            }

            guard let operation = pendingOperations.removeValue(forKey: key) else {
                break
            }

            apply(operation, for: key)
        }

        workers[key] = nil
    }

    private func apply(_ operation: PendingOperation, for key: MeetingNotesDocumentKey) {
        switch operation {
        case let .save(
            _,
            content: content,
            overwriteExisting: overwriteExisting,
            includeRawEventIdentifier: includeRawEventIdentifier,
            timestamp: timestamp
        ):
            do {
                try writeContent(
                    content,
                    for: key,
                    overwriteExisting: overwriteExisting,
                    includeRawEventIdentifier: includeRawEventIdentifier,
                    timestamp: timestamp
                )
            } catch {
                AppLogger.error("Failed to write markdown notes document", category: .storage, error: error)
            }
        case .delete:
            deleteContent(for: key)
        }
    }

    private func writeContent(
        _ content: MeetingNotesContent,
        for key: MeetingNotesDocumentKey,
        overwriteExisting: Bool,
        includeRawEventIdentifier: Bool,
        timestamp: Date
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
        let markdownBody = markdownBodyForPersistence(from: content)
        let document = makeDocument(
            for: key,
            markdownBody: markdownBody,
            includeRawEventIdentifier: includeRawEventIdentifier,
            timestamp: timestamp
        )
        let serialized = serialize(document)
        try serialized.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func deleteContent(for key: MeetingNotesDocumentKey) {
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

    private func hasPersistedContent(_ content: MeetingNotesContent) -> Bool {
        if !content.plainText.trimmingCharacters(in: trimCharacters).isEmpty {
            return true
        }
        if let richTextRTFData = content.richTextRTFData, !richTextRTFData.isEmpty {
            return true
        }
        return false
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
            let trimmedMarkdown = markdown.trimmingCharacters(in: trimCharacters)
            if !trimmedMarkdown.isEmpty {
                return trimmedMarkdown
            }
        }

        return MeetingNotesMarkdownSanitizer
            .sanitizeForMarkdownRendering(content.plainText)
            .trimmingCharacters(in: trimCharacters)
    }

    private func makeDocument(
        for key: MeetingNotesDocumentKey,
        markdownBody: String,
        includeRawEventIdentifier: Bool,
        timestamp: Date
    ) -> MeetingNotesMarkdownDocument {
        let eventIdentifierHash: String? = if case let .calendarEvent(eventIdentifier) = key {
            normalizedCalendarEventIdentifier(eventIdentifier).map(MeetingNotesMarkdownDocumentStore.sha256Hex)
        } else {
            nil
        }
        let eventIdentifierRaw: String? = if case let .calendarEvent(eventIdentifier) = key,
                                             includeRawEventIdentifier
        {
            normalizedCalendarEventIdentifier(eventIdentifier)
        } else {
            nil
        }

        return MeetingNotesMarkdownDocument(
            schemaVersion: 1,
            kind: key.documentKind,
            documentId: key.documentId,
            transcriptionId: key.transcriptionID,
            meetingId: key.meetingID,
            eventIdentifierHash: eventIdentifierHash,
            eventIdentifierRaw: eventIdentifierRaw,
            createdAt: timestamp,
            updatedAt: timestamp,
            markdownBody: markdownBody
        )
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

    private func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func ensureDirectoryStructure(for fileURL: URL) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func fileURL(for key: MeetingNotesDocumentKey) throws -> URL {
        let directoryURL = directoryURL(for: key.documentKind)
        let filename = try key.filenameComponent + ".md"
        return directoryURL.appendingPathComponent(filename, isDirectory: false)
    }

    private func directoryURL(for kind: MeetingNotesDocumentKind) -> URL {
        switch kind {
        case .transcription:
            rootDirectoryURL.appendingPathComponent("transcriptions", isDirectory: true)
        case .meeting:
            rootDirectoryURL.appendingPathComponent("meetings", isDirectory: true)
        case .calendarEvent:
            rootDirectoryURL.appendingPathComponent("calendar-events", isDirectory: true)
        }
    }

    private func normalizedCalendarEventIdentifier(_ identifier: String) -> String? {
        let normalized = identifier.trimmingCharacters(in: trimCharacters)
        return normalized.isEmpty ? nil : normalized
    }
}
