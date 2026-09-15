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
    func submitQuestion(for transcription: Transcription) async {
        let trimmedQuestion = qaQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            qaErrorMessage = "transcription.qa.error.empty_question".localized
            return
        }

        await askQuestion(trimmedQuestion, for: transcription)
    }

    func retryQuestion(_ question: String, turnID: UUID, for transcription: Transcription) async {
        await retryQuestion(question, turnID: Optional(turnID), for: transcription)
    }

    private func retryQuestion(_ question: String, turnID: UUID?, for transcription: Transcription) async {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            qaErrorMessage = "transcription.qa.error.empty_question".localized
            return
        }

        qaQuestion = trimmedQuestion
        await askQuestion(trimmedQuestion, for: transcription, retryTurnID: turnID)
    }

    private func askQuestion(
        _ question: String,
        for transcription: Transcription,
        retryTurnID: UUID? = nil
    ) async {
        guard transcription.supportsMeetingConversation else {
            qaErrorMessage = localizedQuestionError(for: .disabled, transcriptionID: transcription.id)
            return
        }

        guard !isAnsweringQuestion else { return }

        isAnsweringQuestion = true
        qaErrorMessage = nil
        defer { isAnsweringQuestion = false }

        do {
            let request = IntelligenceKernelQuestionRequest(
                mode: .meeting,
                question: question,
                transcription: transcription,
                modelSelectionOverride: qaModelSelectionByTranscription[transcription.id]
            )
            let response = try await meetingQAService.ask(request)
            qaResponse = response
            upsertQATurn(
                QATurn(
                    id: retryTurnID ?? UUID(),
                    question: question,
                    response: response,
                    errorMessage: nil,
                    createdAt: turnCreationDate(for: retryTurnID, transcriptionID: transcription.id)
                ),
                transcriptionID: transcription.id,
                replacingTurnID: retryTurnID
            )
            await persistMeetingConversationState(for: transcription.id)
        } catch {
            let message = (error as? MeetingQAError).map {
                localizedQuestionError(for: $0, transcriptionID: transcription.id)
            } ?? "transcription.qa.error.generic".localized
            qaErrorMessage = message
            upsertQATurn(
                QATurn(
                    id: retryTurnID ?? UUID(),
                    question: question,
                    response: nil,
                    errorMessage: message,
                    createdAt: turnCreationDate(for: retryTurnID, transcriptionID: transcription.id)
                ),
                transcriptionID: transcription.id,
                replacingTurnID: retryTurnID
            )
            await persistMeetingConversationState(for: transcription.id)
        }
    }

    private func localizedQuestionError(for error: MeetingQAError, transcriptionID: UUID? = nil) -> String {
        switch error {
        case .disabled:
            "transcription.qa.error.disabled".localized
        case .emptyQuestion:
            "transcription.qa.error.empty_question".localized
        case .noAPIConfigured:
            "transcription.qa.error.no_api".localized
        case .invalidURL:
            "transcription.qa.error.invalid_url".localized
        case .timeout:
            "transcription.qa.error.timeout".localized
        case .networkUnavailable:
            "transcription.qa.error.network".localized
        case .invalidResponse:
            invalidResponseQuestionError(transcriptionID: transcriptionID)
        case .requestFailed:
            "transcription.qa.error.generic".localized
        }
    }

    func resetQuestionState() {
        qaQuestion = ""
        qaResponse = nil
        qaErrorMessage = nil
    }

    func clearQuestionComposer() {
        qaQuestion = ""
        qaErrorMessage = nil
    }

    private func upsertQATurn(
        _ turn: QATurn,
        transcriptionID: UUID,
        replacingTurnID: UUID?
    ) {
        var turns = qaHistoryByTranscription[transcriptionID] ?? []
        if let replacingTurnID,
           let existingIndex = turns.firstIndex(where: { $0.id == replacingTurnID })
        {
            turns[existingIndex] = turn
        } else {
            turns.append(turn)
        }
        qaHistoryByTranscription[transcriptionID] = turns
    }

    private func turnCreationDate(for turnID: UUID?, transcriptionID: UUID) -> Date {
        guard let turnID,
              let existingTurn = qaHistoryByTranscription[transcriptionID]?.first(where: { $0.id == turnID })
        else {
            return Date()
        }
        return existingTurn.createdAt
    }

    private func invalidResponseQuestionError(transcriptionID: UUID?) -> String {
        guard let transcriptionID else {
            return "transcription.qa.error.invalid_response".localized
        }

        let selection = effectiveMeetingQAModelSelection(for: transcriptionID)
        let providerName = AIProvider(rawValue: selection.providerRawValue)?.displayName ?? selection.providerRawValue
        let modelName = selection.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModelName = modelName.isEmpty
            ? "transcription.qa.error.invalid_response.unknown_model".localized
            : modelName

        return "transcription.qa.error.invalid_response.detailed".localized(with: providerName, resolvedModelName)
    }
}
