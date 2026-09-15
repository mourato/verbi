import AppKit
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

extension RecordingManager {
    private enum MeetingNotesConstants {
        static let userDefaultsKeyPrefix = "meetingNotes."
        static let eventUserDefaultsKeyPrefix = "meetingNotes.event."
        static let mergeSeparator = "\n\n---\n\n"
    }

    public func toggleMeetingNotesPanel() {
        isMeetingNotesPanelVisible.toggle()
    }

    public func setMeetingNotesPanelVisible(_ isVisible: Bool) {
        isMeetingNotesPanelVisible = isVisible
    }

    func restoreMeetingNotesIfNeeded(for meetingID: UUID) {
        let content = loadMeetingNotesContent(for: meetingID)
        currentMeetingNotesText = content.plainText
        currentMeetingNotesRichTextData = content.richTextRTFData
    }

    public func updateMeetingNotes(_ content: MeetingNotesContent) {
        guard let meeting = currentMeeting,
              meeting.capturePurpose == .meeting
        else {
            currentMeetingNotesText = ""
            currentMeetingNotesRichTextData = nil
            return
        }

        currentMeetingNotesText = content.plainText
        currentMeetingNotesRichTextData = content.richTextRTFData
        saveSharedMeetingNotesContent(content, for: meeting)
    }

    public func updateMeetingNotesText(_ text: String) {
        updateMeetingNotes(MeetingNotesContent(plainText: text))
    }

    func loadCalendarEventNotesContent(for eventIdentifier: String) -> MeetingNotesContent {
        guard let normalizedIdentifier = normalizedCalendarEventIdentifier(eventIdentifier) else {
            return .empty
        }

        let legacyContent = MeetingNotesContent(
            plainText: UserDefaults.standard.string(forKey: calendarEventNotesKey(for: normalizedIdentifier)) ?? "",
            richTextRTFData: meetingNotesRichTextStore.calendarEventNotesRTFData(for: normalizedIdentifier)
        )
        return meetingNotesMarkdownStore.loadCalendarEventNotesContent(
            for: normalizedIdentifier,
            legacyContent: legacyContent
        )
    }

    func loadCalendarEventNotesText(for eventIdentifier: String) -> String {
        loadCalendarEventNotesContent(for: eventIdentifier).plainText
    }

    func updateCalendarEventNotes(_ content: MeetingNotesContent, for eventIdentifier: String) {
        guard let normalizedIdentifier = normalizedCalendarEventIdentifier(eventIdentifier) else {
            return
        }

        saveCalendarEventNotesContent(content, for: normalizedIdentifier)

        guard let meeting = currentMeeting,
              meeting.capturePurpose == .meeting,
              meeting.linkedCalendarEvent?.eventIdentifier == normalizedIdentifier
        else {
            return
        }

        currentMeetingNotesText = content.plainText
        currentMeetingNotesRichTextData = content.richTextRTFData
        saveMeetingNotesContent(content, for: meeting.id)
    }

    func updateCalendarEventNotesText(_ text: String, for eventIdentifier: String) {
        updateCalendarEventNotes(MeetingNotesContent(plainText: text), for: eventIdentifier)
    }

    func loadSharedMeetingNotesContent(for meeting: Meeting) -> MeetingNotesContent {
        if let linkedEventIdentifier = meeting.linkedCalendarEvent?.eventIdentifier,
           let normalizedLinkedEventIdentifier = normalizedCalendarEventIdentifier(linkedEventIdentifier)
        {
            let eventContent = loadCalendarEventNotesContent(for: normalizedLinkedEventIdentifier)
            if hasPersistedMeetingNotes(eventContent) {
                return eventContent
            }
        }

        let meetingContent = loadMeetingNotesContent(for: meeting.id)
        if hasPersistedMeetingNotes(meetingContent) {
            return meetingContent
        }

        return .empty
    }

    func saveSharedMeetingNotesContent(_ content: MeetingNotesContent, for meeting: Meeting) {
        saveMeetingNotesContent(content, for: meeting.id)

        if let linkedEventIdentifier = meeting.linkedCalendarEvent?.eventIdentifier,
           let normalizedLinkedEventIdentifier = normalizedCalendarEventIdentifier(linkedEventIdentifier)
        {
            saveCalendarEventNotesContent(content, for: normalizedLinkedEventIdentifier)
        }
    }

