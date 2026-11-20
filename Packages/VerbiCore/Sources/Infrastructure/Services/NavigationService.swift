import AppKit
import Observation
import VerbiCoreCommon

@MainActor
@Observable
public final class NavigationService {
    public static let shared = NavigationService()

    public var requestedSettingsSection: String?
    public private(set) var settingsSidebarToggleRequestID: UInt64 = 0
    public private(set) var isSettingsSidebarVisible = true
    private var openSettingsHandler: (@MainActor () -> Void)?
    private var openOnboardingHandler: (@MainActor () -> Void)?
    private var hasPendingOpenSettingsRequest = false

    private init() {}

    public func registerOpenSettingsHandler(_ handler: @escaping @MainActor () -> Void) {
        openSettingsHandler = handler

        guard hasPendingOpenSettingsRequest else { return }
        hasPendingOpenSettingsRequest = false

        DispatchQueue.main.async {
            Self.presentSettings(using: handler)
        }
    }

    public func registerOpenOnboardingHandler(_ handler: @escaping @MainActor () -> Void) {
        openOnboardingHandler = handler
    }

    public func openSettings() {
        if let openSettingsHandler {
            Self.presentSettings(using: openSettingsHandler)
            return
        }

        hasPendingOpenSettingsRequest = true
    }

    private static func presentSettings(using open: @MainActor () -> Void) {
        if let app = NSApp {
            app.activate(ignoringOtherApps: true)
        }
        open()
        DispatchQueue.main.async {
            orderSettingsWindowFront()
        }
    }

    private static func orderSettingsWindowFront() {
        guard let app = NSApp else { return }

        let autosaveName = AppIdentity.settingsWindowAutosaveName
        if let window = app.windows.first(where: { $0.frameAutosaveName == autosaveName }) {
            window.makeKeyAndOrderFront(nil)
            return
        }

        if let window = app.windows.first(where: {
            $0.isVisible && $0.canBecomeKey && !($0 is NSPanel)
        }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    public func openSettings(section: String) {
        requestedSettingsSection = section
        openSettings()
    }

    public func openHistory() {
        openSettings(section: "history")
    }

    public func openOnboarding() {
        openOnboardingHandler?()
    }

    public func requestSettingsSidebarToggle() {
        settingsSidebarToggleRequestID &+= 1
    }

    public func setSettingsSidebarVisible(_ isVisible: Bool) {
        guard isSettingsSidebarVisible != isVisible else { return }
        isSettingsSidebarVisible = isVisible
    }

    public func showAbout() {
        let alert = NSAlert()
        alert.messageText = AppIdentity.displayName
        alert.informativeText =
            "about.version".localized(with: AppVersion.current) + "\n\n" +
            "about.description".localized + "\n\n" +
            "about.copyright".localized(with: 2025)
        alert.alertStyle = .informational
        alert.icon = NSImage(
            systemSymbolName: "waveform.circle.fill",
            accessibilityDescription: AppIdentity.displayName
        )
        alert.addButton(withTitle: "common.ok".localized)

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
