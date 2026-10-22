import Foundation

public enum ShortcutTelemetryEventName: String, CaseIterable, Sendable {
    case shortcutDetected = "shortcut_detected"
    case shortcutRejected = "shortcut_rejected"
    case layerArmed = "layer_armed"
    case layerTimeout = "layer_timeout"
    case captureHealthChanged = "capture_health_changed"
}

public enum ShortcutTelemetryLevel: Equatable, Sendable {
    case info
    case warning
}

public struct ShortcutTelemetryRecord: Equatable, Sendable {
    public let name: ShortcutTelemetryEventName
    public let level: ShortcutTelemetryLevel
    public let payload: [String: String]

    public init(
        name: ShortcutTelemetryEventName,
        level: ShortcutTelemetryLevel,
        payload: [String: String]
    ) {
        self.name = name
        self.level = level
        self.payload = payload
    }
}

public enum ShortcutTelemetryEvent: Equatable, Sendable {
    case shortcutDetected(
        pipeline: String,
        scope: String,
        shortcutTarget: String,
        source: String,
        trigger: String
    )

    case shortcutRejected(
        pipeline: String,
        scope: String,
        shortcutTarget: String,
        source: String,
        trigger: String,
        reason: String
    )

    case layerArmed(
        pipeline: String,
        scope: String,
        source: String,
        trigger: String,
        timeoutMs: Int
    )

    case layerTimeout(
        pipeline: String,
        scope: String,
        source: String,
        timeoutMs: Int
    )

    case captureHealthChanged(
        pipeline: String,
        scope: String,
        source: String,
        result: String,
        previousResult: String?,
        reason: String?,
        requiresGlobalCapture: Bool,
        accessibilityTrusted: Bool,
        flagsMonitorExpected: Bool,
        flagsMonitorActive: Bool,
        keyDownMonitorExpected: Bool,
        keyDownMonitorActive: Bool,
        keyUpMonitorExpected: Bool,
        keyUpMonitorActive: Bool,
        eventTapExpected: Bool,
        eventTapActive: Bool,
        checkedAtEpochMs: Int64
    )

    public var record: ShortcutTelemetryRecord {
        switch self {
        case let .shortcutDetected(pipeline, scope, shortcutTarget, source, trigger):
            return ShortcutTelemetryRecord(
                name: .shortcutDetected,
                level: .info,
                payload: basePayload(pipeline: pipeline, scope: scope).merging(
                    [
                        "shortcut_target": Self.sanitizeToken(shortcutTarget),
                        "source": Self.sanitizeToken(source),
                        "trigger": Self.sanitizeToken(trigger)
                    ],
                    uniquingKeysWith: { _, new in new }
                )
            )

        case let .shortcutRejected(pipeline, scope, shortcutTarget, source, trigger, reason):
            return ShortcutTelemetryRecord(
                name: .shortcutRejected,
                level: .warning,
                payload: basePayload(pipeline: pipeline, scope: scope).merging(
                    [
                        "shortcut_target": Self.sanitizeToken(shortcutTarget),
                        "source": Self.sanitizeToken(source),
                        "trigger": Self.sanitizeToken(trigger),
                        "reason": Self.sanitizeToken(reason)
                    ],
                    uniquingKeysWith: { _, new in new }
                )
            )

        case let .layerArmed(pipeline, scope, source, trigger, timeoutMs):
            return ShortcutTelemetryRecord(
                name: .layerArmed,
                level: .info,
                payload: basePayload(pipeline: pipeline, scope: scope).merging(
                    [
                        "source": Self.sanitizeToken(source),
                        "trigger": Self.sanitizeToken(trigger),
                        "layer_timeout_ms": String(max(timeoutMs, 0))
                    ],
                    uniquingKeysWith: { _, new in new }
                )
            )

        case let .layerTimeout(pipeline, scope, source, timeoutMs):
            return ShortcutTelemetryRecord(
                name: .layerTimeout,
                level: .warning,
                payload: basePayload(pipeline: pipeline, scope: scope).merging(
                    [
                        "source": Self.sanitizeToken(source),
                        "reason": "timeout",
                        "layer_timeout_ms": String(max(timeoutMs, 0))
                    ],
                    uniquingKeysWith: { _, new in new }
                )
            )

        case let .captureHealthChanged(
            pipeline,
            scope,
            source,
            result,
            previousResult,
            reason,
            requiresGlobalCapture,
            accessibilityTrusted,
            flagsMonitorExpected,
            flagsMonitorActive,
            keyDownMonitorExpected,
            keyDownMonitorActive,
            keyUpMonitorExpected,
            keyUpMonitorActive,
            eventTapExpected,
            eventTapActive,
            checkedAtEpochMs
        ):
            let normalizedResult = Self.sanitizeToken(result)
            var payload = basePayload(pipeline: pipeline, scope: scope).merging(
                [
                    "source": Self.sanitizeToken(source),
                    "result": normalizedResult,
                    "requires_global_capture": requiresGlobalCapture ? "true" : "false",
                    "accessibility_trusted": accessibilityTrusted ? "true" : "false",
                    "flags_monitor_expected": flagsMonitorExpected ? "true" : "false",
                    "flags_monitor_active": flagsMonitorActive ? "true" : "false",
                    "key_down_monitor_expected": keyDownMonitorExpected ? "true" : "false",
                    "key_down_monitor_active": keyDownMonitorActive ? "true" : "false",
                    "key_up_monitor_expected": keyUpMonitorExpected ? "true" : "false",
                    "key_up_monitor_active": keyUpMonitorActive ? "true" : "false",
                    "event_tap_expected": eventTapExpected ? "true" : "false",
                    "event_tap_active": eventTapActive ? "true" : "false",
                    "checked_at_epoch_ms": String(max(checkedAtEpochMs, 0))
                ],
                uniquingKeysWith: { _, new in new }
            )

            if let previousResult {
                payload["previous_result"] = Self.sanitizeToken(previousResult)
            }

            if let reason {
                payload["reason"] = Self.sanitizeToken(reason)
            }

            return ShortcutTelemetryRecord(
                name: .captureHealthChanged,
                level: normalizedResult == "degraded" ? .warning : .info,
                payload: payload
            )
        }
    }

    private func basePayload(pipeline: String, scope: String) -> [String: String] {
        [
            "pipeline": Self.sanitizeToken(pipeline),
            "scope": Self.sanitizeToken(scope)
        ]
    }

    private static func sanitizeToken(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "unknown"
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let scalars = trimmed.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let normalized = String(scalars)
        let compact = normalized.replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
        return String(compact.prefix(64))
    }
}

public enum ShortcutTelemetry {
    public static let schemaVersion = "1"

    public static func emit(_ event: ShortcutTelemetryEvent, category: LogCategory = .health) {
        let record = event.record

        var payload = record.payload
        payload["event"] = record.name.rawValue
        payload["schema_version"] = schemaVersion

        let extra = payload.reduce(into: [String: Any]()) { partialResult, item in
            partialResult[item.key] = item.value
        }

        switch record.level {
        case .info:
            AppLogger.info("shortcut_telemetry", category: category, extra: extra)
        case .warning:
            AppLogger.warning("shortcut_telemetry", category: category, extra: extra)
        }
    }
}
