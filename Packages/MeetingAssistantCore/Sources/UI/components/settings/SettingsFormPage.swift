import SwiftUI

/// Owns the single native grouped Form and its vertical scrolling for a settings page.
public struct SettingsFormPage<Header: View, Content: View>: View {
    private let header: Header
    private let content: Content

    public init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header()
        self.content = content()
    }

    public var body: some View {
        GeometryReader { geometry in
            Form {
                header
                content
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(
                minWidth: SettingsFormLayoutPolicy.contentWidth(availableWidth: geometry.size.width),
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

#Preview("Settings Form Page — 600") {
    SettingsFormPage {
        SettingsFormSectionHeader(title: "Preferences", icon: "gearshape.fill")
    } content: {
        Section("Workflow") {
            Picker("Confirmation delay", selection: .constant(6)) {
                Text("6 seconds").tag(6)
                Text("10 seconds").tag(10)
            }
            .pickerStyle(.menu)
            Toggle("Automatically start recording", isOn: .constant(true))
                .toggleStyle(.switch)
        }
        Section("Details") {
            SettingsDrillDownButtonRow(
                title: "Advanced options",
                subtitle: "Configure additional behavior",
                action: {}
            )
            Text("Long help text wraps inside the native section without introducing another card or scroll owner.")
                .foregroundStyle(.secondary)
        }
    }
    .frame(width: 600, height: 360)
}

#Preview("Settings Form Page — 900") {
    SettingsFormPage {
        SettingsFormSectionHeader(title: "Preferences", icon: "gearshape.fill")
    } content: {
        Section("Workflow") {
            Toggle("Automatically start recording", isOn: .constant(true))
                .toggleStyle(.switch)
        }
        Section("Details") {
            Text("A standard-width native grouped Form.")
        }
    }
    .frame(width: 900, height: 300)
}

#Preview("Settings Form Page — 1200 Accessibility") {
    SettingsFormPage {
        SettingsFormSectionHeader(title: "Preferences", icon: "gearshape.fill")
    } content: {
        Section("Workflow") {
            Picker("Confirmation delay", selection: .constant(10)) {
                Text("10 seconds").tag(10)
            }
            Toggle("Automatically start recording", isOn: .constant(false))
                .toggleStyle(.switch)
        }
        Section("Details") {
            Text("Accessibility-sized content remains readable across the full available settings surface.")
        }
    }
    .frame(width: 1200, height: 360)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
    .environment(\.settingsReduceTransparencyPreview, true)
}
