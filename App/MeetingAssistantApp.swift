import AppKit
import AppUpdater
import Combine
import KeyboardShortcuts
import MeetingAssistantCore
import os
import SwiftUI

/// Main entry point for the Verbi app.
/// Runs as a menu bar application without a dock icon.
@main
struct MeetingAssistantApp: App {
    enum WindowID {
        static let settings = "SettingsWindow"
    }

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        clearLegacyLanguageOverrideIfNeeded()
    }

    var body: some Scene {
        Window("settings.title".localized, id: WindowID.settings) {
            SettingsWindowContent()
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 640)
        .windowStyle(.hiddenTitleBar)
        .commands {
            MeetingAssistantCommands()
        }
    }
}

@MainActor
enum AppUpdaterContainer {
    static let shared = AppUpdater(
        owner: "mourato",
        repo: "verbi",
        releasePrefix: "Verbi",
    )

    static func checkForUpdates() {
        NavigationService.shared.openUpdates()
        shared.check()
    }
}

private struct SettingsWindowContent: View {
    @ObservedObject private var updater = AppUpdaterContainer.shared

    private var showsSystemSettingsBadge: Bool {
        switch updater.state {
        case .none:
            false
        default:
            true
        }
    }

    var body: some View {
        SettingsView(
            updatesView: AnyView(
                AppUpdateSettingsView()
                    .environmentObject(updater),
            ),
            showsSystemSettingsBadge: showsSystemSettingsBadge,
        )
    }
}

struct AppUpdateSettingsView: View {
    @EnvironmentObject private var updater: AppUpdater

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: AppDesignSystem.Layout.spacing12) {
                VStack(alignment: .leading, spacing: AppDesignSystem.Layout.spacing4) {
                    Text("settings.updates.title".localized)
                        .font(AppTypography.settingsSectionTitle)
                    Text("settings.updates.description".localized)
                        .font(AppTypography.settingsSectionDescription)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button("settings.updates.check".localized) {
                    updater.check()
                }
                .accessibilityHint("settings.updates.check_hint".localized)
            }
            .padding(.horizontal, AppDesignSystem.Layout.spacing20)
            .padding(.top, AppDesignSystem.Layout.spacing20)

            AppUpdateSettings()
        }
    }
}

private func clearLegacyLanguageOverrideIfNeeded() {
    let defaults = UserDefaults.standard
    let selectedLanguage = defaults.string(forKey: "selectedLanguage")

    // Keep system language behavior stable across launches, even if a stale override exists.
    if selectedLanguage == nil || selectedLanguage == "system" {
        defaults.removeObject(forKey: "AppleLanguages")
    }
}

private struct AppCommandKeyboardShortcut {
    let key: KeyEquivalent
    let modifiers: EventModifiers
}

private struct OptionalCommandKeyboardShortcutModifier: ViewModifier {
    let shortcut: AppCommandKeyboardShortcut?

    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        } else {
            content
        }
    }
}

private enum AppCommandShortcutDisplaySource {
    case inHouse(ShortcutDefinition)
    case preset
    case custom(KeyboardShortcuts.Shortcut)
    case none
}

@MainActor
final class AppCommandRouter: ObservableObject {
    struct Handlers {
        let toggleDictation: () -> Void
        let toggleMeeting: () -> Void
        let toggleAssistant: () -> Void
        let cancelCapture: () -> Void
        let openSettings: () -> Void
        let openHistory: () -> Void
        let openOnboarding: () -> Void
        let quit: () -> Void
    }

    static let shared = AppCommandRouter()

    @Published private(set) var state = AppCommandState()

    private var toggleDictationHandler: (() -> Void)?
    private var toggleMeetingHandler: (() -> Void)?
    private var toggleAssistantHandler: (() -> Void)?
    private var cancelCaptureHandler: (() -> Void)?
    private var openSettingsHandler: (() -> Void)?
    private var openHistoryHandler: (() -> Void)?
    private var openOnboardingHandler: (() -> Void)?
    private var quitHandler: (() -> Void)?

    private init() {}

    func registerHandlers(_ handlers: Handlers) {
        toggleDictationHandler = handlers.toggleDictation
        toggleMeetingHandler = handlers.toggleMeeting
        toggleAssistantHandler = handlers.toggleAssistant
        cancelCaptureHandler = handlers.cancelCapture
        openSettingsHandler = handlers.openSettings
        openHistoryHandler = handlers.openHistory
        openOnboardingHandler = handlers.openOnboarding
        quitHandler = handlers.quit
    }

