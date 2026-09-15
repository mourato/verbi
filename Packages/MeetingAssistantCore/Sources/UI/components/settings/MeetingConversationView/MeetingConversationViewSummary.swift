import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import SwiftUI

extension MeetingConversationView {
    var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("transcription.qa.summary_title".localized)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer(minLength: 8)
                summaryFallbackBadge
            }

            Text(summaryText)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(
            AppDesignSystem.Colors.settingsCardBackground,
            in: RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
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

    @ViewBuilder
    var summaryFallbackBadge: some View {
        if transcription?.postProcessingOutputState == .deterministicFallback {
            Text("transcription.summary.fallback_badge".localized)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    AppDesignSystem.Colors.settingsCardBackground.opacity(0.8),
                    in: Capsule()
                )
        }
    }

    var chatContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard

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
