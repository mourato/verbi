import AppKit
import Combine
import MeetingAssistantCore

extension AppDelegate {
    func configureUserInterfacePreferences() {
        applyAppearance(settingsStore.appearanceMode)
        applyDockVisibility(settingsStore.showInDock)

        appearanceObserver = settingsStore.$appearanceMode
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.applyAppearance(mode)
            }

        dockObserver = settingsStore.$showInDock
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showInDock in
                self?.applyDockVisibility(showInDock)
            }
    }

    func applyDockVisibility(_ showInDock: Bool) {
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }

        guard NSApp.setActivationPolicy(policy) else {
            logger.error("Failed to set activation policy to \(showInDock ? "regular" : "accessory")")
            return
        }

        logger.info("Activation policy set to: \(showInDock ? "regular (dock)" : "accessory (menu bar only)")")
    }

    func applyAppearance(_ mode: AppearanceMode) {
        if let appearanceName = mode.nsAppearanceName {
            NSApp.appearance = NSAppearance(named: appearanceName)
        } else {
            NSApp.appearance = nil
        }
    }
}
