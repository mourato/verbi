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
    static let windowHeight: CGFloat = 640
    static let sidebarWidth: CGFloat = 220
    /// Clears traffic lights under the transparent titlebar.
    static let titlebarClearance: CGFloat = 40
}

// MARK: - Settings View

/// Settings view for app configuration.
/// Pure NavigationSplitView architecture with native macOS sidebar and detail column.
public struct SettingsView: View {
    private let updatesView: AnyView?
    private let showsSystemSettingsBadge: Bool
    private let settingsStore = AppSettingsStore.shared
    @State private var selectedSection: SettingsSection = .activity
    @State private var activityNavigationState = ActivitySettingsNavigationState()
    @State private var transcriptionsNavigationHistory = TranscriptionsNavigationHistory()
    @State private var systemRoute: SystemSettingsRoute = .root
    @State private var expandProtectedApps = false
    @State private var columnVisibility: NavigationSplitViewVisibility
    @State private var navigationService = NavigationService.shared
    @State private var requestedModesSubroute: DictationStyleRoute?

    @MainActor
    public init(updatesView: AnyView? = nil, showsSystemSettingsBadge: Bool = false) {
        self.updatesView = updatesView
        self.showsSystemSettingsBadge = showsSystemSettingsBadge
        _columnVisibility = State(
            initialValue: AppSettingsStore.shared.isSettingsSidebarVisible ? .all : .detailOnly,
        )
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SettingsSidebarView(
                selectedSection: Binding(
                    get: { selectedSection },
                    set: { newSection in
                        selectDestination(newSection.destination)
                    },
                ),
                showsSystemSettingsBadge: showsSystemSettingsBadge,
            )
            // Manual traffic-light clearance; columns ignore the titlebar safe area.
            .padding(.top, LayoutConstants.titlebarClearance)
            .ignoresSafeArea(.container, edges: .top)
            .navigationSplitViewColumnWidth(min: 200, ideal: LayoutConstants.sidebarWidth, max: 280)
        } detail: {
            detailColumn
                .ignoresSafeArea(.container, edges: .top)
        }
        .navigationSplitViewStyle(.balanced)
        // Drop the native toolbar band; collapsed chrome owns the sidebar toggle.
        .toolbar(removing: .sidebarToggle)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(SettingsWindowConfigurator())
        .frame(minWidth: LayoutConstants.windowWidth, minHeight: LayoutConstants.windowHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            syncSidebarVisibilityFromStore()
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
        .onChange(of: navigationService.settingsSidebarToggleRequestID) { _, _ in
            toggleSidebar()
        }
        .onChange(of: columnVisibility) { _, next in
            persistSidebarVisibility(next != .detailOnly)
        }
    }

    private var detailColumn: some View {
        ZStack(alignment: .topLeading) {
            AppDesignSystem.Colors.settingsCanvasBackground

            VStack(spacing: 0) {
                if columnVisibility == .detailOnly {
                    collapsedSidebarChrome
                }

                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Inset for the sidebar toggle when sidebar is collapsed.
    private var collapsedSidebarChrome: some View {
        HStack(spacing: 12) {
            sidebarToggleButton
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, LayoutConstants.titlebarClearance)
        .padding(.bottom, 10)
    }

    private var sidebarToggleButton: some View {
        Button(action: toggleSidebar) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(sidebarToggleHelpText)
        .accessibilityLabel(sidebarToggleHelpText)
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

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            let next: NavigationSplitViewVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            columnVisibility = next
            persistSidebarVisibility(next != .detailOnly)
        }
    }

    private func syncSidebarVisibilityFromStore() {
        let visible = settingsStore.isSettingsSidebarVisible
        columnVisibility = visible ? .all : .detailOnly
        navigationService.setSettingsSidebarVisible(visible)
    }

    private func persistSidebarVisibility(_ isVisible: Bool) {
        settingsStore.isSettingsSidebarVisible = isVisible
        navigationService.setSettingsSidebarVisible(isVisible)
    }

    private var sidebarToggleHelpText: String {
        let key = columnVisibility != .detailOnly
            ? "commands.view.hide_sidebar"
            : "commands.view.show_sidebar"
        return key.localized
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
                showsUpdateAvailable: showsSystemSettingsBadge,
            )
        }
    }

}

#Preview("Settings Content") {
    SettingsView()
}
