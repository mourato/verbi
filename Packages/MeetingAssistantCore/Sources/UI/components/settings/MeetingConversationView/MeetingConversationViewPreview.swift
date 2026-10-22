import MeetingAssistantCoreAI
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

#Preview("Meeting conversation") {
    MeetingConversationView(
        transcription: .previewConversation,
        isLoadingTranscription: false,
        turns: [
            .init(
                question: "What did we decide about previews?",
                response: MeetingQAResponse(
                    status: .answered,
                    answer: "The team decided to prioritize pages with real side effects, then clean up by component group.",
                    evidence: [
                        .init(
                            speaker: "Speaker 2",
                            startTime: 10,
                            endTime: 21,
                            excerpt: "Vamos priorizar telas com side effects primeiro."
                        )
                    ]
                ),
                errorMessage: nil
            )
        ],
        questionText: "How should I finish this reorg?",
        meetingNotesContent: MeetingNotesContent(
            plainText: "Owner: Speaker 2\n- Prioritize screens with side effects"
        ),
        onQuestionChange: { _ in },
        onAsk: {},
        onRetry: { _, _ in },
        isAnswering: false,
        currentErrorMessage: nil,
        effectiveModelSelection: MeetingQAModelSelection(
            providerRawValue: LLMProvider.openai.rawValue,
            modelID: "gpt-4o"
        ),
        modelOptions: [
            .init(provider: .openai, modelID: "gpt-4o"),
            .init(provider: .openai, modelID: "gpt-4.1-mini"),
            .init(provider: .anthropic, modelID: "claude-3-5-sonnet")
        ],
        isLoadingModelOptions: false,
        onModelChange: { _ in },
        onRefreshModelOptions: {},
        dictationState: .idle,
        dictationErrorMessage: nil,
        onToggleDictation: {},
        onRenameSpeaker: { _, _, _ in },
        onUpdateMeetingNotes: { _, _ in }
    )
    .frame(width: 760, height: 680)
    .padding()
}

private extension CaptureArtifact {
    static var previewConversation: CaptureArtifact {
        CaptureArtifact(
            meeting: CaptureSession(
                app: .slack,
                state: .completed,
                startTime: Date().addingTimeInterval(-1800),
                endTime: Date().addingTimeInterval(-600),
                audioFilePath: nil
            ),
            segments: [
                .init(speaker: "Speaker 1", text: "Precisamos consolidar os previews da interface.", startTime: 0, endTime: 9),
                .init(speaker: "Speaker 2", text: "Vou priorizar as telas com side effects na fase seguinte.", startTime: 10, endTime: 21)
            ],
            text: "Precisamos consolidar os previews da interface. Vou priorizar as telas com side effects na fase seguinte.",
            rawText: "precisamos consolidar previews interface vou priorizar telas com side effects na fase seguinte",
            processedContent: "Precisamos consolidar os previews da interface e priorizar, na sequência, as telas com side effects.",
            postProcessingPromptTitle: "Planning summary",
            language: "pt"
        )
    }
}
