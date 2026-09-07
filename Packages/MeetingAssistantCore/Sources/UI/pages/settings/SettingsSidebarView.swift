import MeetingAssistantCoreCommon
import SwiftUI

// preview-check: ignore — sidebar preview requires the SettingsPage navigation environment.

struct SettingsSidebarView: View {
    @Binding var selectedSection: SettingsSection
    let showsSystemSettingsBadge: Bool
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        sectionsList
            .padding(.top, 8)
    }

    private var sectionsList: some View {
        List(selection: $selectedSection) {
            Section {
                ForEach(SettingsSection.primarySections) { section in
                    sidebarRow(for: section)
                        .tag(section)
                }
            }

            Section {
                sidebarRow(for: SettingsSection.system)
                    .tag(SettingsSection.system)
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
        guard section == .system, showsSystemSettingsBadge else {
            return section.title
        }
        return "\(section.title), \("settings.system.update_available".localized)"
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

            if section == .system, showsSystemSettingsBadge {
                Spacer(minLength: 0)
                Circle()
                    .fill(AppDesignSystem.Colors.accent)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 28)
    }

    private func sidebarIcon(for section: SettingsSection) -> String {
        selectedSection == section ? section.selectedSidebarIcon : section.icon
    }
}
