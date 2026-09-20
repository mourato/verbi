import AppKit
import Combine
import MeetingAssistantCore
import os
import SwiftUI

extension AppDelegate {
    private func performAfterMenuDismissal(_ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            Task { @MainActor in
                action()
            }
        }
    }

    // MARK: - Menu Bar Setup

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.isVisible = true

        if let button = statusItem?.button {
            let image = makeStatusBarImage(
                isRecording: false,
                accessibilityDescription: "about.title".localized
            )
            button.image = image
            button.title = image == nil ? String(AppIdentity.displayName.prefix(1)) : ""
            button.imagePosition = image == nil ? .noImage : .imageOnly
            button.action = #selector(handleStatusItemClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
    }

    func setupContextMenu() {
        contextMenu = NSMenu()
        contextMenu?.delegate = self

        // Dictate (Mic Only)
        let dictateItem = createMenuItem(
            key: "menubar.dictate",
            action: #selector(toggleRecordingFromMenu),
            shortcutDefinition: settingsStore.dictationShortcutDefinition
        )
        dictateMenuItem = dictateItem
        contextMenu?.addItem(dictateItem)

        // Record Meeting (Recorder)
        let meetingItem = createMenuItem(
            key: "menubar.record_meeting",
            action: #selector(startMeetingFromMenu),
            shortcutDefinition: settingsStore.meetingShortcutDefinition
        )
        recordMeetingMenuItem = meetingItem
        contextMenu?.addItem(meetingItem)

        // Assistant
        let assistantItem = createMenuItem(
            key: "menubar.assistant",
            action: #selector(startAssistantFromMenu),
            shortcutDefinition: settingsStore.assistantShortcutDefinition
        )
        assistantMenuItem = assistantItem
        contextMenu?.addItem(assistantItem)

        let cancelItem = createMenuItem(
            key: "menubar.cancel_recording",
            action: #selector(cancelRecordingFromMenu)
        )
        cancelRecordingMenuItem = cancelItem
        cancelItem.isHidden = true
        contextMenu?.addItem(cancelItem)

        contextMenu?.addItem(NSMenuItem.separator())

        contextMenu?.addItem(createMenuItem(
            key: "menubar.history",
            action: #selector(openHistory),
            systemImage: SettingsSection.transcriptions.icon
        ))

        contextMenu?.addItem(NSMenuItem.separator())

        contextMenu?.addItem(createMenuItem(
            key: "menubar.settings",
            action: #selector(openSettings),
            keyEquivalent: ","
        ))
        contextMenu?.addItem(createMenuItem(
            key: "menubar.onboarding",
            action: #selector(openOnboarding)
        ))
        contextMenu?.addItem(createMenuItem(
            key: "menubar.quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        ))
    }

    /// Creates a localized menu item with the given key and action.
    private func createMenuItem(
        key: String,
        action: Selector,
        keyEquivalent: String = "",
        shortcutDefinition: ShortcutDefinition? = nil,
        systemImage: String? = nil
    ) -> NSMenuItem {
        let title = key.localized
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if let systemImage {
            item.image = NSImage(
                systemSymbolName: systemImage,
                accessibilityDescription: title
            )
            item.image?.isTemplate = true
        }

        if shortcutDefinition != nil {
            applyShortcutDefinition(shortcutDefinition, to: item, title: title)
        }

        return item
    }

    func updateMenuTitles() {
        guard !isContextMenuOpen else {
            hasPendingContextMenuRefresh = true
            return
        }

        renderRecordingSection(for: lastAppCommandState)
    }

    private func updateMenuItem(_ item: NSMenuItem?, key: String, shortcutDefinition: ShortcutDefinition?) {
        let title = key.localized
        guard let item else { return }
        applyShortcutDefinition(shortcutDefinition, to: item, title: title)
    }

    private func renderRecordingSection(for state: AppCommandState) {
        updateMenuItem(
            dictateMenuItem,
            key: state.dictationTitleKey,
            shortcutDefinition: settingsStore.dictationShortcutDefinition
        )
        updateMenuItem(
            recordMeetingMenuItem,
            key: state.meetingTitleKey,
            shortcutDefinition: settingsStore.meetingShortcutDefinition
        )
        updateMenuItem(
            assistantMenuItem,
            key: state.assistantTitleKey,
            shortcutDefinition: settingsStore.assistantShortcutDefinition
        )
        updateMenuItem(
            cancelRecordingMenuItem,
            key: state.cancelTitleKey,
            shortcutDefinition: state.cancelRecordingShortcutDefinition
        )

        dictateMenuItem?.isHidden = !state.showsDictationAction
        recordMeetingMenuItem?.isHidden = !state.showsMeetingAction
        assistantMenuItem?.isHidden = !state.showsAssistantAction
        cancelRecordingMenuItem?.isHidden = !state.showsCancelAction
    }

    private func applyShortcutDefinition(
        _ shortcutDefinition: ShortcutDefinition?,
        to item: NSMenuItem,
        title: String
    ) {
        guard let shortcutDefinition else {
            item.title = title
            clearShortcut(from: item)
            return
        }

        if applyShortcutDefinition(shortcutDefinition, to: item, title: title) {
            return
        }

        item.title = "\(title) [\(shortcutDefinition.menuDisplayString)]"
        clearShortcut(from: item)
    }

    private func menuKeyEquivalent(from normalizedKey: String) -> String? {
        switch normalizedKey {
        case "space":
            return " "
        case "return", "enter":
            return "\r"
        case "tab":
            return "\t"
        case "backspace", "delete":
            guard let scalar = UnicodeScalar(NSBackspaceCharacter) else { return nil }
            return String(scalar)
        case "escape", "esc":
            return "\u{1b}"
        case "left":
            guard let scalar = UnicodeScalar(NSLeftArrowFunctionKey) else { return nil }
            return String(scalar)
        case "right":
            guard let scalar = UnicodeScalar(NSRightArrowFunctionKey) else { return nil }
            return String(scalar)
        case "up":
            guard let scalar = UnicodeScalar(NSUpArrowFunctionKey) else { return nil }
            return String(scalar)
        case "down":
            guard let scalar = UnicodeScalar(NSDownArrowFunctionKey) else { return nil }
            return String(scalar)
        default:
            return normalizedKey.first.map(String.init)
        }
    }

    private func applyShortcutDefinition(
        _ shortcut: ShortcutDefinition,
        to item: NSMenuItem,
        title: String
    ) -> Bool {
        guard shortcut.trigger == .singleTap,
              let primaryKey = shortcut.primaryKey,
              let keyEquivalent = keyEquivalent(for: primaryKey)
        else {
            return false
        }

        item.title = title
        item.keyEquivalent = keyEquivalent
        item.keyEquivalentModifierMask = modifierMask(from: shortcut.modifiers)
        return true
    }

    private func keyEquivalent(for primaryKey: ShortcutPrimaryKey) -> String? {
        switch primaryKey.kind {
        case .space:
            return " "
        case .function:
            guard let functionIndex = primaryKey.functionIndex else {
                return nil
            }
            let scalarValue = Int(NSF1FunctionKey) + functionIndex - 1
            guard let scalar = UnicodeScalar(scalarValue) else {
                return nil
            }
            return String(scalar)
        default:
            let normalized = primaryKey.display
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return menuKeyEquivalent(from: normalized)
        }
    }

    private func modifierMask(from modifiers: [ModifierShortcutKey]) -> NSEvent.ModifierFlags {
        modifiers.reduce(into: NSEvent.ModifierFlags()) { partialResult, modifier in
            switch modifier {
            case .leftCommand, .rightCommand, .command:
                partialResult.insert(.command)
            case .leftShift, .rightShift, .shift:
                partialResult.insert(.shift)
            case .leftOption, .rightOption, .option:
                partialResult.insert(.option)
            case .leftControl, .rightControl, .control:
                partialResult.insert(.control)
            case .fn:
                partialResult.insert(.function)
            }
        }
    }

    private func clearShortcut(from item: NSMenuItem) {
        item.keyEquivalent = ""
        item.keyEquivalentModifierMask = []
    }

    @objc private func handleStatusItemClick() {
        showContextMenu()
    }

    private func showContextMenu() {
        guard let menu = contextMenu, let button = statusItem?.button else { return }

        updateMenuTitles()
        statusItem?.menu = menu
        button.performClick(nil)
    }

    // MARK: - Menu Actions

    @objc func openSettings() {
        performAfterMenuDismissal { [weak self] in
            self?.promoteAppForWindowPresentation()
            NavigationService.shared.openSettings()
        }
    }

    @objc func openOnboarding() {
        performAfterMenuDismissal { [weak self] in
            self?.promoteAppForWindowPresentation()
            self?.presentOnboarding {}
        }
    }

    @objc func openHistory() {
        performAfterMenuDismissal { [weak self] in
            self?.promoteAppForWindowPresentation()
            NavigationService.shared.openHistory()
        }
    }

    @objc func toggleRecordingFromMenu() {
        performAfterMenuDismissal { [weak self] in
            Task { @MainActor in
                // Default "Dictation" mode (Mic Only)
                await self?.startRecording(source: .microphone)
            }
        }
    }

    @objc func startMeetingFromMenu() {
        performAfterMenuDismissal { [weak self] in
            guard let self else { return }
            guard settingsStore.isMeetingTranscriptionEnabled else {
                floatingIndicatorController.showError("recording.error.meeting_transcription_disabled".localized)
                return
            }

            Task { @MainActor in
                // Meeting mode (System + Mic) permissions will be checked by manager
                await self.startRecording(source: .all)
            }
        }
    }

    @objc func startAssistantFromMenu() {
        performAfterMenuDismissal { [weak self] in
            guard let self else { return }
            guard settingsStore.isAssistantEnabled else {
                floatingIndicatorController.showError("assistant.error.disabled".localized)
                return
            }

            Task {
                if self.assistantVoiceCommandService.isRecording {
                    await self.assistantVoiceCommandService.stopAndProcess()
                } else if self.recordingManager.isRecording || self.recordingManager.isStartingRecording {
                    AppLogger.info(
                        "Assistant menu start blocked by active recording capture",
                        category: .assistant
                    )
                    self.floatingIndicatorController.showError("assistant.error.recording_in_progress".localized)
                } else {
                    await self.assistantVoiceCommandService.startRecording()
                }
            }
        }
    }

    @objc func cancelRecordingFromMenu() {
        performAfterMenuDismissal { [weak self] in
            guard let self else { return }
            Task {
                if self.assistantVoiceCommandService.isRecording {
                    await self.assistantVoiceCommandService.cancelRecording()
                } else if self.recordingManager.isRecording || self.recordingManager.isStartingRecording {
                    await self.recordingManager.cancelRecording()
                }
            }
        }
    }

    @objc func quitApp() {
        performAfterMenuDismissal {
            NSApp.terminate(nil)
        }
    }

    func performCleanup() async {
        if AppSettingsStore.shared.autoDeleteTranscriptions {
            let days = AppSettingsStore.shared.autoDeletePeriodDays
            do {
                try await FileSystemStorageService.shared.cleanupOldTranscriptions(olderThanDays: days)
                _ = FluidAIModelManager.shared.unloadDiarizationFromMemoryIfPossible()
                _ = FluidAIModelManager.shared.unloadASRFromMemoryIfPossible()
                _ = try await LocalAICacheMaintenanceService.shared.performCleanup(olderThanDays: days)
            } catch {
                logger.error("Failed to perform auto-cleanup: \(error.localizedDescription)")
            }
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === contextMenu else { return }
        isContextMenuOpen = true
        renderRecordingSection(for: lastAppCommandState)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === contextMenu else { return }

        let shouldSyncCommandMenu = hasPendingCommandMenuSync
        let shouldRefreshContextMenu = hasPendingContextMenuRefresh

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            statusItem?.menu = nil
            isContextMenuOpen = false
            hasPendingContextMenuRefresh = false

            if shouldRefreshContextMenu {
                renderRecordingSection(for: lastAppCommandState)
            }

            guard shouldSyncCommandMenu else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.syncCommandMenuStateIfNeeded(force: true)
            }
        }
    }
}
