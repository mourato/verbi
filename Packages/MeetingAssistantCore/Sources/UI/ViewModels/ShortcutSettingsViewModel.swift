import Combine
import Foundation
import KeyboardShortcuts
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

// MARK: - Shortcut Settings View Model

@MainActor
public class ShortcutSettingsViewModel: ObservableObject {
    private let settings = AppSettingsStore.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Published Properties

    @Published public var useEscapeToCancelRecording: Bool
    @Published public var selectedPresetKey: PresetShortcutKey
    @Published public var dictationSelectedPresetKey: PresetShortcutKey
    @Published public var meetingSelectedPresetKey: PresetShortcutKey
    @Published public var dictationShortcutDefinition: ShortcutDefinition?
    @Published public var dictationModifierConflictMessage: String?
    @Published public var meetingShortcutDefinition: ShortcutDefinition?
    @Published public var meetingModifierConflictMessage: String?
    @Published public private(set) var shortcutCaptureHealthPresentation: ShortcutCaptureHealthPresentation?
    @Published public var testKeysInput: String = ""

    /// Whether the user is recording a custom shortcut
    @Published public var isRecordingCustomShortcut: Bool = false
    private var isApplyingShortcutChange = false

    // MARK: - Initialization

    public init() {
        useEscapeToCancelRecording = settings.useEscapeToCancelRecording
        selectedPresetKey = settings.selectedPresetKey
        dictationSelectedPresetKey = settings.dictationSelectedPresetKey
        meetingSelectedPresetKey = settings.meetingSelectedPresetKey
        dictationShortcutDefinition = settings.dictationShortcutDefinition
        dictationModifierConflictMessage = nil
        meetingShortcutDefinition = settings.meetingShortcutDefinition
        meetingModifierConflictMessage = nil
        shortcutCaptureHealthPresentation = Self.makeShortcutCaptureHealthPresentation()

        setupBindings()
    }

    // MARK: - Private Setup

