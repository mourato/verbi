import SwiftUI
import VerbiCoreCommon
import VerbiCoreDomain

extension MeetingConversationView {
    var summaryContent: some View {
        MeetingSummaryView(
            canonicalSummary: transcription?.canonicalSummary,
            fallbackText: summaryText,
            showsFallbackBadge: transcription?.postProcessingOutputState == .deterministicFallback
        )
    }

    var summaryText: String {
        guard let transcription else {
            return "transcription.empty_fallback".localized
        }

        return TranscriptionDisplayText.preferredSummary(
            processedContent: transcription.processedContent,
            canonicalSummary: transcription.canonicalSummary,
            text: transcription.text,
            emptyFallback: "transcription.empty_fallback".localized
        )
    }

    var chatContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryContent

                if let currentErrorMessage {
                    let trimmedError = currentErrorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedError.isEmpty {
                        Text(trimmedError)
                            .font(.caption)
                            .foregroundStyle(AppDesignSystem.Colors.error)
                            .textSelection(.enabled)
                    }
                }

                if turns.isEmpty {
                    Text("transcription.qa.placeholder".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(turns) { turn in
                        turnView(turn)
                    }
                }

                if isAnswering {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("transcription.qa.loading".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
        }
    }
}
