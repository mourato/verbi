import AppKit
import MeetingAssistantCoreAI
import SwiftUI

// MARK: - Onboarding Window Controller

/// Manages the dedicated onboarding window with modal presentation.
@MainActor
public final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var didCompleteOnboarding = false
    private var hasHandledWindowClose = false
    private var onDismiss: (() -> Void)?

    override public init() {
        super.init()
    }

    /// Shows the onboarding window as a modal sheet over the main app.
    public func showOnboarding(
        viewModel: OnboardingViewModel,
        permissionViewModel: PermissionViewModel,
        shortcutViewModel: ShortcutSettingsViewModel,
        assistantShortcutViewModel: AssistantShortcutSettingsViewModel,
        modelManager: FluidAIModelManager,
        refreshPermissions: @escaping @MainActor () async -> Void,
        completion: @escaping () -> Void
    ) {
        didCompleteOnboarding = false
        hasHandledWindowClose = false
        onDismiss = completion

        // Create the onboarding view with all dependencies
        let onboardingView = OnboardingView(
            viewModel: viewModel,
            permissionViewModel: permissionViewModel,
            shortcutViewModel: shortcutViewModel,
            assistantShortcutViewModel: assistantShortcutViewModel,
            modelManager: modelManager,
            refreshPermissions: refreshPermissions,
            onComplete: { [weak self] in
                self?.didCompleteOnboarding = true
                self?.closeOnboarding()
                completion()
            }
        )

        // Create window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "onboarding.title".localized
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        // Style the window
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)

        // Make it modal
        if let mainWindow = NSApplication.shared.mainWindow {
            mainWindow.beginSheet(window) { [weak self] _ in
                self?.handleWindowDidClose()
            }
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        self.window = window
    }

    /// Closes the onboarding window.
    public func closeOnboarding() {
        guard let window else { return }

        if let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
        } else {
            window.close()
        }
    }

    public func windowShouldClose(_: NSWindow) -> Bool {
        true
    }

    public func windowWillClose(_: Notification) {
        handleWindowDidClose()
    }

    private func handleWindowDidClose() {
        guard !hasHandledWindowClose else { return }
        hasHandledWindowClose = true

        window?.delegate = nil
        window = nil

        let onDismiss = onDismiss
        self.onDismiss = nil

        guard !didCompleteOnboarding else { return }
        onDismiss?()
    }
}
