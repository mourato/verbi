import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

/// Compact history-row presentation used for scanning and direct navigation.
struct TranscriptionCardCollapsedRow: View {
    let transcription: TranscriptionMetadata
    let title: String
    let previewText: String
    let failureMessage: String?
    let supportsMeetingConversation: Bool
    let accessibilityHint: String
    let onPrimaryAction: () -> Void
    let onToggleExpand: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onPrimaryAction) {
                collapsedContent
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(collapsedAccessibilityValue)
            .accessibilityHint(accessibilityHint)
            .accessibilityAddTraits(.isButton)

            if supportsMeetingConversation {
                Button(action: onToggleExpand) {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("transcription.content.show_all".localized)
                .accessibilityValue("common.collapsed".localized)
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    private var collapsedContent: some View {
        HStack(alignment: .top, spacing: 12) {
            AppIconView(
                bundleIdentifier: transcription.appBundleIdentifier,
                fallbackSystemName: appSource.icon,
                size: 32,
                cornerRadius: 7
            )
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                markdownText(previewText)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let failureMessage {
                    TranscriptionCardFailureLabel(message: failureMessage)
                }
            }

            if !supportsMeetingConversation {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var collapsedAccessibilityValue: String {
        let preview = String(markdownAttributedString(previewText).characters)
        return "\("common.collapsed".localized). \(preview)"
    }

    private var appSource: MeetingApp {
        MeetingApp(rawValue: transcription.appRawValue) ?? .unknown
    }

    private func markdownText(_ text: String) -> Text {
        Text(markdownAttributedString(text))
    }

    private func markdownAttributedString(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

struct TranscriptionCardFailureLabel: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppDesignSystem.Colors.error)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppDesignSystem.Colors.error)
                .multilineTextAlignment(.leading)
        }
    }
}
