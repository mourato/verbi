import AppKit
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import OSLog
import SwiftUI

public extension TranscriptionSettingsViewModel {
    func renameSpeaker(
        from originalSpeaker: String,
        to updatedSpeaker: String,
        in transcriptionID: UUID
    ) async {
        let oldValue = originalSpeaker.trimmingCharacters(in: .whitespacesAndNewlines)
        let newValue = updatedSpeaker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldValue.isEmpty, !newValue.isEmpty, oldValue != newValue else { return }

        do {
            guard var transcription = selectedTranscription, transcription.id == transcriptionID else {
                guard var loaded = try await storage.loadTranscription(by: transcriptionID) else { return }
                try await renameSpeaker(in: &loaded, from: oldValue, to: newValue, selectedID: transcriptionID)
                return
            }

            try await renameSpeaker(in: &transcription, from: oldValue, to: newValue, selectedID: transcriptionID)
        } catch {
            logger.error("Failed to rename speaker: \(error.localizedDescription)")
            operationErrorMessage = "transcription.speaker.rename.error".localized
        }
    }

    func meetingNotesContent(for transcription: Transcription?) -> MeetingNotesContent {
        guard let transcription else {
            return .empty
        }

        if transcription.supportsMeetingConversation {
            let sharedContent = recordingManager.loadSharedMeetingNotesContent(for: transcription.meeting)
            if hasPersistedMeetingNotesContent(sharedContent) {
                return sharedContent
            }
        }

        let fallbackLegacyContent = MeetingNotesContent(
            plainText: transcription.contextItems.first(where: { $0.source == .meetingNotes })?.text ?? "",
            richTextRTFData: meetingNotesRichTextStore.transcriptionNotesRTFData(for: transcription.id)
        )
        return meetingNotesMarkdownStore.loadTranscriptionNotesContent(
            for: transcription.id,
            legacyContent: fallbackLegacyContent
        )
    }

    func updateMeetingNotes(_ content: MeetingNotesContent, in transcriptionID: UUID) async {
        do {
            guard var transcription = selectedTranscription, transcription.id == transcriptionID else {
                guard var loaded = try await storage.loadTranscription(by: transcriptionID) else { return }
                try await updateMeetingNotes(in: &loaded, content: content, selectedID: transcriptionID)
                return
            }

            try await updateMeetingNotes(in: &transcription, content: content, selectedID: transcriptionID)
        } catch {
            logger.error("Failed to update meeting notes: \(error.localizedDescription)")
            operationErrorMessage = "transcription.meeting_notes.error".localized
        }
    }

    func updateMeetingNotes(_ notes: String, in transcriptionID: UUID) async {
        await updateMeetingNotes(MeetingNotesContent(plainText: notes), in: transcriptionID)
    }

    func confirmDeleteTranscription(_ metadata: TranscriptionMetadata) {
        pendingDeleteTranscription = metadata
        showDeleteConfirmation = true
    }

    func cancelDeleteTranscription() {
        pendingDeleteTranscription = nil
        showDeleteConfirmation = false
    }

    func executeDeleteTranscription() async {
        guard let metadata = pendingDeleteTranscription else { return }
        await doDeleteTranscription(metadata)
        cancelDeleteTranscription()
    }

    private func doDeleteTranscription(_ metadata: TranscriptionMetadata) async {
        do {
            try await storage.deleteTranscription(by: metadata.id)
            meetingNotesRichTextStore.saveTranscriptionNotesRTFData(nil, for: metadata.id)
            meetingNotesMarkdownStore.deleteTranscriptionNotesContent(for: metadata.id)
            if selectedId == metadata.id {
                selectedId = nil
            }
            await loadTranscriptions()
        } catch {
            logger.error("Failed to delete transcription: \(error.localizedDescription)")
            operationErrorMessage = error.localizedDescription
        }
    }

