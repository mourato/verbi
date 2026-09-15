import MeetingAssistantCoreCommon
import SwiftUI

public struct ShortcutCaptureHealthStatusView: View {
    private let presentation: ShortcutCaptureHealthPresentation
    private let onAction: () -> Void

    public init(
        presentation: ShortcutCaptureHealthPresentation,
        onAction: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.onAction = onAction
    }

    public var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(presentation.scopeLabelKey.localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    DSBadge(
                        presentation.badgeKey.localized,
                        kind: presentation.isFallback ? .error : .warning
                    )
                }

                HStack(spacing: 8) {
                    Image(systemName: presentation.isFallback ? "arrow.trianglehead.branch" : "exclamationmark.triangle.fill")
                        .foregroundStyle(
                            presentation.isFallback
                                ? AppDesignSystem.Colors.error
                                : AppDesignSystem.Colors.warning
                        )
                    Text(presentation.titleKey.localized)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Text(presentation.messageKey.localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitleKey = presentation.actionTitleKey,
                   presentation.action != .none
                {
                    Button(actionTitleKey.localized) {
                        onAction()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityHint("settings.shortcuts.health.accessibility.hint.actionable".localized)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [
                presentation.scopeLabelKey.localized,
                presentation.badgeKey.localized,
                presentation.titleKey.localized,
                presentation.messageKey.localized
            ]
            .joined(separator: ", ")
        )
        .accessibilityHint(
            presentation.action == .none
                ? "settings.shortcuts.health.accessibility.hint.read_only".localized
                : "settings.shortcuts.health.accessibility.hint.actionable".localized
        )
    }
}

#Preview("Shortcut health warning") {
    let status = ShortcutCaptureHealthStatus(
        scope: .global,
        result: .degraded,
        reasonToken: "preview",
        requiresGlobalCapture: true,
        accessibilityTrusted: false,
        eventTapExpected: false,
        eventTapActive: false
    )

    if let presentation = ShortcutCaptureHealthPresentation.from(status: status) {
        ShortcutCaptureHealthStatusView(
            presentation: presentation,
            onAction: {}
        )
        .frame(width: 360)
        .padding()
    }
}
