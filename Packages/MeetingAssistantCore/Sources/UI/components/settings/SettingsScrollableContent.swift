import SwiftUI

enum SettingsContentSurface {
    static let horizontalGutter: CGFloat = 20
    static let bottomInset: CGFloat = 20
    /// Legacy preview metric retained for surface-contract fixtures (not live shell chrome).
    static let titleStripBoundaryHeight: CGFloat = AppDesignSystem.Layout.settingsTitleBarMaterialHeight
}

/// Settings shell uses a transparent AppKit titlebar without an opaque in-content title strip.
enum SettingsChromeLayoutPolicy {
    static let usesLocalTitleStrip = false
    /// Clears traffic lights / titlebar drag region when content ignores the top safe area.
    static let titlebarClearance: CGFloat = 40

    /// Detail-only clearance when traffic lights sit over the detail column.
    /// Keep the spacer always mounted and animate this height so sidebar toggles do not reflow by insert/remove.
    static func detailTitlebarClearanceHeight(sidebarVisible: Bool) -> CGFloat {
        sidebarVisible ? 0 : titlebarClearance
    }
}

/// Owns the single vertical scroll surface for collection, status, analytics,
/// and rich-editor pages that are intentionally outside the native settings
/// `Form` contract. Do not embed a page `Form` inside this container.
public struct SettingsScrollableContent<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(
        spacing: CGFloat = AppDesignSystem.Layout.sectionSpacing,
        @ViewBuilder content: () -> Content,
    ) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    content
                }
                .padding(
                    EdgeInsets(
                        top: 0,
                        leading: SettingsContentSurface.horizontalGutter,
                        bottom: SettingsContentSurface.bottomInset,
                        trailing: SettingsContentSurface.horizontalGutter,
                    ),
                )
                .frame(
                    minWidth: geometry.size.width,
                    minHeight: geometry.size.height,
                    alignment: .topLeading,
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .settingsScrollEdgeEffect()
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .subtleScrollbars()
        }
    }
}

// MARK: - Surface Contract Previews

private struct SettingsContentSurfacePreview: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            SettingsWindowBackground()

            SettingsScrollableContent {
                DSGroup("settings.section.general".localized, icon: "gearshape.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Surface contract demonstration")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("20pt horizontal gutter on both sides, content under the transparent titlebar, bottom breathing room, and scrollable content.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }

                DSGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        SettingsRowClickSurface(onSingleClick: {}, content: {
                            HStack {
                                Text("Row item")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        })
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 400)
    }
}

#Preview("Content Surface (Normal)") {
    SettingsContentSurfacePreview()
        .frame(width: 900)
}

#Preview("Content Surface (Narrow)") {
    SettingsContentSurfacePreview()
        .frame(width: 600)
}

#Preview("Content Surface (Accessibility)") {
    SettingsContentSurfacePreview()
        .frame(width: 600)
        .environment(\.dynamicTypeSize, .accessibility3)
        .environment(\.settingsReduceTransparencyPreview, true)
        .preferredColorScheme(.dark)
}

#Preview("Ownership Matrix — Native Form") {
    SettingsFormPage {
        SettingsFormSectionHeader(title: "Form-owned page", icon: "rectangle.stack.fill")
    } content: {
        Section("Scalar settings") {
            Picker("Mode", selection: .constant("Automatic")) {
                Text("Automatic").tag("Automatic")
                Text("Manual").tag("Manual")
            }
            Toggle("Enabled", isOn: .constant(true))
                .toggleStyle(.checkbox)
        }
    }
    .frame(width: 900, height: 260)
}

#Preview("Ownership Matrix — Dashboard ScrollView") {
    SettingsScrollableContent {
        SettingsSectionHeader(title: "Dashboard-owned page", description: "Collections and analytics retain the existing ScrollView owner.")
        SettingsListGroup("Rows", icon: "list.bullet") {
            Text("Non-Form content")
        }
    }
    .frame(width: 900, height: 260)
}