    private func renameSpeaker(
        in transcription: inout Transcription,
        from oldValue: String,
        to newValue: String,
        selectedID: UUID
    ) async throws {
        let renamedSegments = transcription.segments.map { segment in
            guard segment.speaker == oldValue else { return segment }
            return Transcription.Segment(
                id: segment.id,
                speaker: newValue,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime
            )
        }

        guard renamedSegments != transcription.segments else { return }
        let sortedRenamedSegments = sortedSegments(renamedSegments)
        let updatedTranscription = Transcription(
            id: transcription.id,
            meeting: transcription.meeting,
            contextItems: transcription.contextItems,
            segments: sortedRenamedSegments,
            text: transcription.text,
            rawText: transcription.rawText,
            processedContent: transcription.processedContent,
            canonicalSummary: transcription.canonicalSummary,
            qualityProfile: transcription.qualityProfile,
            postProcessingPromptId: transcription.postProcessingPromptId,
            postProcessingPromptTitle: transcription.postProcessingPromptTitle,
            language: transcription.language,
            createdAt: transcription.createdAt,
            modelName: transcription.modelName,
            inputSource: transcription.inputSource,
            transcriptionDuration: transcription.transcriptionDuration,
            postProcessingDuration: transcription.postProcessingDuration,
            postProcessingModel: transcription.postProcessingModel,
            meetingType: transcription.meetingType,
            meetingConversationState: transcription.meetingConversationState
        )

        try await storage.saveTranscription(updatedTranscription)
        if selectedId == selectedID || selectedTranscription?.id == selectedID {
            selectedTranscription = updatedTranscription
        }
    }

    private func updateMeetingNotes(
        in transcription: inout Transcription,
        content: MeetingNotesContent,
        selectedID: UUID
    ) async throws {
        let notes = content.plainText
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextWithoutMeetingNotes = transcription.contextItems.filter { $0.source != .meetingNotes }
        let updatedContextItems = if trimmedNotes.isEmpty {
            contextWithoutMeetingNotes
        } else {
            contextWithoutMeetingNotes + [TranscriptionContextItem(source: .meetingNotes, text: notes)]
        }
        let currentTranscriptionRichTextData = meetingNotesRichTextStore.transcriptionNotesRTFData(for: transcription.id)
        let isSameTranscriptionRichText = currentTranscriptionRichTextData == content.richTextRTFData
        let isSameSharedContent = if transcription.supportsMeetingConversation {
            recordingManager.loadSharedMeetingNotesContent(for: transcription.meeting) == content
        } else {
            true
        }

        guard updatedContextItems != transcription.contextItems
            || !isSameTranscriptionRichText
            || !isSameSharedContent
        else { return }

        if updatedContextItems == transcription.contextItems {
            persistMeetingNotesSideEffects(content, trimmedNotes: trimmedNotes, for: transcription)
            return
        }

        let updatedTranscription = Transcription(
            id: transcription.id,
            meeting: transcription.meeting,
            contextItems: updatedContextItems,
            segments: transcription.segments,
            text: transcription.text,
            rawText: transcription.rawText,
            processedContent: transcription.processedContent,
            canonicalSummary: transcription.canonicalSummary,
            qualityProfile: transcription.qualityProfile,
            postProcessingPromptId: transcription.postProcessingPromptId,
            postProcessingPromptTitle: transcription.postProcessingPromptTitle,
            language: transcription.language,
            createdAt: transcription.createdAt,
            modelName: transcription.modelName,
            inputSource: transcription.inputSource,
            transcriptionDuration: transcription.transcriptionDuration,
            postProcessingDuration: transcription.postProcessingDuration,
            postProcessingModel: transcription.postProcessingModel,
            meetingType: transcription.meetingType,
            meetingConversationState: transcription.meetingConversationState
        )

        try await storage.saveTranscription(updatedTranscription)
        persistMeetingNotesSideEffects(content, trimmedNotes: trimmedNotes, for: transcription)

        if selectedId == selectedID || selectedTranscription?.id == selectedID {
            selectedTranscription = updatedTranscription
        }
    }

    private func persistMeetingNotesSideEffects(
        _ content: MeetingNotesContent,
        trimmedNotes: String,
        for transcription: Transcription
    ) {
        if transcription.supportsMeetingConversation {
            recordingManager.saveSharedMeetingNotesContent(content, for: transcription.meeting)
        }

        if trimmedNotes.isEmpty {
            meetingNotesRichTextStore.saveTranscriptionNotesRTFData(nil, for: transcription.id)
            meetingNotesMarkdownStore.deleteTranscriptionNotesContent(for: transcription.id)
        } else {
            meetingNotesRichTextStore.saveTranscriptionNotesRTFData(content.richTextRTFData, for: transcription.id)
            meetingNotesMarkdownStore.saveTranscriptionNotesContent(content, for: transcription.id)
        }
    }

    private func hasPersistedMeetingNotesContent(_ content: MeetingNotesContent) -> Bool {
        !content.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (content.richTextRTFData?.isEmpty == false)
    }
}
