import Foundation
import MeetingAssistantCoreDomain

public extension RecordingManager {
    func loadNotesContent(for scope: NotesScope) -> MeetingNotesContent {
        switch scope {
        case let .calendarEvent(eventIdentifier):
            return loadCalendarEventNotesContent(for: eventIdentifier)
        case let .meetingSession(meetingID):
            if currentMeeting?.id == meetingID {
                return MeetingNotesContent(
                    plainText: currentMeetingNotesText,
                    richTextRTFData: currentMeetingNotesRichTextData
                )
            }
            return loadMeetingNotesContent(for: meetingID)
        case let .transcription(transcriptionID):
            return meetingNotesMarkdownStore.loadTranscriptionNotesContent(
                for: transcriptionID,
                legacyContent: MeetingNotesContent(
                    plainText: "",
                    richTextRTFData: meetingNotesRichTextStore.transcriptionNotesRTFData(for: transcriptionID)
                )
            )
        }
    }

    func persistNotesContent(_ content: MeetingNotesContent, for scope: NotesScope) {
        switch scope {
        case let .calendarEvent(eventIdentifier):
            updateCalendarEventNotes(content, for: eventIdentifier)
        case .meetingSession:
            updateMeetingNotes(content)
        case let .transcription(transcriptionID):
            persistMeetingNotes(content, forTranscription: transcriptionID)
        }
    }
}
