import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

// MARK: - Layout Constants

private enum LayoutConstants {
    static let windowWidth: CGFloat = 900
    static let windowHeight: CGFloat = 700
    static let sidebarWidth: CGFloat = 215
}

// MARK: - Settings View

/// Settings view for app configuration.
/// NavigationSplitView with a fixed non-collapsible native sidebar; the
/// AppKit configurator owns the window chrome (unified toolbar, inline pane
/// title, no separator hairline).
public struct SettingsView: View {
    private let updatesView: AnyView?
    private let showsSystemSettingsBadge: Bool
    @State private var selectedSection: SettingsSection = .activity
    @State private var activityNavigationState = ActivitySettingsNavigationState()
    @State private var transcriptionsNavigationHistory = TranscriptionsNavigationHistory()
    @State private var systemRoute: SystemSettingsRoute = .root
    @State private var expandProtectedApps = false
    @State private var navigationService = NavigationService.shared
    @State private var requestedModesSubroute: DictationStyleRoute?

    @MainActor
    public init(updatesView: AnyView? = nil, showsSystemSettingsBadge: Bool = false) {
        self.updatesView = updatesView
        self.showsSystemSettingsBadge = showsSystemSettingsBadge
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SettingsSidebarView(
                selectedSection: Binding(
                    get: { selectedSection },
                    set: { newSection in
                        selectDestination(newSection.destination)
                    }
                ),
                showsSystemSettingsBadge: showsSystemSettingsBadge
            )
            // Fixed sidebar; it is not resizable or collapsible.
            .navigationSplitViewColumnWidth(
                min: LayoutConstants.sidebarWidth,
                ideal: LayoutConstants.sidebarWidth,
                max: LayoutConstants.sidebarWidth
            )
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .background(SettingsWindowConfigurator(title: selectedSection.title))
        .frame(minWidth: LayoutConstants.windowWidth, minHeight: LayoutConstants.windowHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            healSidebarVisibility()
            if let sectionId = navigationService.requestedSettingsSection,
               let destination = SettingsSection.resolvedDestination(for: sectionId)
            {
                selectDestination(destination)
                navigationService.requestedSettingsSection = nil
            }
        }
        .onChange(of: navigationService.requestedSettingsSection) { _, sectionId in
            guard let sectionId else { return }
            if let destination = SettingsSection.resolvedDestination(for: sectionId) {
                selectDestination(destination)
            }
            navigationService.requestedSettingsSection = nil
        }
    }

    private var detailColumn: some View {
        detailView
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private extension SettingsView {
    private func selectDestination(_ destination: SettingsDestination) {
        selectedSection = destination.section
        activityNavigationState.pendingSheet = destination.activityPendingSheet
        expandProtectedApps = destination.expandProtectedApps
        if destination.section == .system {
            systemRoute = destination.systemRoute ?? .root
        }
        if destination.section == .dictionary {
            systemRoute = .root
        }
        if destination.section == .modes || destination.section == .assistant || destination.section == .integrations {
            requestedModesSubroute = destination.modesSubroute
        }
    }

    /// One-time heal: the sidebar is fixed visible, so a persisted hidden
    /// state from before the parity change must not stick.
    private func healSidebarVisibility() {
        AppSettingsStore.shared.isSettingsSidebarVisible = true
        navigationService.setSettingsSidebarVisible(true)
    }

    @MainActor
    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .metrics, .activity:
            ActivitySettingsTab(navigationState: $activityNavigationState)
        case .history, .transcriptions:
            TranscriptionsSettingsTab(navigationHistory: $transcriptionsNavigationHistory)
        case .general:
            GeneralSettingsTab()
        case .models:
            ModelsSettingsTab()
        case .vocabulary, .dictionary:
            DictionarySettingsTab()
        case .dictation, .modes:
            ModesSettingsTab(initialRoute: $requestedModesSubroute)
        case .meetings:
            MeetingSettingsTab()
        case .assistant, .integrations:
            ModesSettingsTab(initialRoute: $requestedModesSubroute)
        case .audio:
            SystemSettingsTab(route: .constant(.sound))
        case .enhancements:
            EnhancementsSettingsTab()
        case .permissions:
            PermissionsSettingsTab()
        case .intelligence:
            SystemSettingsTab(route: .constant(.models))
        case .system, .updates:
            SystemSettingsTab(
                route: $systemRoute,
                expandProtectedApps: $expandProtectedApps,
                updatesView: updatesView,
                showsUpdateAvailable: showsSystemSettingsBadge
            )
        }
    }
}

#Preview("Settings Content") {
    SettingsView()
}
