import AppKit
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

// MARK: - Meeting Settings Tab

/// Tab for meeting-specific settings like app monitoring and automation.
public struct MeetingSettingsTab: View {
    private enum CapabilityLayout {
        static let disabledOpacity = 0.58
    }

    @StateObject var meetingViewModel: MeetingSettingsViewModel
    @StateObject private var shortcutsViewModel = ShortcutSettingsViewModel()
    @StateObject private var serviceViewModel: ServiceSettingsViewModel
    @StateObject private var aiSettingsViewModel: AISettingsViewModel
    @StateObject private var monitoredAppsViewModel: InstalledAppsSelectionViewModel
    @StateObject var webTargetsViewModel: WebMeetingTargetsViewModel
    private let settings: AppSettingsStore
    @State private var showSummaryTemplateEditor = false
    @State private var showMonitoredAppSearchSheet = false
    @State var selectedWebTargetID: UUID?
    @State private var isMonitoringExpanded = false
    @State private var isExportExpanded = false
    @State private var showMeetingPromptsPanel = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(settings: AppSettingsStore = .shared) {
        _meetingViewModel = StateObject(wrappedValue: MeetingSettingsViewModel(settings: settings))
        _serviceViewModel = StateObject(wrappedValue: ServiceSettingsViewModel(settings: settings))
        _aiSettingsViewModel = StateObject(wrappedValue: AISettingsViewModel(settings: settings))
        _monitoredAppsViewModel = StateObject(
            wrappedValue: InstalledAppsSelectionViewModel(
                defaultBundleIdentifiers: AppSettingsStore.defaultMonitoredMeetingBundleIdentifiers,
                hasConfigured: { settings.hasConfiguredMonitoredMeetingApps },
                loadBundleIdentifiers: { settings.monitoredMeetingBundleIdentifiers },
                saveBundleIdentifiers: { settings.monitoredMeetingBundleIdentifiers = $0 },
            ),
        )
        _webTargetsViewModel = StateObject(wrappedValue: WebMeetingTargetsViewModel(settings: settings))
        self.settings = settings
    }

    public var body: some View {
        mainPage
            .settingsSidePanel(
                isPresented: showMeetingPromptsPanel,
                onDismiss: dismissMeetingPromptsPanel,
            ) {
                MeetingPromptsSettingsContent(
                    meetingViewModel: meetingViewModel,
                    onClose: dismissMeetingPromptsPanel,
                )
            }
            .sheet(isPresented: $meetingViewModel.showPromptEditor) {
                PromptEditorSheet(
                    prompt: meetingViewModel.editingPrompt,
                    onSave: meetingViewModel.handleSavePrompt,
                    onCancel: { meetingViewModel.showPromptEditor = false },
                )
            }
            .sheet(isPresented: $showSummaryTemplateEditor) {
                SummaryTemplateEditorSheet(
                    initialTemplate: meetingViewModel.settings.summaryTemplate,
                    onSave: { updatedTemplate in
                        meetingViewModel.settings.summaryTemplate = updatedTemplate
                        showSummaryTemplateEditor = false
                    },
                    onCancel: { showSummaryTemplateEditor = false },
                )
            }
            .alert("settings.post_processing.delete_confirm_title".localized, isPresented: $meetingViewModel.showDeleteConfirmation) {
                Button("common.cancel".localized, role: .cancel) {}
                Button("common.delete".localized, role: .destructive) {
                    meetingViewModel.executeDelete()
                }
            } message: {
                if let prompt = meetingViewModel.promptToDelete {
                    Text("settings.post_processing.delete_confirm_message".localized(with: prompt.title))
                }
            }
            .onDeleteCommand(perform: deleteSelectedWebTarget)
            .sheet(isPresented: $webTargetsViewModel.showEditor) {
                WebMeetingTargetEditorSheet(
                    target: webTargetsViewModel.editingTarget,
                    onSave: webTargetsViewModel.handleSave,
                    onCancel: { webTargetsViewModel.showEditor = false },
                )
            }
            .sheet(isPresented: $showMonitoredAppSearchSheet) {
                AppSearchSheet(
                    viewModel: monitoredAppsViewModel,
                    isPresented: $showMonitoredAppSearchSheet,
                    titleKey: "settings.general.monitored_apps",
                    descriptionKey: "settings.general.monitored_apps_desc",
                    addButtonKey: "settings.general.monitored_apps_add",
                )
            }
            .alert("settings.meetings.web_targets.delete_confirm_title".localized, isPresented: $webTargetsViewModel.showDeleteConfirmation) {
                Button("common.cancel".localized, role: .cancel) {}
                Button("common.delete".localized, role: .destructive) {
                    webTargetsViewModel.executeDelete()
                }
            } message: {
                if let target = webTargetsViewModel.targetToDelete {
                    Text("settings.meetings.web_targets.delete_confirm_message".localized(with: target.displayName))
                }
            }
            .onAppear {
                if meetingViewModel.settings.autoExportSummaries {
                    isExportExpanded = true
                }
            }
            .onChange(of: meetingViewModel.isMeetingPostProcessingEnabled) { _, isEnabled in
                if !isEnabled {
                    dismissMeetingPromptsPanel()
                }
            }
    }