    func synchronizeMeetingNotesWithLinkedCalendarEventIfNeeded(
        linkedEventIdentifier overrideLinkedEventIdentifier: String? = nil
    ) {
        guard let meeting = currentMeeting,
              meeting.capturePurpose == .meeting
        else {
            return
        }

        let linkedEventIdentifier = overrideLinkedEventIdentifier ?? meeting.linkedCalendarEvent?.eventIdentifier
        guard let linkedEventIdentifier,
              let normalizedIdentifier = normalizedCalendarEventIdentifier(linkedEventIdentifier)
        else {
            return
        }

        let eventContent = loadCalendarEventNotesContent(for: normalizedIdentifier)
        let meetingContent = MeetingNotesContent(
            plainText: currentMeetingNotesText,
            richTextRTFData: currentMeetingNotesRichTextData
        )
        let mergedContent = mergeLinkedNotes(eventContent: eventContent, meetingContent: meetingContent)

        currentMeetingNotesText = mergedContent.plainText
        currentMeetingNotesRichTextData = mergedContent.richTextRTFData
        saveMeetingNotesContent(mergedContent, for: meeting.id)
        saveCalendarEventNotesContent(mergedContent, for: normalizedIdentifier)
    }

    func meetingNotesContextItem(
        from content: MeetingNotesContent,
        capturePurpose: CapturePurpose
    ) -> TranscriptionContextItem? {
        guard capturePurpose == .meeting else { return nil }

        let trimmed = content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return TranscriptionContextItem(source: .meetingNotes, text: trimmed)
    }

    func persistCurrentMeetingNotesForTranscription(_ transcriptionID: UUID) {
        persistMeetingNotes(
            MeetingNotesContent(
                plainText: currentMeetingNotesText,
                richTextRTFData: currentMeetingNotesRichTextData
            ),
            forTranscription: transcriptionID
        )
    }

    func persistMeetingNotes(_ content: MeetingNotesContent, forTranscription transcriptionID: UUID) {
        let trimmed = normalizedNotesValue(content.plainText)
        if trimmed.isEmpty {
            meetingNotesRichTextStore.saveTranscriptionNotesRTFData(nil, for: transcriptionID)
            meetingNotesMarkdownStore.deleteTranscriptionNotesContent(for: transcriptionID)
            return
        }

        meetingNotesRichTextStore.saveTranscriptionNotesRTFData(content.richTextRTFData, for: transcriptionID)
        meetingNotesMarkdownStore.saveTranscriptionNotesContent(content, for: transcriptionID)
    }

    func clearMeetingNotesState(removePersistedValue: Bool, meetingID: UUID? = nil) {
        let persistedMeetingID = meetingID ?? currentMeeting?.id
        if removePersistedValue, let persistedMeetingID {
            removeMeetingNotesContent(for: persistedMeetingID)
        }

        if let meetingID, currentMeeting?.id != meetingID {
            return
        }

        isMeetingNotesPanelVisible = false
        currentMeetingNotesText = ""
        currentMeetingNotesRichTextData = nil
    }

    func loadMeetingNotesContent(for meetingID: UUID) -> MeetingNotesContent {
        let legacyContent = MeetingNotesContent(
            plainText: UserDefaults.standard.string(forKey: meetingNotesKey(for: meetingID)) ?? "",
            richTextRTFData: meetingNotesRichTextStore.meetingNotesRTFData(for: meetingID)
        )
        return meetingNotesMarkdownStore.loadMeetingNotesContent(for: meetingID, legacyContent: legacyContent)
    }

    private func saveMeetingNotesContent(_ content: MeetingNotesContent, for meetingID: UUID) {
        if normalizedNotesValue(content.plainText).isEmpty {
            meetingNotesRichTextStore.saveMeetingNotesRTFData(nil, for: meetingID)
            meetingNotesMarkdownStore.deleteMeetingNotesContent(for: meetingID)
            return
        }

        meetingNotesRichTextStore.saveMeetingNotesRTFData(content.richTextRTFData, for: meetingID)
        meetingNotesMarkdownStore.saveMeetingNotesContent(content, for: meetingID)
    }

    private func removeMeetingNotesContent(for meetingID: UUID) {
        meetingNotesRichTextStore.saveMeetingNotesRTFData(nil, for: meetingID)
        meetingNotesMarkdownStore.deleteMeetingNotesContent(for: meetingID)
    }

