import SwiftUI

/// Synthetic route/state inventory used to inspect Settings surface roles.
///
/// This catalog intentionally renders labels instead of production view models. It
/// keeps visual acceptance local and deterministic while the route-specific previews
/// remain responsible for exercising their real composition.
struct SettingsPreviewEvidenceCatalog: View {
    private struct Family: Identifiable {
        let name: String
        let routes: [String]

        var id: String {
            name
        }
    }

    private static let families = [
        Family(name: "Activity", routes: [
            "root", "history empty", "history populated", "performance",
            "recording detail", "more insights", "event detail"
        ]),
        Family(name: "Dictation", routes: [
            "normal", "long labels/help", "provider loading", "provider error",
            "provider configured"
        ]),
        Family(name: "Modes", routes: [
            "list", "editor", "prompt child", "narrow", "accessibility",
            "reduced effects"
        ]),
        Family(name: "Meetings", routes: [
            "root", "monitoring apps/sites", "export off", "export on",
            "export error", "prompts disabled", "prompts enabled"
        ]),
        Family(name: "Assistant", routes: [
            "disabled", "enabled", "visual feedback variants"
        ]),
        Family(name: "Integrations", routes: [
            "empty", "populated", "editor", "advanced script result"
        ]),
        Family(name: "System", routes: [
            "root", "models empty", "models configured", "models error",
            "dictionary empty", "dictionary populated", "sound default",
            "sound custom", "permissions states", "protected apps empty",
            "protected apps populated"
        ])
    ]

    var body: some View {
        SettingsFormPage {
            SettingsFormSectionHeader(title: "Settings visual evidence", icon: "checkmark.rectangle")
        } content: {
            Section("Surface roles") {
                Label("Window canvas — SettingsWindowBackground", systemImage: "rectangle.dashed")
                Label("Native settings form — SettingsFormPage / Form", systemImage: "list.bullet.rectangle")
                Label("Rich collection — SettingsScrollableContent", systemImage: "rectangle.stack")
                Label("Transient editor — SettingsSidePanel / ModeEditorDrawer", systemImage: "sidebar.trailing")
                Label("Status/recording overlay — recording tokens", systemImage: "record.circle")
                Label("Sidebar chrome — NavigationSplitView / List", systemImage: "sidebar.leading")
            }

            ForEach(Self.families) { family in
                Section(family.name) {
                    ForEach(family.routes, id: \.self) { route in
                        Label(route.capitalized, systemImage: "circle.dotted")
                    }
                }
            }

            Section("Layout acceptance") {
                Toggle("Expanded and enabled state", isOn: .constant(true))
                    .toggleStyle(.checkbox)
                Toggle("Disabled state", isOn: .constant(false))
                    .toggleStyle(.checkbox)
                Text("Long labels and help copy must wrap within the native Form section while retaining one scroll owner and aligned leading and trailing guides.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Deterministic fixtures for surface roles that are not native Form pages.
enum SettingsSurfaceRoleEvidence {
    static var richCollection: some View {
        SettingsScrollableContent {
            Text("Rich collection surface")
                .font(AppTypography.settingsSectionTitle)
            Text("One restrained grouping treatment; no nested page Form.")
                .foregroundStyle(.secondary)
            DSGroup("Collection sample") {
                Label("Row one", systemImage: "doc")
                Label("Row two", systemImage: "doc.fill")
            }
        }
    }

    static var transientEditor: some View {
        VStack(alignment: .leading, spacing: AppDesignSystem.Layout.sectionSpacing) {
            HStack {
                Text("Transient editor")
                    .font(AppTypography.settingsSectionTitle)
                Spacer()
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
            Text("Bounded panel with its own header and footer.")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Done") {}
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppDesignSystem.Layout.cardPadding)
        .frame(width: 320, height: 280)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: AppDesignSystem.Layout.cardCornerRadius, style: .continuous)
        )
    }

    static var sidebarChrome: some View {
        List(selection: .constant("activity")) {
            Label("Activity", systemImage: "chart.bar")
                .tag("activity")
            Label("Modes", systemImage: "slider.horizontal.3")
                .tag("modes")
            Label("Meetings", systemImage: "person.3")
                .tag("meetings")
            Label("History", systemImage: "clock")
                .tag("history")
            Label("Dictionary", systemImage: "character.book.closed")
                .tag("dictionary")
            Label("System", systemImage: "gearshape")
                .tag("system")
        }
        .listStyle(.sidebar)
        .frame(width: 220, height: 360)
    }

    static var recordingOverlay: some View {
        HStack(spacing: AppDesignSystem.Layout.spacing12) {
            Circle()
                .fill(AppDesignSystem.Colors.recording)
                .frame(width: 10, height: 10)
            Text("Recording")
                .font(AppTypography.sidebarLabel)
            Text("00:12")
                .font(AppTypography.indicatorCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppDesignSystem.Layout.spacing16)
        .padding(.vertical, AppDesignSystem.Layout.spacing8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

#Preview("Settings evidence — 600 light") {
    SettingsPreviewEvidenceCatalog()
        .frame(width: 600, height: 640)
}

#Preview("Settings evidence — 900 dark") {
    SettingsPreviewEvidenceCatalog()
        .frame(width: 900, height: 640)
        .preferredColorScheme(.dark)
}

#Preview("Settings evidence — 1200 accessibility") {
    SettingsPreviewEvidenceCatalog()
        .frame(width: 1200, height: 720)
        .environment(\.dynamicTypeSize, .accessibility3)
        .environment(\.settingsReduceTransparencyPreview, true)
        .preferredColorScheme(.dark)
}

#Preview("Surface role — rich collection") {
    SettingsSurfaceRoleEvidence.richCollection
        .frame(width: 600, height: 400)
}

#Preview("Surface role — transient editor") {
    SettingsSurfaceRoleEvidence.transientEditor
        .preferredColorScheme(.dark)
}

#Preview("Surface role — sidebar chrome") {
    SettingsSurfaceRoleEvidence.sidebarChrome
}

#Preview("Surface role — recording overlay") {
    ZStack {
        Color.black.opacity(0.35)
        SettingsSurfaceRoleEvidence.recordingOverlay
    }
    .frame(width: 360, height: 120)
}
