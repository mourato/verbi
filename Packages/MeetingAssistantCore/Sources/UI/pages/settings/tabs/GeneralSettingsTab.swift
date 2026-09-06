import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

// MARK: - General Settings Tab

/// Main tab for core application settings like language, appearance, and storage.
public struct GeneralSettingsTab: View {
    @State private var viewModel = GeneralSettingsViewModel()
    @StateObject private var recordingCancelShortcutViewModel = RecordingCancelShortcutSettingsViewModel()
    @StateObject private var shortcutSettingsViewModel = ShortcutSettingsViewModel()
    @State private var shortcutDoubleTapIntervalInput = ""
    @State private var isProtectedAppsExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let showsHeader: Bool
    private let headerTitleKey: String
    private let headerDescriptionKey: String
    private let openModels: (() -> Void)?
    private let openSound: (() -> Void)?
    private let openUpdates: (() -> Void)?
    private let showsUpdateAvailable: Bool
    @Binding private var expandProtectedApps: Bool

    public init(
        showsHeader: Bool = true,
        headerTitleKey: String = "settings.general.title",
        headerDescriptionKey: String = "settings.general.language_desc",
        openModels: (() -> Void)? = nil,
        openSound: (() -> Void)? = nil,
        expandProtectedApps: Binding<Bool> = .constant(false),
        openUpdates: (() -> Void)? = nil,
        showsUpdateAvailable: Bool = false,
    ) {
        self.showsHeader = showsHeader
        self.headerTitleKey = headerTitleKey
        self.headerDescriptionKey = headerDescriptionKey
        self.openModels = openModels
        self.openSound = openSound
        self.openUpdates = openUpdates
        self.showsUpdateAvailable = showsUpdateAvailable
        _expandProtectedApps = expandProtectedApps
    }