    private func meetingNotesKey(for meetingID: UUID) -> String {
        MeetingNotesConstants.userDefaultsKeyPrefix + meetingID.uuidString
    }

    private func saveCalendarEventNotesContent(_ content: MeetingNotesContent, for eventIdentifier: String) {
        guard let normalizedIdentifier = normalizedCalendarEventIdentifier(eventIdentifier) else { return }
        if normalizedNotesValue(content.plainText).isEmpty {
            meetingNotesRichTextStore.saveCalendarEventNotesRTFData(nil, for: normalizedIdentifier)
            meetingNotesMarkdownStore.deleteCalendarEventNotesContent(for: normalizedIdentifier)
            return
        }

        meetingNotesRichTextStore.saveCalendarEventNotesRTFData(content.richTextRTFData, for: normalizedIdentifier)
        meetingNotesMarkdownStore.saveCalendarEventNotesContent(content, for: normalizedIdentifier)
    }

    private func calendarEventNotesKey(for eventIdentifier: String) -> String {
        MeetingNotesConstants.eventUserDefaultsKeyPrefix + eventIdentifier
    }

    private func normalizedCalendarEventIdentifier(_ identifier: String) -> String? {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizedNotesValue(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func hasPersistedMeetingNotes(_ content: MeetingNotesContent) -> Bool {
        !normalizedNotesValue(content.plainText).isEmpty || (content.richTextRTFData?.isEmpty == false)
    }

    private func mergeLinkedNotes(
        eventContent: MeetingNotesContent,
        meetingContent: MeetingNotesContent
    ) -> MeetingNotesContent {
        let normalizedEventNotes = normalizedNotesValue(eventContent.plainText)
        let normalizedMeetingNotes = normalizedNotesValue(meetingContent.plainText)

        if normalizedEventNotes.isEmpty {
            return meetingContent
        }

        if normalizedMeetingNotes.isEmpty {
            return eventContent
        }

        if normalizedEventNotes == normalizedMeetingNotes {
            return MeetingNotesContent(
                plainText: eventContent.plainText,
                richTextRTFData: eventContent.richTextRTFData ?? meetingContent.richTextRTFData
            )
        }

        let mergedPlainText = normalizedEventNotes
            + MeetingNotesConstants.mergeSeparator
            + normalizedMeetingNotes
        let mergedRichText = mergeLinkedRichTextData(
            eventContent: eventContent,
            meetingContent: meetingContent,
            normalizedEventNotes: normalizedEventNotes,
            normalizedMeetingNotes: normalizedMeetingNotes
        )

        return MeetingNotesContent(plainText: mergedPlainText, richTextRTFData: mergedRichText)
    }

    private func mergeLinkedRichTextData(
        eventContent: MeetingNotesContent,
        meetingContent: MeetingNotesContent,
        normalizedEventNotes: String,
        normalizedMeetingNotes: String
    ) -> Data? {
        let eventAttributed = attributedString(from: eventContent.richTextRTFData)
            ?? NSAttributedString(string: normalizedEventNotes)
        let meetingAttributed = attributedString(from: meetingContent.richTextRTFData)
            ?? NSAttributedString(string: normalizedMeetingNotes)

        let merged = NSMutableAttributedString(attributedString: eventAttributed)
        merged.append(NSAttributedString(string: MeetingNotesConstants.mergeSeparator))
        merged.append(meetingAttributed)

        if let serialized = rtfData(from: merged) {
            return serialized
        }

        return eventContent.richTextRTFData ?? meetingContent.richTextRTFData
    }

    private func attributedString(from rtfData: Data?) -> NSAttributedString? {
        guard let rtfData, !rtfData.isEmpty else { return nil }
        return try? NSAttributedString(
            data: rtfData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }

    private func rtfData(from attributedText: NSAttributedString) -> Data? {
        guard attributedText.length > 0 else { return nil }
        let fullRange = NSRange(location: 0, length: attributedText.length)
        return try? attributedText.data(
            from: fullRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    func runMeetingNotesMarkdownBackfillIfNeeded() async {
        await meetingNotesMarkdownStore.runBackfillIfNeeded(
            storage: storage,
            meetingNotesRichTextStore: meetingNotesRichTextStore
        )
    }
}