    private var mainPage: some View {
        SettingsFormPage {
            VStack(alignment: .leading, spacing: 8) {
                SettingsFormSectionHeader(title: "settings.section.meetings".localized, icon: "person.2.fill")
                Text("settings.meetings.description".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SettingsCapabilityHeaderToggle(
                    titleKey: "settings.capabilities.meeting_transcription",
                    isOn: $meetingViewModel.settings.isMeetingTranscriptionEnabled,
                )
            }
        } content: {
            Group {
                ShortcutSettingsSection(
                    groupTitle: "settings.shortcuts.meeting".localized,
                    descriptionText: "settings.shortcuts.meeting_desc".localized,
                    settingsContent: {
                        HStack(alignment: .center, spacing: 12) {
                            if let healthPresentation = shortcutsViewModel.shortcutCaptureHealthPresentation {
                                ShortcutCaptureHealthStatusView(presentation: healthPresentation) {
                                    shortcutsViewModel.openShortcutCaptureHealthAction()
                                }
                            }

                            DSModifierShortcutEditor(
                                shortcut: $shortcutsViewModel.meetingShortcutDefinition,
                                conflictMessage: shortcutsViewModel.meetingModifierConflictMessage,
                            )
                        }
                    },
                )

                Section {
                    Toggle("settings.general.auto_start".localized, isOn: $meetingViewModel.settings.autoStartRecording)
                        .toggleStyle(.switch)
                    Picker(
                        "settings.general.auto_start_confirmation_delay".localized,
                        selection: $meetingViewModel.settings.automaticAutomaticMeetingRecordingConfirmationDelay,
                    ) {
                        ForEach(AppSettingsStore.AutomaticMeetingRecordingConfirmationDelay.allCases, id: \.self) { delay in
                            Text(delay.localizedTitle).tag(delay)
                        }
                    }
                    .pickerStyle(.menu)
                    SettingsExpandableSection(
                        title: "settings.meetings.monitoring_access.button".localized,
                        subtitle: "settings.meetings.monitoring_access.desc".localized,
                        accessibilityHint: "settings.meetings.monitoring_access.expand_accessibility_hint".localized,
                        isExpanded: $isMonitoringExpanded,
                    ) {
                        monitoringTargetsContent
                    }
                    Toggle("settings.general.merge_audio".localized, isOn: $meetingViewModel.settings.shouldMergeAudioFiles)
                        .toggleStyle(.switch)
                    SettingsExpandableSection(
                        title: "settings.meetings.export".localized,
                        subtitle: "settings.meetings.export_drilldown_desc".localized,
                        accessibilityHint: "settings.meetings.export.expand_accessibility_hint".localized,
                        isExpanded: $isExportExpanded,
                    ) {
                        exportSectionContent
                    }
                } header: {
                    SettingsFormSectionHeader(title: "settings.meetings.workflow".localized, icon: "bolt.fill")
                }

                ServiceMeetingTranscriptionSection(viewModel: serviceViewModel)
                meetingIntelligenceSection

                Section {
                    SpeakerIdentificationSettingsSection(settings: meetingViewModel.settings)
                } header: {
                    SettingsFormSectionHeader(title: "settings.meetings.speaker_identification".localized, icon: "person.wave.2.fill")
                }

                MeetingNotesPanelSettingsSection(settings: meetingViewModel.settings)
            }
            .disabled(!meetingViewModel.settings.isMeetingTranscriptionEnabled)
            .opacity(meetingViewModel.settings.isMeetingTranscriptionEnabled ? 1 : CapabilityLayout.disabledOpacity)
            .animation(
                SettingsMotion.sectionAnimation(reduceMotion: reduceMotion),
                value: meetingViewModel.settings.isMeetingTranscriptionEnabled,
            )

            meetingRemindersSection
        }
    }

    private var meetingRemindersSection: some View {
        MeetingSettingsRemindersSection(settings: meetingViewModel.settings)
    }

    private var meetingIntelligenceSection: some View {
        Section {
            Toggle("settings.meetings.post_processing_enabled".localized, isOn: meetingPostProcessingBinding)
                .toggleStyle(.switch)

            EnhancementsModelSelectionControl(
                target: .meeting,
                viewModel: aiSettingsViewModel,
                settings: settings,
            )

            Toggle("transcription.qa.title".localized, isOn: $meetingViewModel.settings.meetingQnAEnabled)
                .toggleStyle(.switch)

            HStack(alignment: .center, spacing: 12) {
                SettingsTitleWithPopover(
                    title: "settings.meetings.prompts".localized,
                    helperMessage: "settings.meetings.prompts_drilldown_desc".localized,
                )

                Spacer(minLength: 8)

                Button("common.configure".localized) {
                    openMeetingPromptsPanel()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .accessibilityHint("settings.meetings.prompts.configure_accessibility_hint".localized)
            }
            .disabled(!meetingViewModel.isMeetingPostProcessingEnabled)
            .opacity(meetingViewModel.isMeetingPostProcessingEnabled ? 1 : CapabilityLayout.disabledOpacity)
        } header: {
            SettingsFormSectionHeader(title: "settings.enhancements.meeting_intelligence_model".localized, icon: "bubble.left.and.bubble.right.fill")
        }
    }

    private var monitoringTargetsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstalledAppsSelectionSection(
                titleKey: "settings.general.monitored_apps",
                descriptionKey: "settings.general.monitored_apps_desc",
                emptyKey: "settings.general.monitored_apps_empty",
                addButtonKey: "settings.general.monitored_apps_add",
                icon: "app.badge",
                onAddApp: { showMonitoredAppSearchSheet = true },
                viewModel: monitoredAppsViewModel,
            )

            webTargetsSection
        }
    }

