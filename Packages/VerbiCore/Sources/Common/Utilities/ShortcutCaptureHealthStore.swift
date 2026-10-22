import Foundation

public enum ShortcutCaptureHealthScope: String, CaseIterable, Equatable {
    case global
    case assistant
}

public enum ShortcutCaptureHealthResultState: String, Equatable {
    case idle
    case healthy
    case degraded
}

public struct ShortcutCaptureHealthStatus: Equatable {
    public let scope: ShortcutCaptureHealthScope
    public let result: ShortcutCaptureHealthResultState
    public let reasonToken: String
    public let requiresGlobalCapture: Bool
    public let accessibilityTrusted: Bool
    public let eventTapExpected: Bool
    public let eventTapActive: Bool

    public init(
        scope: ShortcutCaptureHealthScope,
        result: ShortcutCaptureHealthResultState,
        reasonToken: String,
        requiresGlobalCapture: Bool,
        accessibilityTrusted: Bool,
        eventTapExpected: Bool,
        eventTapActive: Bool
    ) {
        self.scope = scope
        self.result = result
        self.reasonToken = reasonToken
        self.requiresGlobalCapture = requiresGlobalCapture
        self.accessibilityTrusted = accessibilityTrusted
        self.eventTapExpected = eventTapExpected
        self.eventTapActive = eventTapActive
    }
}

@MainActor
public enum ShortcutCaptureHealthStore {
    private static var statuses: [ShortcutCaptureHealthScope: ShortcutCaptureHealthStatus] = Dictionary(uniqueKeysWithValues: ShortcutCaptureHealthScope.allCases.map { scope in
        (scope, defaultStatus(for: scope))
    })

    public static func status(for scope: ShortcutCaptureHealthScope) -> ShortcutCaptureHealthStatus {
        statuses[scope] ?? defaultStatus(for: scope)
    }

    public static func updateHealth(
        scope: ShortcutCaptureHealthScope,
        result: String,
        reasonToken: String,
        requiresGlobalCapture: Bool,
        accessibilityTrusted: Bool,
        eventTapExpected: Bool,
        eventTapActive: Bool
    ) {
        let normalizedResult = ShortcutCaptureHealthResultState(rawValue: result) ?? .idle
        let normalizedReasonToken = reasonToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedStatus = ShortcutCaptureHealthStatus(
            scope: scope,
            result: normalizedResult,
            reasonToken: normalizedReasonToken,
            requiresGlobalCapture: requiresGlobalCapture,
            accessibilityTrusted: accessibilityTrusted,
            eventTapExpected: eventTapExpected,
            eventTapActive: eventTapActive
        )

        guard statuses[scope] != updatedStatus else {
            return
        }

        statuses[scope] = updatedStatus
        NotificationCenter.default.post(
            name: .meetingAssistantShortcutCaptureHealthDidChange,
            object: nil,
            userInfo: [
                AppNotifications.UserInfoKey.shortcutCaptureHealthStatus: [
                    "scope": updatedStatus.scope.rawValue,
                    "result": updatedStatus.result.rawValue,
                    "reasonToken": updatedStatus.reasonToken
                ]
            ]
        )
    }

    public static func reset() {
        statuses = Dictionary(uniqueKeysWithValues: ShortcutCaptureHealthScope.allCases.map { scope in
            (scope, defaultStatus(for: scope))
        })
        NotificationCenter.default.post(name: .meetingAssistantShortcutCaptureHealthDidChange, object: nil)
    }

    private static func defaultStatus(for scope: ShortcutCaptureHealthScope) -> ShortcutCaptureHealthStatus {
        ShortcutCaptureHealthStatus(
            scope: scope,
            result: .idle,
            reasonToken: "",
            requiresGlobalCapture: false,
            accessibilityTrusted: true,
            eventTapExpected: false,
            eventTapActive: false
        )
    }
}
