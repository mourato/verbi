import SwiftUI

/// Form-friendly expandable disclosure for infrequent options that stay on the same page.
///
/// Expand/collapse uses `SettingsMotion.expandableAnimation` (short easeInOut disclosure
/// timing), not `sectionAnimation` / `defaultSpring`.
///
/// Prefer this over `SettingsListDrillDownButtonRow` / `SettingsDrillDownButtonRow` when
/// content should expand in place rather than navigate to a child destination.
public struct SettingsExpandableSection<Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let accessibilityHint: String?
    @Binding private var isExpanded: Bool
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        title: String,
        subtitle: String? = nil,
        accessibilityHint: String? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessibilityHint = accessibilityHint
        _isExpanded = isExpanded
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(SettingsMotion.expandableAnimation(reduceMotion: reduceMotion)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    SettingsTitleWithPopover(
                        title: title,
                        helperMessage: subtitle
                    )

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isExpanded ? "common.expanded".localized : "common.collapsed".localized)
            .modifier(OptionalExpandableAccessibilityHintModifier(accessibilityHint: accessibilityHint))

            if isExpanded {
                content
                    .padding(.top, AppDesignSystem.Layout.spacing12)
                    .padding(.leading, AppDesignSystem.Layout.spacing4)
                    .transition(SettingsMotion.sectionTransition(reduceMotion: reduceMotion))
            }
        }
    }
}

private struct OptionalExpandableAccessibilityHintModifier: ViewModifier {
    let accessibilityHint: String?

    func body(content: Content) -> some View {
        if let accessibilityHint, !accessibilityHint.isEmpty {
            content.accessibilityHint(accessibilityHint)
        } else {
            content
        }
    }
}

#Preview("Expandable Section — 600") {
    SettingsFormPage {
        SettingsFormSectionHeader(title: "Preferences", icon: "gearshape.fill")
    } content: {
        Section("Workflow") {
            SettingsExpandableSection(
                title: "Export summaries",
                subtitle: "Automatically saves the meeting summary as Markdown in the selected folder.",
                isExpanded: .constant(true)
            ) {
                Toggle("Auto-export summaries", isOn: .constant(true))
                    .toggleStyle(.switch)
                Picker("Safety policy", selection: .constant(0)) {
                    Text("Standard").tag(0)
                    Text("Strict").tag(1)
                }
                .pickerStyle(.menu)
            }
            SettingsExpandableSection(
                title: "Monitored apps and sites",
                subtitle: "Configure which apps and web targets are monitored.",
                isExpanded: .constant(false)
            ) {
                Text("Expanded collection content would appear here.")
                    .foregroundStyle(.secondary)
            }
        }
    }
    .frame(width: 600, height: 420)
}

#Preview("Expandable Section — 900") {
    SettingsFormPage {
        SettingsFormSectionHeader(title: "Preferences", icon: "gearshape.fill")
    } content: {
        Section("Details") {
            SettingsExpandableSection(
                title: "Advanced options",
                subtitle: "Configure additional behavior",
                isExpanded: .constant(false)
            ) {
                Toggle("Enable feature", isOn: .constant(false))
                    .toggleStyle(.switch)
            }
        }
    }
    .frame(width: 900, height: 300)
}
