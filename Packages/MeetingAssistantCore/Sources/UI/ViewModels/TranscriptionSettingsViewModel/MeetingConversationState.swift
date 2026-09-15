import Foundation
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

@MainActor
extension TranscriptionSettingsViewModel {
    public func updateMeetingQAModelSelection(
        provider: AIProvider,
        model: String,
        for transcriptionID: UUID
    ) async {
        let normalizedModel = settings.normalizedEnhancementsModelID(model, for: provider)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedModel.isEmpty else {
            qaModelSelectionByTranscription.removeValue(forKey: transcriptionID)
            await persistMeetingConversationState(for: transcriptionID)
            return
        }

        qaModelSelectionByTranscription[transcriptionID] = MeetingQAModelSelection(
            providerRawValue: provider.rawValue,
            modelID: normalizedModel
        )
        await persistMeetingConversationState(for: transcriptionID)
    }

    func restoreMeetingConversationState(from transcription: Transcription) {
        let state = transcription.meetingConversationState
        let turns = (state?.turns ?? []).map {
            QATurn(
                id: $0.id,
                question: $0.question,
                response: $0.response,
                errorMessage: $0.errorMessage,
                createdAt: $0.createdAt
            )
        }

        qaHistoryByTranscription[transcription.id] = turns
        if let modelSelection = state?.modelSelection {
            qaModelSelectionByTranscription[transcription.id] = modelSelection
        } else {
            qaModelSelectionByTranscription.removeValue(forKey: transcription.id)
        }
    }

    func persistMeetingConversationState(for transcriptionID: UUID) async {
        guard var selected = selectedTranscription, selected.id == transcriptionID else { return }

        let turns = (qaHistoryByTranscription[transcriptionID] ?? []).map {
            MeetingConversationTurn(
                id: $0.id,
                question: $0.question,
                response: $0.response,
                errorMessage: $0.errorMessage,
                createdAt: $0.createdAt
            )
        }
        let modelSelection = qaModelSelectionByTranscription[transcriptionID]
        let state: MeetingConversationState? = if turns.isEmpty, modelSelection == nil {
            nil
        } else {
            MeetingConversationState(turns: turns, modelSelection: modelSelection)
        }

        selected.meetingConversationState = state

        do {
            try await storage.saveTranscription(selected)
            selectedTranscription = selected
        } catch {
            logger.error("Failed to persist meeting conversation state: \(error.localizedDescription)")
        }
    }
}
