import SwiftUI
import VerbiCoreCommon

/// Short transcription preview with optional expansion for the current tab.
struct TranscriptionCardContentView: View {
    let text: String
    let selectedTab: TranscriptionCardView.TranscriptionTab
    let lineLimit: Int
    let isPostProcessing: Bool
    @Binding var expandedTabs: Set<TranscriptionCardView.TranscriptionTab>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            markdownText(text)
                .lineLimit(isTabExpanded ? nil : lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(textOpacity)
                .animation(pulseAnimation, value: isPostProcessing)

            if shouldShowExpansionToggle {
                Button(isTabExpanded ? "transcription.content.show_less".localized : "transcription.content.show_all".localized) {
                    toggleTabExpansion()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(AppDesignSystem.Colors.accent)
            }
        }
    }

    private var isTabExpanded: Bool {
        expandedTabs.contains(selectedTab)
    }

    private var shouldShowExpansionToggle: Bool {
        let lineBreakCount = text.reduce(into: 0) { partialResult, character in
            if character == "\n" {
                partialResult += 1
            }
        }
        let estimatedLines = lineBreakCount + max(1, text.count / 110)
        return estimatedLines > lineLimit
    }

    private var textOpacity: Double {
        if isPostProcessing, !reduceMotion {
            return 0.45
        }
        return 1
    }

    private var pulseAnimation: Animation? {
        if isPostProcessing, !reduceMotion {
            return .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        }
        return nil
    }

    private func toggleTabExpansion() {
        if isTabExpanded {
            expandedTabs.remove(selectedTab)
        } else {
            expandedTabs.insert(selectedTab)
        }
    }

    private func markdownText(_ text: String) -> Text {
        Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
    }
}

func transcriptionCardDisplayText(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return "transcription.empty_fallback".localized
    }
    return text
}
