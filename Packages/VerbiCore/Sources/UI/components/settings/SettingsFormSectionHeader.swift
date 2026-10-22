import SwiftUI

/// A native Form Section header with the shared Settings icon and title anatomy.
public struct SettingsFormSectionHeader<Accessory: View>: View {
    private let title: String
    private let icon: String?
    private let accessory: Accessory

    public init(
        title: String,
        icon: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.icon = icon
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(AppDesignSystem.Colors.accent)
                    .accessibilityHidden(true)
            }

            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
            accessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public extension SettingsFormSectionHeader where Accessory == EmptyView {
    init(title: String, icon: String? = nil) {
        self.init(title: title, icon: icon) { EmptyView() }
    }
}

#Preview("Settings Form Section Header") {
    Form {
        Section {
            Text("Native grouped Form content")
        } header: {
            SettingsFormSectionHeader(title: "Workflow", icon: "bolt.fill") {
                Text("Optional")
                    .foregroundStyle(.secondary)
            }
        }
    }
    .formStyle(.grouped)
    .frame(width: 600, height: 180)
}