    private var exportSectionContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $meetingViewModel.settings.autoExportSummaries) {
                VStack(alignment: .leading) {
                    Text("settings.meetings.auto_export".localized)
                    Text("settings.meetings.auto_export_desc".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            if meetingViewModel.settings.autoExportSummaries {
                Divider()
                    .padding(.vertical, 8)

                HStack {
                    SettingsTitleWithPopover(
                        title: "settings.meetings.export_location".localized,
                        helperMessage: "settings.meetings.export_location_desc".localized,
                    )
                    Spacer()
                    if let url = meetingViewModel.settings.summaryExportFolder {
                        Text(url.lastPathComponent)
                            .foregroundStyle(.secondary)
                            .truncationMode(.middle)
                    } else {
                        Text("settings.meetings.no_folder_selected".localized)
                            .foregroundStyle(.secondary)
                    }
                    Button("common.select".localized) {
                        meetingViewModel.selectExportFolder()
                    }
                }

                Divider()
                    .padding(.vertical, 8)

                Toggle(isOn: $meetingViewModel.settings.summaryTemplateEnabled) {
                    VStack(alignment: .leading) {
                        Text("settings.meetings.template_enabled".localized)
                        Text("settings.meetings.template_enabled_desc".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Divider()
                    .padding(.vertical, 8)

                Picker(
                    "settings.meetings.export_safety_policy".localized,
                    selection: $meetingViewModel.settings.summaryExportSafetyPolicyLevel,
                ) {
                    ForEach(SummaryExportSafetyPolicyLevel.allCases, id: \.self) { level in
                        Text(exportSafetyPolicyLabel(level)).tag(level)
                    }
                }
                .pickerStyle(.menu)

                if meetingViewModel.settings.summaryExportFolder == nil {
                    Text("settings.meetings.export_location_required".localized)
                        .font(.caption)
                        .foregroundStyle(AppDesignSystem.Colors.error)
                }

                if meetingViewModel.settings.summaryTemplateEnabled {
                    Divider()
                        .padding(.vertical, 8)

                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(AppDesignSystem.Colors.iconHighlight)
                            SettingsTitleWithPopover(
                                title: "settings.meetings.template".localized,
                                helperMessage: "settings.meetings.template_desc".localized,
                                font: .subheadline,
                                fontWeight: .semibold,
                            )
                        }

                        Spacer()

                        Button {
                            showSummaryTemplateEditor = true
                        } label: {
                            Label("settings.meetings.template.edit".localized, systemImage: "pencil")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                }
            }
        }
    }

    private var meetingPostProcessingBinding: Binding<Bool> {
        Binding(
            get: { meetingViewModel.isMeetingPostProcessingEnabled },
            set: { meetingViewModel.setMeetingPostProcessingEnabled($0) },
        )
    }

    private func exportSafetyPolicyLabel(_ level: SummaryExportSafetyPolicyLevel) -> String {
        switch level {
        case .permissive:
            "settings.meetings.export_safety_policy.permissive".localized
        case .standard:
            "settings.meetings.export_safety_policy.standard".localized
        case .strict:
            "settings.meetings.export_safety_policy.strict".localized
        }
    }

    private func openMeetingPromptsPanel() {
        withAnimation(SettingsMotion.sidePanelAnimation(reduceMotion: reduceMotion)) {
            showMeetingPromptsPanel = true
        }
    }

    private func dismissMeetingPromptsPanel() {
        withAnimation(SettingsMotion.sidePanelAnimation(reduceMotion: reduceMotion)) {
            showMeetingPromptsPanel = false
        }
    }
}

#Preview {
    MeetingSettingsTab()
}
