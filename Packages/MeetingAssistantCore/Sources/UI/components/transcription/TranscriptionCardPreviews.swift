import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

private struct TranscriptionCardPreviewContainer: View {
    @State private var isExpanded = true

    var body: some View {
        TranscriptionCardView(
            transcription: .previewMetadata,
            transcriptionDetail: .previewDetail,
            isExpanded: isExpanded,
            audioURL: nil,
            availablePrompts: PostProcessingPrompt.allPredefined,
            availableRetryTranscriptionOptions: [
                RetryTranscriptionOption(
                    selection: TranscriptionProviderSelection(
                        provider: .local,
                        selectedModel: LocalTranscriptionModel.parakeetTdt06BV3.rawValue
                    )
                )
            ],
            onToggleExpand: { isExpanded.toggle() },
            onAction: { _ in }
        )
        .padding()
        .frame(width: 760)
    }
}

private extension TranscriptionMetadata {
    static var previewMetadata: Self {
        .init(
            id: UUID(),
            meetingId: UUID(),
            meetingTitle: "Sprint Planning",
            appName: "Google Meet",
            appRawValue: "google-meet",
            appBundleIdentifier: "com.google.Chrome",
            startTime: Date().addingTimeInterval(-900),
            createdAt: Date(),
            previewText: "Resumo da sprint: concluímos os endpoints de transcrição, faltando validar tratamento de erros e UX da aba de settings.",
            wordCount: 24,
            language: "pt",
            isPostProcessed: true,
            duration: 540,
            audioFilePath: nil,
            inputSource: "microphone"
        )
    }
}

private extension Transcription {
    static var previewDetail: Self {
        .init(
            meeting: Meeting(
                app: .googleMeet,
                title: "Sprint Planning",
                state: .completed,
                startTime: Date().addingTimeInterval(-1200),
                endTime: Date().addingTimeInterval(-600),
                audioFilePath: nil
            ),
            segments: [
                .init(speaker: "Speaker 1", text: "Finalizamos o fluxo principal do processamento.", startTime: 0, endTime: 12),
                .init(speaker: "Speaker 2", text: "Próximo passo é revisar os previews dos componentes.", startTime: 13, endTime: 24)
            ],
            text: "Finalizamos o fluxo principal do processamento. Próximo passo é revisar os previews dos componentes.",
            rawText: "finalizamos fluxo principal processamento proximo passo revisar previews componentes",
            processedContent: "Finalizamos o fluxo principal do processamento. O próximo passo é revisar os previews dos componentes.",
            postProcessingPromptTitle: "Clean transcription",
            language: "pt"
        )
    }
}

#Preview("Expanded") {
    TranscriptionCardPreviewContainer()
}

#Preview("Collapsed") {
    TranscriptionCardView(
        transcription: .previewMetadata,
        transcriptionDetail: .previewDetail,
        isExpanded: false,
        audioURL: nil,
        availablePrompts: PostProcessingPrompt.allPredefined,
        availableRetryTranscriptionOptions: [
            RetryTranscriptionOption(
                selection: TranscriptionProviderSelection(
                    provider: .local,
                    selectedModel: LocalTranscriptionModel.parakeetTdt06BV3.rawValue
                )
            ),
            RetryTranscriptionOption(
                selection: TranscriptionProviderSelection(
                    provider: .groq,
                    selectedModel: TranscriptionProvider.groqPresetModelIDs[0]
                )
            )
        ],
        onToggleExpand: {},
        onAction: { _ in }
    )
    .padding()
    .frame(width: 760)
}
