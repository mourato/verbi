import SwiftUI
import VerbiCoreCommon
import VerbiCoreDomain

/// Footer text rules for the meeting detail page.
///
/// The footer always names local storage. The model suffix appears only when
/// the post-processing model is known, and the AI disclaimer appears only for
/// generated summaries that are not the deterministic fallback.
struct MeetingFooterState {
    /// The model name to show, or nil when unknown or blank.
    let modelName: String?
    /// Whether to append the "AI can make mistakes" suffix.
    let showsAIDisclaimer: Bool

    init(postProcessingModel: String?, hasGeneratedSummary: Bool, isFallback: Bool) {
        let trimmedModel = postProcessingModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        modelName = trimmedModel?.isEmpty == false ? trimmedModel : nil
        showsAIDisclaimer = hasGeneratedSummary && !isFallback
    }
}

extension MeetingConversationView {
    /// Page footer: local-storage note plus an Ask shortcut button.
    ///
    /// Shown on every tab except Ask (whose composer pins its own bar).
    /// The shortcut only exists in this hierarchy, so ⌘J fires on this page alone.
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
            isFallback: transcription?.postProcessingOutputState == .deterministicFallback
        )
    }
}
