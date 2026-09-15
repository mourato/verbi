import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

struct TranscriptionConversationPage: View {
    let transcriptionID: UUID
    let activeTranscription: Transcription?
    @ObservedObject var viewModel: TranscriptionSettingsViewModel
    @ObservedObject var dictationService: MeetingQuestionDictationService
    let onToggleDictation: () -> Void
    let onBack: (() -> Void)?

    @StateObject private var aiSettingsViewModel: AISettingsViewModel

    init(
        transcriptionID: UUID,
        activeTranscription: Transcription?,
        viewModel: TranscriptionSettingsViewModel,
        dictationService: MeetingQuestionDictationService,
        settings: AppSettingsStore = .shared,
        onToggleDictation: @escaping () -> Void,
        onBack: (() -> Void)? = nil
    ) {
        self.transcriptionID = transcriptionID
        self.activeTranscription = activeTranscription
        self.viewModel = viewModel
        self.dictationService = dictationService
        self.onToggleDictation = onToggleDictation
        self.onBack = onBack
        _aiSettingsViewModel = StateObject(
            wrappedValue: AISettingsViewModel(
                settings: settings,
                credentialBootstrapPolicy: .deferredUserAction
            )
        )
    }

    var body: some View {
        let effectiveSelection = viewModel.effectiveMeetingQAModelSelection(for: transcriptionID)
        let meetingNotesContent = viewModel.meetingNotesContent(for: activeTranscription)

        VStack(spacing: 0) {
            if let onBack {
                HStack {
                    SettingsChildPageBackButton(titleKey: "common.back", action: onBack)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            SettingsSectionHeader(
                title: "settings.section.history".localized,
                description: activeTranscription?.meeting.appName
            )
            .padding(16)

            Divider()

            MeetingConversationView(
                transcription: activeTranscription,
                isLoadingTranscription: activeTranscription == nil,
                turns: viewModel.qaHistory(for: transcriptionID),
                questionText: viewModel.qaQuestion,
                meetingNotesContent: meetingNotesContent,
                onQuestionChange: { newValue in
                    dictationService.clearError()
                    viewModel.qaQuestion = newValue
                },
                onAsk: {
                    guard let transcription = viewModel.selectedTranscription, transcription.id == transcriptionID else { return }
                    Task {
                        await viewModel.submitQuestion(for: transcription)
                    }
                },
                onRetry: { turnID, question in
                    guard let transcription = viewModel.selectedTranscription, transcription.id == transcriptionID else { return }
                    Task {
                        await viewModel.retryQuestion(question, turnID: turnID, for: transcription)
                    }
                },
                isAnswering: viewModel.isAnsweringQuestion,
                currentErrorMessage: viewModel.qaErrorMessage,
                effectiveModelSelection: effectiveSelection,
                modelOptions: aiSettingsViewModel.enhancementsProviderModels,
                isLoadingModelOptions: aiSettingsViewModel.isLoadingEnhancementsProviderModels,
                onModelChange: { option in
                    Task {
                        await viewModel.updateMeetingQAModelSelection(
                            provider: option.provider,
                            model: option.modelID,
                            for: transcriptionID
                        )
                    }
                },
                onRefreshModelOptions: {
                    aiSettingsViewModel.refreshEnhancementsProviderModelsManually()
                },
                dictationState: dictationService.state,
                dictationErrorMessage: dictationService.errorMessage,
                onToggleDictation: onToggleDictation,
                onRenameSpeaker: { original, updated, id in
                    Task {
                        await viewModel.renameSpeaker(from: original, to: updated, in: id)
                    }
                },
                onUpdateMeetingNotes: { content, id in
                    Task {
                        await viewModel.updateMeetingNotes(content, in: id)
                    }
                }
            )
        }
        .task {
            aiSettingsViewModel.refreshEnhancementsProviderModelsManually()
        }
    }
}

#Preview("Transcription conversation page") {
    let transcriptionID = UUID()
    let activeTranscription = Transcription(
        id: transcriptionID,
        meeting: Meeting(
            app: .slack,
            state: .completed,
            startTime: Date().addingTimeInterval(-1800),
            endTime: Date().addingTimeInterval(-600),
            audioFilePath: nil
        ),
        segments: [
            .init(speaker: "Speaker 1", text: "Precisamos priorizar as mudanças de UI.", startTime: 0, endTime: 6),
            .init(speaker: "Speaker 2", text: "Conforme discutido, vou ajustar a navegação da tela de transcrição.", startTime: 8, endTime: 16)
        ],
        text: "Precisamos priorizar as mudanças de UI. Conforme discutido, vou ajustar a navegação da tela de transcrição.",
        rawText: "Precisamos priorizar as mudanças de UI conforme discutido ajustar a navegacao da tela de transcricao",
        processedContent: "Precisamos priorizar as mudanças de UI e ajustar a navegação da tela de transcrição.",
        language: "pt"
    )

    TranscriptionConversationPage(
        transcriptionID: transcriptionID,
        activeTranscription: activeTranscription,
        viewModel: TranscriptionSettingsViewModel(),
        dictationService: MeetingQuestionDictationService(),
        onToggleDictation: {}
    )
    .frame(width: 780, height: 780)
}
