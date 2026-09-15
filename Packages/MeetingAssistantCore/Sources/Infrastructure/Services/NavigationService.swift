import AppKit
import MeetingAssistantCoreCommon
import Observation

/// Service to handle navigation and window management across the app.
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

    /// Registers an explicit settings opener provided by the app target.
    public func registerOpenSettingsHandler(_ handler: @escaping @MainActor () -> Void) {
        openSettingsHandler = handler

        guard hasPendingOpenSettingsRequest else { return }
        hasPendingOpenSettingsRequest = false

        DispatchQueue.main.async {
            Self.presentSettings(using: handler)
        }
    }

    /// Registers an explicit onboarding opener provided by the app target.
    public func registerOpenOnboardingHandler(_ handler: @escaping @MainActor () -> Void) {
        openOnboardingHandler = handler
    }

    /// Opens the settings/dashboard window.
    public func openSettings() {
        if let openSettingsHandler {
            Self.presentSettings(using: openSettingsHandler)
            return
        }

        // The SwiftUI settings window opener may register after AppDelegate launch work.
        // Queue one pending request instead of falling back to the legacy Settings scene API.
        hasPendingOpenSettingsRequest = true
    }

    /// Menu-bar / accessory apps do not steal focus on `openWindow` alone.
    /// Always activate, then order the settings window front after it exists.
    private static func presentSettings(using open: @MainActor () -> Void) {
        if let app = NSApp {
            if app.activationPolicy() != .regular {
                app.setActivationPolicy(.regular)
            }
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

        // First open: autosave name may not be applied until the configurator runs.
        if let window = app.windows.first(where: {
            $0.isVisible && $0.canBecomeKey && !($0 is NSPanel)
        }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Opens the settings window and requests a specific section.
    public func openSettings(section: String) {
        requestedSettingsSection = section
        openSettings()
    }

    public func openHistory() {
        openSettings(section: "history")
    }

    public func openUpdates() {
        openSettings(section: "updates")
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

    /// Shows the About alert.
    public func showAbout() {
        let alert = NSAlert()
        alert.messageText = "about.title".localized
        alert.informativeText =
            "about.version".localized(with: AppVersion.current) + "\n\n" +
            "about.description".localized + "\n\n" +
            "about.copyright".localized(with: 2025)
        alert.alertStyle = .informational
        alert.icon = NSImage(
            systemSymbolName: "waveform.circle.fill",
            accessibilityDescription: "about.title".localized
        )
        alert.addButton(withTitle: "common.ok".localized)

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
