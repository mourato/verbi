import SwiftUI

/// Card-backed surface for composed settings content such as collections,
/// analytics, editors, callouts, and dense status blocks.
///
/// Ordinary scalar settings belong in the owning page's native `Form` and
/// `Section`; use this group only when the content's semantics need a richer
/// surface than a settings row. Default surface intensity is `.subtle` so the
/// group does not compete with `SettingsWindowBackground`.
public struct DSGroup<Content: View, HeaderAccessory: View>: View {
    private let title: String?
    private let icon: String?
    private let surfaceIntensity: AppDesignSystem.SettingsSurfaceIntensity
    private let headerAccessory: HeaderAccessory
    private let content: Content

    public init(
        surfaceIntensity: AppDesignSystem.SettingsSurfaceIntensity = .subtle,
        @ViewBuilder content: () -> Content
    )
        where HeaderAccessory == EmptyView
    {
        title = nil
        icon = nil
        self.surfaceIntensity = surfaceIntensity
        headerAccessory = EmptyView()
        self.content = content()
    }

    public init(
        _ title: String,
        icon: String? = nil,
        surfaceIntensity: AppDesignSystem.SettingsSurfaceIntensity = .subtle,
        @ViewBuilder content: () -> Content
    )
        where HeaderAccessory == EmptyView
    {
        self.title = title
        self.icon = icon
        self.surfaceIntensity = surfaceIntensity
        headerAccessory = EmptyView()
        self.content = content()
    }

    public init(
        _ title: String,
        icon: String? = nil,
        surfaceIntensity: AppDesignSystem.SettingsSurfaceIntensity = .subtle,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.surfaceIntensity = surfaceIntensity
        self.headerAccessory = headerAccessory()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .foregroundStyle(AppDesignSystem.Colors.accent)
                    }

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    headerAccessory
                }
                .padding(.leading, 4)
            }

            DSCard(style: .settings, settingsSurfaceIntensity: surfaceIntensity) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("DSGroup") {
    DSGroup(
        "Design Group",
        icon: "cube.fill",
        surfaceIntensity: .strong,
        headerAccessory: {
            DSBadge("Preview", kind: .neutral)
        },
        content: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Reusable layout container.")
                    .foregroundStyle(.secondary)
                Text("Contains a title, optional icon, and accessory.")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    )
    .padding()
}