    private func setupBindings() {
        // Sync escape cancel setting
        $useEscapeToCancelRecording
            .dropFirst()
            .sink { [weak self] newValue in
                self?.settings.useEscapeToCancelRecording = newValue
            }
            .store(in: &cancellables)

        // Sync preset key selection
        $selectedPresetKey
            .dropFirst()
            .sink { [weak self] newValue in
                self?.settings.selectedPresetKey = newValue
                self?.isRecordingCustomShortcut = (newValue == .custom)
            }
            .store(in: &cancellables)

        // Sync Dictation preset
        $dictationSelectedPresetKey
            .dropFirst()
            .sink { [weak self] newValue in
                self?.settings.dictationSelectedPresetKey = newValue
            }
            .store(in: &cancellables)

        // Sync Meeting preset
        $meetingSelectedPresetKey
            .dropFirst()
            .sink { [weak self] newValue in
                self?.settings.meetingSelectedPresetKey = newValue
            }
            .store(in: &cancellables)

        $dictationShortcutDefinition
            .dropFirst()
            .sink { [weak self] newValue in
                self?.handleDictationShortcutDefinitionChange(newValue)
            }
            .store(in: &cancellables)

        $meetingShortcutDefinition
            .dropFirst()
            .sink { [weak self] newValue in
                self?.handleMeetingShortcutDefinitionChange(newValue)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .meetingAssistantShortcutCaptureHealthDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshShortcutCaptureHealthPresentation()
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    /// Resets all keyboard shortcuts to their default values.
    public func resetShortcuts() {
        KeyboardShortcuts.reset(.toggleRecording)
        KeyboardShortcuts.reset(.dictationToggle)
        KeyboardShortcuts.reset(.meetingToggle)
        useEscapeToCancelRecording = false
        selectedPresetKey = .custom
        dictationSelectedPresetKey = .custom
        meetingSelectedPresetKey = .custom
        dictationShortcutDefinition = AppSettingsStore.defaultDictationShortcutDefinition
        dictationModifierConflictMessage = nil
        meetingShortcutDefinition = AppSettingsStore.defaultMeetingShortcutDefinition
        meetingModifierConflictMessage = nil
        isRecordingCustomShortcut = false
    }

    public func openShortcutCaptureHealthAction() {
        guard let presentation = shortcutCaptureHealthPresentation else {
            return
        }

        switch presentation.action {
        case .none:
            return
        case .openAccessibilitySettings:
            AccessibilityPermissionService.openSystemSettings()
        }
    }

    private func refreshShortcutCaptureHealthPresentation() {
        shortcutCaptureHealthPresentation = Self.makeShortcutCaptureHealthPresentation()
    }

    private static func makeShortcutCaptureHealthPresentation() -> ShortcutCaptureHealthPresentation? {
        ShortcutCaptureHealthPresentation.from(
            status: ShortcutCaptureHealthStore.status(for: .global)
        )
    }

    private func handleDictationShortcutDefinitionChange(_ newValue: ShortcutDefinition?) {
        guard !isApplyingShortcutChange else {
            return
        }

        if let newValue,
           ShortcutDefinitionNormalizer.normalized(newValue, allowReturnOrEnter: false) == nil
        {
            isApplyingShortcutChange = true
            dictationShortcutDefinition = settings.dictationShortcutDefinition
            dictationModifierConflictMessage = "settings.shortcuts.modifier.primary_key_required".localized
            isApplyingShortcutChange = false
            return
        }

        guard let normalizedValue = ShortcutDefinitionNormalizer.normalized(
            newValue,
            allowReturnOrEnter: false
        ) else {
            settings.dictationModifierShortcutGesture = nil
            settings.dictationShortcutDefinition = nil
            settings.dictationSelectedPresetKey = .notSpecified
            dictationSelectedPresetKey = .notSpecified
            dictationModifierConflictMessage = nil
            return
        }

        let candidate = ShortcutBinding(
            actionID: .dictation,
            actionDisplayName: "settings.shortcuts.dictation".localized,
            shortcut: normalizedValue
        )

        if let conflict = settings.shortcutConflict(for: candidate) {
            isApplyingShortcutChange = true
            dictationShortcutDefinition = settings.dictationShortcutDefinition
            dictationModifierConflictMessage = conflictMessage(for: conflict)
            isApplyingShortcutChange = false
            return
        }

        settings.dictationShortcutDefinition = normalizedValue
        settings.dictationModifierShortcutGesture = normalizedValue.asModifierShortcutGesture
        settings.dictationSelectedPresetKey = .custom
        dictationSelectedPresetKey = .custom
        dictationModifierConflictMessage = nil
    }

    private func handleMeetingShortcutDefinitionChange(_ newValue: ShortcutDefinition?) {
        guard !isApplyingShortcutChange else {
            return
        }

        if let newValue,
           ShortcutDefinitionNormalizer.normalized(newValue) == nil
        {
            isApplyingShortcutChange = true
            meetingShortcutDefinition = settings.meetingShortcutDefinition
            meetingModifierConflictMessage = "settings.shortcuts.modifier.primary_key_required".localized
            isApplyingShortcutChange = false
            return
        }

        guard let normalizedValue = ShortcutDefinitionNormalizer.normalized(newValue) else {
            settings.meetingModifierShortcutGesture = nil
            settings.meetingShortcutDefinition = nil
            settings.meetingSelectedPresetKey = .notSpecified
            meetingSelectedPresetKey = .notSpecified
            meetingModifierConflictMessage = nil
            return
        }

        let candidate = ShortcutBinding(
            actionID: .meeting,
            actionDisplayName: "settings.shortcuts.meeting".localized,
            shortcut: normalizedValue
        )

        if let conflict = settings.shortcutConflict(for: candidate) {
            isApplyingShortcutChange = true
            meetingShortcutDefinition = settings.meetingShortcutDefinition
            meetingModifierConflictMessage = conflictMessage(for: conflict)
            isApplyingShortcutChange = false
            return
        }

        settings.meetingShortcutDefinition = normalizedValue
        settings.meetingModifierShortcutGesture = normalizedValue.asModifierShortcutGesture
        settings.meetingSelectedPresetKey = .custom
        meetingSelectedPresetKey = .custom
        meetingModifierConflictMessage = nil
    }

    private func conflictMessage(for conflict: ShortcutConflict) -> String {
        switch conflict.reason {
        case .systemReserved:
            "settings.shortcuts.modifier.system_reserved".localized
        case .layerLeaderKeyCollision,
             .identicalSignature,
             .effectiveModifierOverlap,
             .sideSpecificVsAgnosticOverlap,
             .assistantIntegrationConcurrentActivation:
            "settings.shortcuts.modifier.conflict".localized(with: conflict.conflicting.actionDisplayName)
        }
    }
}
