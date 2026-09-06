import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

// MARK: - Permissions Settings Tab

/// Tab for managing app permissions (microphone, screen recording).
public struct PermissionsSettingsTab: View {
    private let showsHeader: Bool

    public init(showsHeader: Bool = true) {
        self.showsHeader = showsHeader
    }

    public var body: some View {
        SettingsFormPage {
            VStack(alignment: .leading, spacing: 4) {
                SettingsFormSectionHeader(title: "settings.section.permissions".localized, icon: "checkmark.shield")
                if showsHeader {
                    Text("settings.permissions.description".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } content: {
            PermissionsSettingsContent()
        }
    }
}

/// Reusable permissions Form sections for General and standalone tabs.
public struct PermissionsSettingsContent: View {
    @StateObject private var viewModel: PermissionViewModel
    @StateObject private var shortcutSettingsViewModel = ShortcutSettingsViewModel()
    @StateObject private var assistantShortcutSettingsViewModel = AssistantShortcutSettingsViewModel()

    public init() {
        let recordingManager = RecordingManager.shared
        _viewModel = StateObject(wrappedValue: PermissionViewModel(
            manager: recordingManager.permissionStatus,
            requestMicrophone: { await recordingManager.requestPermission(for: .microphone) },
            requestScreen: { await recordingManager.requestPermission(for: .system) },
            openMicrophoneSettings: { recordingManager.openMicrophoneSettings() },
            openScreenSettings: { recordingManager.openPermissionSettings() },
            requestAccessibility: { recordingManager.requestAccessibilityPermission() },
            openAccessibilitySettings: { recordingManager.openAccessibilitySettings() },
        ))
    }

    public var body: some View {
        Group {
            Section {
                PermissionStatusView(viewModel: viewModel, requiredSource: .all)
                    .padding(.top, 4)
            } header: {
                SettingsFormSectionHeader(title: "settings.permissions.status".localized, icon: "checkmark.shield")
            }

            if shortcutSettingsViewModel.shortcutCaptureHealthPresentation != nil ||
                assistantShortcutSettingsViewModel.shortcutCaptureHealthPresentation != nil
            {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        if let globalPresentation = shortcutSettingsViewModel.shortcutCaptureHealthPresentation {
                            ShortcutCaptureHealthStatusView(presentation: globalPresentation) {
                                shortcutSettingsViewModel.openShortcutCaptureHealthAction()
                            }
                        }

                        if let assistantPresentation = assistantShortcutSettingsViewModel.shortcutCaptureHealthPresentation {
                            ShortcutCaptureHealthStatusView(presentation: assistantPresentation) {
                                assistantShortcutSettingsViewModel.openShortcutCaptureHealthAction()
                            }
                        }
                    }
                } header: {
                    SettingsFormSectionHeader(title: "settings.shortcuts.health.title".localized, icon: "keyboard")
                }
            }

            if !viewModel.allPermissionsGranted {
                Section {
                    SettingsStateBlock(
                        kind: .warning,
                        title: "permissions.action_required".localized,
                        message: "permissions.warning".localized,
                        actionTitle: "permissions.configure".localized,
                    ) {
                        viewModel.openScreenSystemSettings()
                    }
                }
            }
        }
        .task {
            await RecordingManager.shared.checkPermission()
        }
    }
}

#Preview {
    PermissionsSettingsTab()
}