    func update(state: AppCommandState) {
        guard self.state != state else { return }
        self.state = state
    }

    func toggleDictation() {
        toggleDictationHandler?()
    }

    func toggleMeeting() {
        toggleMeetingHandler?()
    }

    func toggleAssistant() {
        toggleAssistantHandler?()
    }

    func cancelCapture() {
        cancelCaptureHandler?()
    }

    func openSettings() {
        if let openSettingsHandler {
            openSettingsHandler()
        } else {
            NavigationService.shared.openSettings()
        }
    }

    func toggleSettingsSidebar() {
        openSettings()
        NavigationService.shared.requestSettingsSidebarToggle()
    }

    func openHistory() {
        if let openHistoryHandler {
            openHistoryHandler()
        } else {
            NavigationService.shared.openHistory()
        }
    }

    func openOnboarding() {
        if let openOnboardingHandler {
            openOnboardingHandler()
        } else {
            NavigationService.shared.openOnboarding()
        }
    }

    func bringAllToFront() {
        NSApp.arrangeInFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func quit() {
        quitHandler?()
    }
}

struct MeetingAssistantCommands: Commands {
    @ObservedObject private var commandRouter = AppCommandRouter.shared
    @State private var navigationService = NavigationService.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Named binding (not `let _ =` / `_ =`): SwiftFormat's redundantLet rewrites
        // `let _ =` to `_ =`, which Release/WMO rejects inside CommandsBuilder.
        let isSettingsOpenerRegistered = registerSettingsSceneOpener()

