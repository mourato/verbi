// Re-export internal modules so app code can continue to `import VerbiCore`.

@_exported import VerbiCoreAI
@_exported import VerbiCoreAudio
@_exported import VerbiCoreCommon
@_exported import VerbiCoreData
@_exported import VerbiCoreDomain
@_exported import VerbiCoreInfrastructure
@_exported import VerbiCoreUI

public typealias ShortcutTelemetry = VerbiCoreCommon.ShortcutTelemetry
public typealias ShortcutTelemetryEvent = VerbiCoreCommon.ShortcutTelemetryEvent
public typealias ShortcutTelemetryEventName = VerbiCoreCommon.ShortcutTelemetryEventName
public typealias ShortcutTelemetryLevel = VerbiCoreCommon.ShortcutTelemetryLevel
public typealias ShortcutTelemetryRecord = VerbiCoreCommon.ShortcutTelemetryRecord

// Re-export shortcut input types for convenience
public typealias ShortcutInputEvent = VerbiCoreInfrastructure.ShortcutInputEvent
public typealias ShortcutInputEventKind = VerbiCoreInfrastructure.ShortcutInputEventKind
public typealias ShortcutInputBackend = VerbiCoreInfrastructure.ShortcutInputBackend
public typealias MockShortcutInputBackend = VerbiCoreInfrastructure.MockShortcutInputBackend
public typealias DoubleEscapePressDetector = VerbiCoreInfrastructure.DoubleEscapePressDetector
