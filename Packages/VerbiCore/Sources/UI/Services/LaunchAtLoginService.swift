import ServiceManagement

@MainActor
public protocol LaunchAtLoginService: AnyObject {
    var isEnabled: Bool { get }

    func register() throws
    func unregister() throws
}

@MainActor
public final class SystemLaunchAtLoginService: LaunchAtLoginService {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

public enum LaunchAtLoginUpdateError: Equatable, Sendable {
    case registrationFailed
    case unregistrationFailed

    public var messageKey: String {
        switch self {
        case .registrationFailed:
            "settings.general.launch_at_login.registration_error"
        case .unregistrationFailed:
            "settings.general.launch_at_login.unregistration_error"
        }
    }

    var requestedValue: Bool {
        switch self {
        case .registrationFailed:
            true
        case .unregistrationFailed:
            false
        }
    }
}