        CommandGroup(replacing: .appSettings) {
            Button("menubar.check_for_updates".localized) {
                guard isSettingsOpenerRegistered else { return }
                AppUpdaterContainer.checkForUpdates()
            }

            Button("menubar.settings".localized) {
                guard isSettingsOpenerRegistered else { return }
                commandRouter.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu("commands.capture.title".localized) {
            if commandRouter.state.showsDictationAction {
                Button(commandRouter.state.dictationTitleKey.localized) {
                    commandRouter.toggleDictation()
                }
                .modifier(OptionalCommandKeyboardShortcutModifier(shortcut: appCommandKeyboardShortcut(for: .dictationToggle)))
            }

            if commandRouter.state.showsMeetingAction {
                Button(commandRouter.state.meetingTitleKey.localized) {
                    commandRouter.toggleMeeting()
                }
                .modifier(OptionalCommandKeyboardShortcutModifier(shortcut: appCommandKeyboardShortcut(for: .meetingToggle)))
            }

            if commandRouter.state.showsAssistantAction {
                Button(commandRouter.state.assistantTitleKey.localized) {
                    commandRouter.toggleAssistant()
                }
                .modifier(OptionalCommandKeyboardShortcutModifier(shortcut: appCommandKeyboardShortcut(for: .assistantCommand)))
            }

            if commandRouter.state.showsCancelAction {
                Divider()

                Button(commandRouter.state.cancelTitleKey.localized) {
                    commandRouter.cancelCapture()
                }
                .modifier(
                    OptionalCommandKeyboardShortcutModifier(
                        shortcut: appCommandKeyboardShortcut(for: commandRouter.state.cancelRecordingShortcutDefinition),
                    ),
                )
            }
        }

        CommandGroup(replacing: .sidebar) {
            Button(sidebarTitle) {
                commandRouter.toggleSettingsSidebar()
            }
            .keyboardShortcut("S", modifiers: [.command, .control])
        }

        CommandGroup(after: .sidebar) {
            Button("menubar.history".localized) {
                commandRouter.openHistory()
            }
        }

        CommandGroup(after: .windowArrangement) {
            Button("commands.window.bring_all_to_front".localized) {
                commandRouter.bringAllToFront()
            }
        }

        CommandGroup(after: .help) {
            Button("menubar.onboarding".localized) {
                commandRouter.openOnboarding()
            }
        }
    }

    private var sidebarTitle: String {
        let key = navigationService.isSettingsSidebarVisible
            ? "commands.view.hide_sidebar"
            : "commands.view.show_sidebar"
        return key.localized
    }

    @MainActor
    private func registerSettingsSceneOpener() -> Bool {
        NavigationService.shared.registerOpenSettingsHandler {
            openWindow(id: MeetingAssistantApp.WindowID.settings)
        }
        return true
    }
}

extension ShortcutDefinition {
    var menuDisplayString: String {
        let modifierSymbols = modifiers.map { modifier in
            switch modifier {
            case .leftCommand, .rightCommand, .command: "⌘"
            case .leftShift, .rightShift, .shift: "⇧"
            case .leftOption, .rightOption, .option: "⌥"
            case .leftControl, .rightControl, .control: "⌃"
            case .fn: "Fn"
            }
        }

        var tokens = modifierSymbols
        if let primaryKey {
            tokens.append(primaryKey.display)
        } else if trigger == .doubleTap, let first = modifierSymbols.first {
            tokens.append(first)
        }

        return tokens.joined()
    }
}

@MainActor
private func appCommandShortcutDisplaySource(
    for shortcutName: KeyboardShortcuts.Name,
) -> AppCommandShortcutDisplaySource {
    let settings = AppSettingsStore.shared

    switch shortcutName {
    case .dictationToggle:
        return resolveShortcutDisplaySource(
            definition: settings.dictationShortcutDefinition,
            hasModifierShortcut: settings.dictationModifierShortcutGesture != nil,
            selectedPresetKey: settings.dictationSelectedPresetKey,
            fallbackShortcutName: shortcutName,
        )
    case .assistantCommand:
        return resolveShortcutDisplaySource(
            definition: settings.assistantShortcutDefinition,
            hasModifierShortcut: settings.assistantModifierShortcutGesture != nil,
            selectedPresetKey: settings.assistantSelectedPresetKey,
            fallbackShortcutName: shortcutName,
        )
    case .meetingToggle:
        return resolveShortcutDisplaySource(
            definition: settings.meetingShortcutDefinition,
            hasModifierShortcut: settings.meetingModifierShortcutGesture != nil,
            selectedPresetKey: settings.meetingSelectedPresetKey,
            fallbackShortcutName: shortcutName,
        )
    default:
        guard let shortcut = KeyboardShortcuts.Shortcut(name: shortcutName) else {
            return .none
        }
        return .custom(shortcut)
    }
}

private func resolveShortcutDisplaySource(
    definition: ShortcutDefinition?,
    hasModifierShortcut: Bool,
    selectedPresetKey: PresetShortcutKey,
    fallbackShortcutName: KeyboardShortcuts.Name,
) -> AppCommandShortcutDisplaySource {
    if let definition {
        return .inHouse(definition)
    }

    if hasModifierShortcut {
        return .none
    }

    if selectedPresetKey != .custom, selectedPresetKey != .notSpecified {
        return .preset
    }

    guard let shortcut = KeyboardShortcuts.Shortcut(name: fallbackShortcutName) else {
        return .none
    }
    return .custom(shortcut)
}

@MainActor
private func appCommandKeyboardShortcut(for shortcutName: KeyboardShortcuts.Name) -> AppCommandKeyboardShortcut? {
    switch appCommandShortcutDisplaySource(for: shortcutName) {
    case let .inHouse(shortcut):
        appCommandKeyboardShortcut(for: shortcut)
    case let .custom(shortcut):
        appCommandKeyboardShortcut(forCustomShortcut: shortcut)
    case .preset, .none:
        nil
    }
}

@MainActor
private func appCommandKeyboardShortcut(for shortcutDefinition: ShortcutDefinition?) -> AppCommandKeyboardShortcut? {
    guard let shortcutDefinition else { return nil }
    guard shortcutDefinition.trigger == .singleTap, let primaryKey = shortcutDefinition.primaryKey else {
        return nil
    }
    guard let keyEquivalent = keyEquivalent(for: primaryKey) else {
        return nil
    }
    return AppCommandKeyboardShortcut(
        key: keyEquivalent,
        modifiers: eventModifiers(from: shortcutDefinition.modifiers),
    )
}

@MainActor
private func appCommandKeyboardShortcut(forCustomShortcut shortcut: KeyboardShortcuts.Shortcut) -> AppCommandKeyboardShortcut? {
    let normalizedKey = normalizedShortcutKey(from: shortcut.description)
    guard let keyEquivalent = keyEquivalent(from: normalizedKey) else { return nil }
    return AppCommandKeyboardShortcut(
        key: keyEquivalent,
        modifiers: EventModifiers(shortcut.modifiers),
    )
}

private func normalizedShortcutKey(from description: String) -> String {
    let modifierSymbols = ["⌘", "⌥", "⌃", "⇧"]
    var cleanKey = description
    for symbol in modifierSymbols {
        cleanKey = cleanKey.replacingOccurrences(of: symbol, with: "")
    }
    return cleanKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func keyEquivalent(for primaryKey: ShortcutPrimaryKey) -> KeyEquivalent? {
    switch primaryKey.kind {
    case .space:
        KeyEquivalent.space
    case .function:
        nil
    default:
        keyEquivalent(from: primaryKey.display.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

private func keyEquivalent(from normalizedKey: String) -> KeyEquivalent? {
    switch normalizedKey {
    case "space":
        return KeyEquivalent.space
    case "return", "enter":
        return KeyEquivalent.return
    case "tab":
        return KeyEquivalent.tab
    case "backspace", "delete":
        return KeyEquivalent.delete
    case "escape", "esc":
        return KeyEquivalent.escape
    case "left":
        return KeyEquivalent.leftArrow
    case "right":
        return KeyEquivalent.rightArrow
    case "up":
        return KeyEquivalent.upArrow
    case "down":
        return KeyEquivalent.downArrow
    default:
        guard let character = normalizedKey.first, normalizedKey.count == 1 else {
            return nil
        }
        return KeyEquivalent(character)
    }
}

private func eventModifiers(from modifiers: [ModifierShortcutKey]) -> EventModifiers {
    modifiers.reduce(into: EventModifiers()) { partialResult, modifier in
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
            break
        }
    }
}

private extension EventModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.command) {
            insert(.command)
        }
        if flags.contains(.shift) {
            insert(.shift)
        }
        if flags.contains(.option) {
            insert(.option)
        }
        if flags.contains(.control) {
            insert(.control)
        }
    }
}

/// App delegate for menu bar setup and lifecycle management.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    struct RecordingUIRenderState: Equatable {
        let isRecording: Bool
        let isStarting: Bool
        let isTranscribing: Bool
        let isAssistantRecording: Bool
        let isAssistantProcessing: Bool
        let automaticMeetingRecordingConfirmation: AutomaticMeetingRecordingConfirmation?
        let meetingTypeRawValue: String?
        let isMeetingNotesPanelVisible: Bool
    }

