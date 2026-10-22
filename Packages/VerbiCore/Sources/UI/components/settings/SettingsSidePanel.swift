import SwiftUI

enum SettingsSidePanelLayout {
    static func resolvedWidth(requested: CGFloat, available: CGFloat) -> CGFloat {
        min(max(requested, 0), max(available, 0))
    }
}

struct SettingsWindowPanelSurfaceModifier<PanelContent: View>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Environment(\.settingsReduceTransparencyPreview) private var reduceTransparencyPreview
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let isPresented: Bool
    let width: CGFloat
    let onDismiss: () -> Void
    let onEscape: (() -> Void)?
    @ViewBuilder let panelContent: () -> PanelContent

    private var reduceMotion: Bool {
        accessibilityReduceMotion
    }

    private var reduceTransparency: Bool {
        accessibilityReduceTransparency || reduceTransparencyPreview
    }

    private var escapeAction: () -> Void {
        onEscape ?? onDismiss
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            content
                .disabled(isPresented)
                .accessibilityHidden(isPresented)

            GeometryReader { geometry in
                ZStack(alignment: .trailing) {
                    if isPresented {
                        // Clear outside layer. Prefer Color.clear + contentShape over an
                        // empty-title Button, which can lose hit testing on macOS.
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onDismiss)
                            .accessibilityHidden(true)
                            .transition(.identity)
                    }

                    if isPresented {
                        panelContent()
                            .frame(width: SettingsSidePanelLayout.resolvedWidth(
                                requested: width,
                                available: geometry.size.width
                            ))
                            .frame(maxHeight: .infinity, alignment: .top)
                            .background(surface)
                            .overlay(separator, alignment: .leading)
                            .overlay(separator, alignment: .trailing)
                            .transition(SettingsMotion.sidePanelTransition(reduceMotion: reduceMotion))
                            .zIndex(1)
                    }
                }
            }
            .allowsHitTesting(isPresented)
            .zIndex(1)
        }
        // Own Escape for the whole host (list + panel), not only the panel subtree,
        // so focus on the underlying Modes list still dismisses / unwinds correctly.
        .onExitCommand {
            guard isPresented else { return }
            escapeAction()
        }
        .animation(SettingsMotion.sidePanelAnimation(reduceMotion: reduceMotion), value: isPresented)
    }

    @ViewBuilder private var surface: some View {
        if reduceTransparency {
            AppDesignSystem.Colors.settingsCanvasBackground
        } else {
            ZStack {
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                AppDesignSystem.Colors.settingsPanelOverlay
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(AppDesignSystem.Colors.separator.opacity(colorSchemeContrast == .increased ? 1 : 0.42))
            .frame(width: 1)
            .accessibilityHidden(true)
    }
}

#Preview("Side Panel") {
    SidePanelPreview()
}

private struct SidePanelPreview: View {
    @State private var isPresented = true

    var body: some View {
        Text("Stable underlying list")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding()
            .windowSidePanel(
                isPresented: isPresented,
                onDismiss: { isPresented = false },
                content: {
                    Text("400 pt editor")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            )
            .frame(width: 900, height: 640)
    }
}
