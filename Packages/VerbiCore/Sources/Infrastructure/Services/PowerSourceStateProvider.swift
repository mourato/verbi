import Foundation
import IOKit.ps

public enum PowerSourceState: String, Sendable, Equatable {
    case charging
    case battery
}

public protocol PowerSourceStateProviding: Sendable {
    func currentPowerSourceState() -> PowerSourceState
}

public struct PowerSourceStateProvider: PowerSourceStateProviding {
    public init() {}

    public func currentPowerSourceState() -> PowerSourceState {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .charging
        }

        if let sourceType = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue() as String? {
            if sourceType == kIOPSBatteryPowerValue {
                return .battery
            }
            if sourceType == kIOPSACPowerValue {
                return .charging
            }
        }

        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return .charging
        }

        var descriptions: [[String: Any]] = []
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            descriptions.append(description)
        }

        return Self.resolvePowerSourceState(from: descriptions)
    }

    public static func resolvePowerSourceState(from descriptions: [[String: Any]]) -> PowerSourceState {
        for description in descriptions {
            guard let state = description[kIOPSPowerSourceStateKey as String] as? String else {
                continue
            }

            if state == kIOPSBatteryPowerValue {
                return .battery
            }
        }

        return .charging
    }
}
