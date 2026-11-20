import SwiftUI
import VerbiCoreCommon
import VerbiCoreDomain

struct MeetingFooterState {
    let modelName: String?
    let showsAIDisclaimer: Bool

    init(postProcessingModel: String?, hasGeneratedSummary: Bool, isFallback: Bool) {
        let trimmedModel = postProcessingModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        modelName = trimmedModel?.isEmpty == false ? trimmedModel : nil
        showsAIDisclaimer = hasGeneratedSummary && !isFallback
    }
}

extension MeetingConversationView {
    var isDeterministicFallback: Bool {
        transcription?.postProcessingOutputState == .deterministicFallback
    }

    struct MeetingFooter: View {
        let leadingText: String
        let onAsk: () -> Void

        var body: some View {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Label(leadingText, systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: AppDesignSystem.Layout.spacing8)
                    Button(
                        "transcription.qa.tab.ask".localized,
                        systemImage: "bubble.left.and.bubble.right"
                    ) {
                        onAsk()
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut("j", modifiers: .command)
                }
                .padding(.horizontal, AppDesignSystem.Layout.spacing16)
                .padding(.vertical, AppDesignSystem.Layout.spacing12)
            }
        }
    }
}

extension MeetingConversationView {
    @ViewBuilder
    func footer(onAsk: @escaping () -> Void) -> some View {
        if transcription != nil {
            MeetingFooter(
                leadingText: footerLeadingText,
                onAsk: onAsk
            )
        }
    }

    private var footerLeadingText: String {
        var text = "meeting.detail.footer.saved".localized
        let state = footerState
        if let modelName = state.modelName {
            text += " · \(modelName)"
        }
        if state.showsAIDisclaimer {
            text += " · \("meeting.detail.footer.ai_disclaimer".localized)"
        }
        return text
    }

    private var footerState: MeetingFooterState {
        let processedSummary = transcription?.processedContent?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let hasGeneratedSummary =
            transcription?.canonicalSummary != nil || !(processedSummary?.isEmpty ?? true)
        return MeetingFooterState(
            postProcessingModel: transcription?.postProcessingModel,
            hasGeneratedSummary: hasGeneratedSummary,
            isFallback: isDeterministicFallback
        )
    }
}

#Preview("Meeting footer") {
    MeetingConversationView.MeetingFooter(
        leadingText: "Saved on this Mac · Gemini Flash Lite · AI can make mistakes",
        onAsk: {}
    )
    .frame(width: 560)
    .padding()
}

#Preview("Meeting footer narrow") {
    MeetingConversationView.MeetingFooter(
        leadingText: "Saved on this Mac · Gemini Flash Lite · AI can make mistakes",
        onAsk: {}
    )
    .frame(width: 220)
    .padding()
}
