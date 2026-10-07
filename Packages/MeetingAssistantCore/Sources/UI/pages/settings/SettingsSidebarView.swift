import MeetingAssistantCoreCommon
import SwiftUI

// preview-check: ignore — sidebar preview requires the SettingsPage navigation environment.

struct SettingsSidebarView: View {
    @Binding var selectedSection: SettingsSection
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        sectionsList
    }

    private var sectionsList: some View {
        List(selection: $selectedSection) {
            Section("settings.sidebar.library".localized) {
                ForEach(SettingsSection.librarySections) { section in
                    sidebarRow(for: section)
                        .tag(section)
                }
            }
            Section("settings.sidebar.settings".localized) {
                ForEach(SettingsSection.settingsSections) { section in
                    sidebarRow(for: section)
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func sidebarRow(for section: SettingsSection) -> some View {
        sidebarLabel(for: section)
            .contentShape(Rectangle())
            .accessibilityLabel(sidebarAccessibilityLabel(for: section))
    }

    private func sidebarAccessibilityLabel(for section: SettingsSection) -> String {
        section.title
    }

    private func sidebarLabel(for section: SettingsSection) -> some View {
        HStack(spacing: 8) {
            Image(systemName: sidebarIcon(for: section))
                .font(AppTypography.sidebarIcon)
                .foregroundStyle(.primary)
                .frame(width: 18, alignment: .center)
                .opacity(controlActiveState == .inactive ? 0.55 : 1.0)

            Text(section.title)
                .font(AppTypography.sidebarLabel)
                .lineLimit(1)
        }
        .frame(height: 28)
    }

    private func sidebarIcon(for section: SettingsSection) -> String {
        selectedSection == section ? section.selectedSidebarIcon : section.icon
    }
}
