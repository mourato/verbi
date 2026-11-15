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

    var summaryTabContent: some View {
        ScrollView {
            summaryContent
                .padding(16)
        }
    }

    var askContent: some View {
        VStack(spacing: 0) {
            if turns.isEmpty, !isAnswering, trimmedCurrentErrorMessage == nil {
                VStack {
                    Spacer(minLength: 0)
                    Text("transcription.qa.empty_hint".localized)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    Spacer(minLength: 0)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let trimmedError = trimmedCurrentErrorMessage {
                            Text(trimmedError)
                                .font(.caption)
                                .foregroundStyle(AppDesignSystem.Colors.error)
                                .textSelection(.enabled)
                        }

                        ForEach(turns) { turn in
                            turnView(turn)
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

            Divider()
            composer
        }
    }

    private var trimmedCurrentErrorMessage: String? {
        guard let currentErrorMessage else { return nil }
        let trimmedError = currentErrorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedError.isEmpty ? nil : trimmedError
    }
}
