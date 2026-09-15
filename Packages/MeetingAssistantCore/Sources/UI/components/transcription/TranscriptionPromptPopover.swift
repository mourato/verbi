import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

struct TranscriptionPromptPopover: View {
    let transcription: Transcription

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("transcription.prompt.title".localized)
                .font(.headline)
                .padding(.bottom, 4)

            let promptInput = constructPromptInput()
            let diagnosticsLines = postProcessingDiagnosticsLines()

            ScrollView {
                Text(promptInput)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Increased area

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("transcription.prompt.section.post_processing_diagnostics".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(diagnosticsLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .frame(width: 500, height: 600) // Increased popover size
    }

    private func constructPromptInput() -> String {
        let requestSystemPrompt = nonEmptyTrimmed(transcription.postProcessingRequestSystemPrompt)
        let requestUserPrompt = nonEmptyTrimmed(transcription.postProcessingRequestUserPrompt)

        return [
            "transcription.prompt.section.system_prompt".localized,
            requestSystemPrompt ?? "transcription.prompt.not_available".localized,
            "",
            "transcription.prompt.section.user_message".localized,
            requestUserPrompt ?? "transcription.prompt.not_available".localized
        ].joined(separator: "\n")
    }

    private func nonEmptyTrimmed(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func postProcessingDiagnosticsLines() -> [String] {
        let settings = AppSettingsStore.shared
        let hasProcessedContent = transcription.processedContent?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        let processingStatus = hasProcessedContent
            ? "transcription.prompt.value.applied".localized
            : "transcription.prompt.value.skipped".localized
        let globalStatus = settings.postProcessingEnabled
            ? "transcription.prompt.value.enabled".localized
            : "transcription.prompt.value.disabled".localized

        return [
            "\("transcription.prompt.global_post_processing_enabled".localized): \(globalStatus)",
            "\("transcription.prompt.dictation_selected_prompt_id".localized): \(settings.dictationSelectedPromptId?.uuidString ?? "transcription.prompt.unset".localized)",
            "\("transcription.prompt.meeting_selected_prompt_id".localized): \(settings.selectedPromptId?.uuidString ?? "transcription.prompt.unset".localized)",
            "\("transcription.prompt.used_prompt_id".localized): \(transcription.postProcessingPromptId?.uuidString ?? "transcription.prompt.unset".localized)",
            "\("transcription.prompt.used_prompt_title".localized): \(transcription.postProcessingPromptTitle ?? "transcription.prompt.unset".localized)",
            "\("transcription.prompt.post_processing_applied".localized): \(processingStatus)",
            "\("transcription.prompt.post_processing_model".localized): \(transcription.postProcessingModel ?? "transcription.prompt.unset".localized)",
            "\("transcription.prompt.post_processing_duration".localized): \(String(format: "%.2fs", transcription.postProcessingDuration))"
        ]
    }
}

#Preview {
    TranscriptionPromptPopover(
        transcription: Transcription(
            meeting: Meeting(app: .zoom),
            text: "Preview text",
            rawText: "Raw text",
            postProcessingRequestSystemPrompt: "You are a helpful assistant specialized in processing transcriptions.",
            postProcessingRequestUserPrompt: """
            <TRANSCRIPTION>
            Hello everyone, today we will discuss the quarterly results.
            </TRANSCRIPTION>

            <INSTRUCTIONS>
            Process this transcription and create a summary.
            </INSTRUCTIONS>
            """,
            modelName: "Whisper-v3"
        )
    )
}