    let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "AppDelegate")
    var statusItem: NSStatusItem?
    var contextMenu: NSMenu?
    var dictateMenuItem: NSMenuItem?
    var recordMeetingMenuItem: NSMenuItem?
    var assistantMenuItem: NSMenuItem?
    var cancelRecordingMenuItem: NSMenuItem?
    lazy var recordingManager: RecordingManager = .shared
    let settingsStore = AppSettingsStore.shared
    let localModelResidencyCoordinator = LocalModelResidencyCoordinator.shared
    lazy var floatingIndicatorController = FloatingRecordingIndicatorController()
    lazy var meetingNotesPaneController = MeetingNotesPaneController()
    lazy var meetingNotesPaneShortcutController = MeetingNotesPaneShortcutController(
        paneController: meetingNotesPaneController,
    )
    lazy var meetingNotesPanelController = MeetingNotesFloatingPanelController(
        paneController: meetingNotesPaneController,
    )
    lazy var globalShortcutController = GlobalShortcutController(recordingManager: RecordingManager.shared)
    lazy var assistantVoiceCommandService = AssistantVoiceCommandService(
        indicator: floatingIndicatorController,
    )
    lazy var assistantShortcutController = AssistantShortcutController(
        assistantService: assistantVoiceCommandService,
    )
    lazy var recordingCancelShortcutController = RecordingCancelShortcutController(
        stateProvider: { [weak self] in
            guard let self else {
                return RecordingCancelShortcutState(
                    isRecordingManagerCaptureActive: false,
                    isAssistantCaptureActive: false,
                )
            }
            return RecordingCancelShortcutState(
                isRecordingManagerCaptureActive: recordingManager.isRecording || recordingManager.isStartingRecording,
                isAssistantCaptureActive: assistantVoiceCommandService.isRecording,
            )
        },
        cancelRecordingManagerCapture: { [weak self] in
            await self?.recordingManager.cancelRecording()
        },
        cancelAssistantCapture: { [weak self] in
            await self?.assistantVoiceCommandService.cancelRecording()
        },
    )
    lazy var onboardingController = OnboardingWindowController()
    var cancellables = Set<AnyCancellable>()
    var appearanceObserver: AnyCancellable?
    var dockObserver: AnyCancellable?
    var hasConfiguredCapabilityObservers = false
    var lastRecordingUIRenderState: RecordingUIRenderState?
    var lastAppCommandState = AppCommandState()
    var isContextMenuOpen = false
    var hasPendingCommandMenuSync = false
    var hasPendingContextMenuRefresh = false
    var terminationTask: Task<Void, Never>?
}
