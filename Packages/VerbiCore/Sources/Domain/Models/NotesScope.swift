import Foundation

/// Identifies which meeting-notes document the pane is editing.
public enum NotesScope: Equatable, Hashable, Sendable {
    case calendarEvent(eventIdentifier: String)
    case meetingSession(meetingID: UUID)
    case transcription(transcriptionID: UUID)

    public var documentId: String {
        switch self {
        case let .calendarEvent(eventIdentifier):
            "calendar-event-notes-\(eventIdentifier)"
        case let .meetingSession(meetingID):
            "meeting-panel-\(meetingID.uuidString)"
        case let .transcription(transcriptionID):
            "transcription-notes-\(transcriptionID.uuidString)"
        }
    }
}
