import Foundation

@MainActor
public protocol MeetingNotesRichTextStoreProtocol: AnyObject {
    func meetingNotesRTFData(for meetingID: UUID) -> Data?
    func saveMeetingNotesRTFData(_ data: Data?, for meetingID: UUID)

    func calendarEventNotesRTFData(for eventIdentifier: String) -> Data?
    func saveCalendarEventNotesRTFData(_ data: Data?, for eventIdentifier: String)

    func transcriptionNotesRTFData(for transcriptionID: UUID) -> Data?
    func saveTranscriptionNotesRTFData(_ data: Data?, for transcriptionID: UUID)
}

@MainActor
public final class MeetingNotesRichTextStore: MeetingNotesRichTextStoreProtocol {
    private enum Keys {
        static let meetingPrefix = "meetingNotes.rich."
        static let eventPrefix = "meetingNotes.event.rich."
        static let transcriptionPrefix = "meetingNotes.transcription.rich."
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func meetingNotesRTFData(for meetingID: UUID) -> Data? {
        userDefaults.data(forKey: meetingKey(for: meetingID))
    }

    public func saveMeetingNotesRTFData(_ data: Data?, for meetingID: UUID) {
        save(data, forKey: meetingKey(for: meetingID))
    }

    public func calendarEventNotesRTFData(for eventIdentifier: String) -> Data? {
        guard let normalized = normalizedEventIdentifier(eventIdentifier) else { return nil }
        return userDefaults.data(forKey: eventKey(for: normalized))
    }

    public func saveCalendarEventNotesRTFData(_ data: Data?, for eventIdentifier: String) {
        guard let normalized = normalizedEventIdentifier(eventIdentifier) else { return }
        save(data, forKey: eventKey(for: normalized))
    }

    public func transcriptionNotesRTFData(for transcriptionID: UUID) -> Data? {
        userDefaults.data(forKey: transcriptionKey(for: transcriptionID))
    }

    public func saveTranscriptionNotesRTFData(_ data: Data?, for transcriptionID: UUID) {
        save(data, forKey: transcriptionKey(for: transcriptionID))
    }

    private func save(_ data: Data?, forKey key: String) {
        guard let data, !data.isEmpty else {
            userDefaults.removeObject(forKey: key)
            return
        }

        userDefaults.set(data, forKey: key)
    }

    private func normalizedEventIdentifier(_ eventIdentifier: String) -> String? {
        let normalized = eventIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func meetingKey(for meetingID: UUID) -> String {
        Keys.meetingPrefix + meetingID.uuidString
    }

    private func eventKey(for eventIdentifier: String) -> String {
        Keys.eventPrefix + eventIdentifier
    }

    private func transcriptionKey(for transcriptionID: UUID) -> String {
        Keys.transcriptionPrefix + transcriptionID.uuidString
    }
}
