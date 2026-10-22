import Foundation

public enum AssistantShortcutSuppressionPolicy {
    public static func shouldSuppressEnterStopWhileRecording(
        assistantUseEnterToStopRecording: Bool,
        isAssistantRecording: Bool
    ) -> Bool {
        assistantUseEnterToStopRecording && isAssistantRecording
    }

    public static func shouldSuppressKeyDownEvents(
        shouldUseAssistantShortcutLayer: Bool,
        isShortcutLayerArmed: Bool,
        shouldSuppressEnterStopWhileRecording: Bool
    ) -> Bool {
        (shouldUseAssistantShortcutLayer && isShortcutLayerArmed) || shouldSuppressEnterStopWhileRecording
    }
}
