import MeetingAssistantCoreCommon

public enum ShortcutCaptureHealthAction: Equatable {
    case none
    case openAccessibilitySettings
}

public struct ShortcutCaptureHealthPresentation: Equatable {
    public let scope: ShortcutCaptureHealthScope
    public let scopeLabelKey: String
    public let badgeKey: String
    public let titleKey: String
    public let messageKey: String
    public let actionTitleKey: String?
    public let action: ShortcutCaptureHealthAction
    public let isFallback: Bool

    public static func from(status: ShortcutCaptureHealthStatus) -> ShortcutCaptureHealthPresentation? {
        guard status.result == .degraded, status.requiresGlobalCapture else {
            return nil
        }

        let scopeLabelKey = switch status.scope {
        case .global:
            "settings.shortcuts.health.scope.global"
        case .assistant:
            "settings.shortcuts.health.scope.assistant"
        }

        let isFallback = status.scope == .assistant && status.eventTapExpected && !status.eventTapActive
        if isFallback {
            return ShortcutCaptureHealthPresentation(
                scope: status.scope,
                scopeLabelKey: scopeLabelKey,
                badgeKey: "settings.shortcuts.health.badge.fallback",
                titleKey: "settings.shortcuts.health.fallback.title",
                messageKey: "settings.shortcuts.health.fallback.message.generic",
                actionTitleKey: nil,
                action: .none,
                isFallback: true
            )
        }

        if !status.accessibilityTrusted {
            return ShortcutCaptureHealthPresentation(
                scope: status.scope,
                scopeLabelKey: scopeLabelKey,
                badgeKey: "settings.shortcuts.health.badge.degraded",
                titleKey: "settings.shortcuts.health.degraded.title",
                messageKey: "settings.shortcuts.health.degraded.message.permissions_accessibility",
                actionTitleKey: "settings.shortcuts.health.action.open_accessibility",
                action: .openAccessibilitySettings,
                isFallback: false
            )
        }

        return ShortcutCaptureHealthPresentation(
            scope: status.scope,
            scopeLabelKey: scopeLabelKey,
            badgeKey: "settings.shortcuts.health.badge.degraded",
            titleKey: "settings.shortcuts.health.degraded.title",
            messageKey: "settings.shortcuts.health.degraded.message.monitors",
            actionTitleKey: nil,
            action: .none,
            isFallback: false
        )
    }
}