    public var body: some View {
        SettingsFormPage {
            VStack(alignment: .leading, spacing: 4) {
                SettingsFormSectionHeader(title: headerTitleKey.localized, icon: "gearshape.2")
                if showsHeader {
                    Text(headerDescriptionKey.localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } content: {
            ShortcutSettingsSection(
                groupTitle: "settings.shortcuts.dictation".localized,
                descriptionText: "settings.shortcuts.dictation_desc".localized,
                settingsContent: {
                    VStack(alignment: .leading, spacing: 12) {
                        if let healthPresentation = shortcutSettingsViewModel.shortcutCaptureHealthPresentation {
                            ShortcutCaptureHealthStatusView(presentation: healthPresentation) {
                                shortcutSettingsViewModel.openShortcutCaptureHealthAction()
                            }
                        }

                        DSModifierShortcutEditor(
                            shortcut: $shortcutSettingsViewModel.dictationShortcutDefinition,
                            conflictMessage: shortcutSettingsViewModel.dictationModifierConflictMessage,
                        )
                    }
                },
            )

            systemDrilldownsSection

            Section {
                Toggle("settings.general.launch_at_login".localized, isOn: $viewModel.launchAtLogin)
                    .toggleStyle(.switch)
                Toggle(isOn: $viewModel.showInDock) {
                    LabeledContent("settings.general.show_in_dock".localized) {
                        Text("settings.general.show_in_dock_desc".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                Toggle("settings.general.show_settings_on_launch".localized, isOn: $viewModel.showSettingsOnLaunch)
                    .toggleStyle(.switch)

                HStack(alignment: .center, spacing: 12) {
                    SettingsTitleWithPopover(
                        title: "settings.general.shortcut_double_tap_interval".localized,
                        helperMessage: "settings.general.shortcut_double_tap_interval_desc".localized,
                    )

                    Spacer()

                    HStack(spacing: 8) {
                        TextField("", text: $shortcutDoubleTapIntervalInput)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 84)
                            .onChange(of: shortcutDoubleTapIntervalInput) { _, newValue in
                                applyShortcutDoubleTapIntervalInput(newValue)
                            }
                            .onSubmit {
                                syncShortcutDoubleTapIntervalInputFromModel()
                            }

                        Text("ms")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    SettingsTitleWithPopover(
                        title: "settings.general.cancel_recording_shortcut".localized,
                        helperMessage: "settings.general.cancel_recording_shortcut_desc".localized,
                    )

                    Spacer()

                    DSModifierShortcutEditor(
                        shortcut: $recordingCancelShortcutViewModel.cancelRecordingShortcutDefinition,
                        conflictMessage: recordingCancelShortcutViewModel.cancelRecordingShortcutConflictMessage,
                        showsTitle: false,
                        maxInputWidth: AppDesignSystem.Layout.maxCompactTextFieldWidth,
                    )
                }
            } header: {
                SettingsFormSectionHeader(title: "settings.general.app_behavior".localized, icon: "app.badge")
            }

            Section {
                Picker("settings.general.language".localized, selection: $viewModel.selectedLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: AppDesignSystem.Layout.spacing8) {
                    Text("settings.general.appearance.theme".localized)
                        .font(.body)

                    DSAppearanceModePicker(selection: $viewModel.appearanceMode)
                }
            } header: {
                SettingsFormSectionHeader(title: "settings.general.appearance".localized, icon: "paintbrush.fill")
            }

            recordingIndicatorSection

            storageSection

            softwareUpdatesSection

            if openModels != nil {
                PermissionsSettingsContent()

                Section {
                    SettingsExpandableSection(
                        title: "settings.context_awareness.protect_sensitive_apps".localized,
                        subtitle: "settings.context_awareness.protect_sensitive_apps_desc".localized,
                        isExpanded: $isProtectedAppsExpanded,
                    ) {
                        ProtectedAppsSettingsContent()
                    }
                }
            }
        }
        .onChange(of: expandProtectedApps) { _, shouldExpand in
            guard shouldExpand else { return }
            isProtectedAppsExpanded = true
            expandProtectedApps = false
        }
        .onAppear {
            if expandProtectedApps {
                isProtectedAppsExpanded = true
                expandProtectedApps = false
            }
        }
        .confirmationDialog(
            "settings.storage.cleanup_confirm_title".localized,
            isPresented: $viewModel.showCleanupConfirmationDialog,
            titleVisibility: .visible,
        ) {
            Button("settings.storage.cleanup_confirm_delete".localized, role: .destructive) {
                viewModel.confirmCleanup()
            }
            Button("settings.storage.cleanup_confirm_cancel".localized, role: .cancel) {}
        } message: {
            Text(viewModel.cleanupConfirmationMessage)
        }
        .alert("settings.general.storage".localized, isPresented: $viewModel.showCleanupSuccessAlert) {
            Button("common.ok".localized, role: .cancel) {}
        } message: {
            Text("settings.storage.cleanup_success".localized)
        }
        .alert("common.error".localized, isPresented: Binding(
            get: { viewModel.cleanupError != nil },
            set: {
                if !$0 {
                    viewModel.cleanupError = nil
                }
            },
        )) {
            Button("common.ok".localized, role: .cancel) {}
        } message: {
            if let error = viewModel.cleanupError {
                Text(error)
            }
        }
        .alert("settings.general.launch_at_login.error_title".localized, isPresented: Binding(
            get: { viewModel.launchAtLoginError != nil },
            set: {
                if !$0 {
                    viewModel.dismissLaunchAtLoginError()
                }
            },
        )) {
            Button("settings.general.launch_at_login.retry".localized) {
                viewModel.retryLaunchAtLogin()
            }
            Button("common.ok".localized, role: .cancel) {
                viewModel.dismissLaunchAtLoginError()
            }
        } message: {
            if let error = viewModel.launchAtLoginError {
                Text(error.messageKey.localized)
            }
        }
        .onAppear {
            syncShortcutDoubleTapIntervalInputFromModel()
            normalizeStorageRetentionSelection()
        }
    }

    @ViewBuilder
    private var systemDrilldownsSection: some View {
        if let openModels, let openSound {
            Section {
                SettingsListDrillDownButtonRow(
                    title: "settings.section.models".localized,
                    subtitle: "settings.models.description".localized,
                    accessibilityHint: "settings.section.models".localized,
                    action: openModels,
                )

                SettingsListDrillDownButtonRow(
                    title: "settings.section.audio".localized,
                    subtitle: "settings.general.audio_devices_desc".localized,
                    accessibilityHint: "settings.section.audio".localized,
                    action: openSound,
                )
            } header: {
                SettingsFormSectionHeader(title: "settings.section.settings".localized, icon: "gearshape.2")
            }
        }
    }

    private var recordingIndicatorSection: some View {
        Section {
            Toggle(
                "settings.general.recording_indicator.enabled".localized,
                isOn: $viewModel.recordingIndicatorEnabled.animated(),
            )
            .toggleStyle(.switch)

            if viewModel.recordingIndicatorEnabled {
                Picker("settings.general.recording_indicator.style".localized, selection: $viewModel.recordingIndicatorStyle) {
                    ForEach(RecordingIndicatorStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)

                Picker("settings.general.recording_indicator.position".localized, selection: $viewModel.recordingIndicatorPosition) {
                    ForEach(RecordingIndicatorPosition.allCases, id: \.self) { pos in
                        Text(pos.displayName).tag(pos)
                    }
                }
                .pickerStyle(.segmented)

                Picker("settings.general.recording_indicator.animation_speed".localized, selection: $viewModel.recordingIndicatorAnimationSpeed) {
                    ForEach(RecordingIndicatorAnimationSpeed.allCases, id: \.self) { speed in
                        Text(speed.displayName).tag(speed)
                    }
                }
                .pickerStyle(.menu)
            }
        } header: {
            SettingsFormSectionHeader(title: "settings.general.recording_indicator".localized, icon: "record.circle")
        }
    }

    @ViewBuilder
    private var softwareUpdatesSection: some View {
        if let openUpdates {
            Section {
                LabeledContent("settings.system.version".localized) {
                    Text(AppVersion.full)
                        .foregroundStyle(.secondary)
                }

                SettingsListDrillDownButtonRow(
                    title: showsUpdateAvailable
                        ? "settings.system.update_available".localized
                        : "settings.system.open_updates".localized,
                    subtitle: "settings.updates.description".localized,
                    accessibilityHint: "settings.system.open_updates_hint".localized,
                    action: openUpdates,
                )
            } header: {
                SettingsFormSectionHeader(title: "settings.updates.title".localized, icon: "arrow.down.circle")
            }
        }
    }

    private var storageSection: some View {
        Section {
            Picker("settings.general.auto_delete".localized, selection: storageRetentionBinding) {
                ForEach(StorageRetentionOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Button {
                    viewModel.performCleanup()
                } label: {
                    Text(cleanupNowTitle)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.autoDeleteTranscriptions || viewModel.cleanupInProgress)

                Spacer()
            }
        } header: {
            SettingsFormSectionHeader(title: "settings.general.storage".localized, icon: "folder.fill")
        }
    }

    private var storageRetentionBinding: Binding<StorageRetentionOption> {
        Binding(
            get: {
                StorageRetentionOption(
                    autoDeleteEnabled: viewModel.autoDeleteTranscriptions,
                    days: viewModel.autoDeletePeriodDays,
                )
            },
            set: { option in
                viewModel.autoDeleteTranscriptions = option.days != nil
                if let days = option.days {
                    viewModel.autoDeletePeriodDays = days
                }
            },
        )
    }

    private var cleanupNowTitle: String {
        guard viewModel.autoDeleteTranscriptions else {
            return "settings.storage.cleanup_now_disabled".localized
        }

        return String(
            format: "settings.storage.cleanup_now".localized,
            viewModel.autoDeletePeriodDays,
        )
    }

    private func applyShortcutDoubleTapIntervalInput(_ rawValue: String) {
        let digitsOnly = rawValue.filter(\.isNumber)
        if digitsOnly != rawValue {
            shortcutDoubleTapIntervalInput = digitsOnly
            return
        }

        guard !digitsOnly.isEmpty, let value = Double(digitsOnly) else { return }
        let validRange = AppSettingsStore.shortcutDoubleTapIntervalRangeMilliseconds
        let clampedValue = min(max(value, validRange.lowerBound), validRange.upperBound)

        viewModel.shortcutDoubleTapIntervalMilliseconds = clampedValue
        let normalizedValue = "\(Int(clampedValue))"
        if shortcutDoubleTapIntervalInput != normalizedValue {
            shortcutDoubleTapIntervalInput = normalizedValue
        }
    }

    private func syncShortcutDoubleTapIntervalInputFromModel() {
        shortcutDoubleTapIntervalInput = "\(Int(viewModel.shortcutDoubleTapIntervalMilliseconds))"
    }

    private func normalizeStorageRetentionSelection() {
        guard viewModel.autoDeleteTranscriptions else { return }
        guard StorageRetentionOption.supports(days: viewModel.autoDeletePeriodDays) else {
            viewModel.autoDeletePeriodDays = StorageRetentionOption.oneMonth.rawValue
            return
        }
    }
}

private enum StorageRetentionOption: Int, CaseIterable, Identifiable {
    case oneWeek = 7
    case twoWeeks = 14
    case oneMonth = 30
    case threeMonths = 90
    case sixMonths = 180
    case disabled = 0

    var id: Int {
        rawValue
    }

    init(autoDeleteEnabled: Bool, days: Int) {
        guard autoDeleteEnabled else {
            self = .disabled
            return
        }

        self = Self.allCases.first { $0.days == days } ?? .oneMonth
    }

    static func supports(days: Int) -> Bool {
        allCases.contains { $0.days == days }
    }

    var days: Int? {
        self == .disabled ? nil : rawValue
    }

    var title: String {
        switch self {
        case .oneWeek:
            "settings.storage.retention.one_week".localized
        case .twoWeeks:
            "settings.storage.retention.two_weeks".localized
        case .oneMonth:
            "settings.storage.retention.one_month".localized
        case .threeMonths:
            "settings.storage.retention.three_months".localized
        case .sixMonths:
            "settings.storage.retention.six_months".localized
        case .disabled:
            "settings.storage.retention.disabled".localized
        }
    }
}

#Preview {
    GeneralSettingsTab()
}
