import SwiftUI

@resultBuilder
public enum SettingsListRowBuilder {
    public static func buildExpression(_ expression: some View) -> [AnyView] {
        [AnyView(expression)]
    }

    public static func buildBlock(_ components: [AnyView]...) -> [AnyView] {
        components.flatMap(\.self)
    }

    public static func buildOptional(_ component: [AnyView]?) -> [AnyView] {
        component ?? []
    }

    public static func buildEither(first component: [AnyView]) -> [AnyView] {
        component
    }

    public static func buildEither(second component: [AnyView]) -> [AnyView] {
        component
    }

    public static func buildArray(_ components: [[AnyView]]) -> [AnyView] {
        components.flatMap(\.self)
    }
}

/// Composed list surface for collection, status, navigation, and data rows.
///
/// Scalar settings belong in the owning page's native `Form` and `Section`;
/// this component intentionally keeps collection interactions and row rhythm
/// outside that contract. Default surface intensity is `.subtle`.
public struct SettingsListGroup<HeaderAccessory: View>: View {
    private let title: String
    private let icon: String?
    private let surfaceIntensity: AppDesignSystem.SettingsSurfaceIntensity
    private let headerAccessory: HeaderAccessory
    private let rows: [AnyView]

    public init(
        _ title: String,
        icon: String? = nil,
        surfaceIntensity: AppDesignSystem.SettingsSurfaceIntensity = .subtle,
        @SettingsListRowBuilder rows: () -> [AnyView]
    )
        where HeaderAccessory == EmptyView
    {
        self.title = title
        self.icon = icon
        self.surfaceIntensity = surfaceIntensity
        headerAccessory = EmptyView()
        self.rows = rows()
    }

    public init(
        _ title: String,
        icon: String? = nil,
        surfaceIntensity: AppDesignSystem.SettingsSurfaceIntensity = .subtle,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @SettingsListRowBuilder rows: () -> [AnyView]
    ) {
        self.title = title
        self.icon = icon
        self.surfaceIntensity = surfaceIntensity
        self.headerAccessory = headerAccessory()
        self.rows = rows()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            DSCard(style: .settings, settingsSurfaceIntensity: surfaceIntensity, padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows.indices, id: \.self) { index in
                        if index > rows.startIndex {
                            Divider()
                        }

                        rows[index]
                            .modifier(SettingsListRowModifier())
                    }
                }
                .padding(.horizontal, AppDesignSystem.Layout.cardPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct SettingsListDrillDownButtonRow: View {
    private let title: String
    private let subtitle: String?
    private let accessibilityHint: String?
    private let action: () -> Void

    public init(
        title: String,
        subtitle: String? = nil,
        accessibilityHint: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessibilityHint = accessibilityHint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                SettingsTitleWithPopover(
                    title: title,
                    helperMessage: subtitle
                )

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .modifier(OptionalAccessibilityHintModifier(accessibilityHint: accessibilityHint))
    }
}

private struct OptionalAccessibilityHintModifier: ViewModifier {
    let accessibilityHint: String?

    func body(content: Content) -> some View {
        if let accessibilityHint, !accessibilityHint.isEmpty {
            content.accessibilityHint(accessibilityHint)
        } else {
            content
        }
    }
}

private struct SettingsListRowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}

#Preview("Settings List Group") {
    SettingsListGroup("Workflow", icon: "bolt.fill") {
        DSToggleRow("Automatically start recording", isOn: .constant(true))
        SettingsListDrillDownButtonRow(title: "Configure monitored apps and sites") {}
    }
    .padding()
}
