import Foundation
import VerbiCoreCommon

public extension AppSettingsStore {
    enum ModelResidencyTimeoutOption: String, CaseIterable, Codable, Sendable {
        case minutes5
        case minutes10
        case minutes15
        case minutes30
        case minutes60
        case never

        public var inactivityInterval: TimeInterval? {
            switch self {
            case .minutes5:
                TimeInterval(5 * 60)
            case .minutes10:
                TimeInterval(10 * 60)
            case .minutes15:
                TimeInterval(15 * 60)
            case .minutes30:
                TimeInterval(30 * 60)
            case .minutes60:
                TimeInterval(60 * 60)
            case .never:
                nil
            }
        }

        public var displayName: String {
            switch self {
            case .minutes5:
                "settings.service.model_residency_timeout.option.5m".localized
            case .minutes10:
                "settings.service.model_residency_timeout.option.10m".localized
            case .minutes15:
                "settings.service.model_residency_timeout.option.15m".localized
            case .minutes30:
                "settings.service.model_residency_timeout.option.30m".localized
            case .minutes60:
                "settings.service.model_residency_timeout.option.60m".localized
            case .never:
                "settings.service.model_residency_timeout.option.never".localized
            }
        }
    }
}
