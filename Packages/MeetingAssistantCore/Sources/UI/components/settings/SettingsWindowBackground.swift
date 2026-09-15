import AppKit
import SwiftUI

extension EnvironmentValues {
    @Entry var settingsReduceTransparencyPreview = false
}

public struct SettingsWindowBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Environment(\.settingsReduceTransparencyPreview) private var reduceTransparencyPreview

    public init() {}

    public var body: some View {
        nativeWindowBackground
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var nativeWindowBackground: some View {
        switch colorScheme {
        case .light, .dark:
            if effectiveReduceTransparency {
                AppDesignSystem.Colors.windowBackground
            } else {
                ZStack {
                    VisualEffectView(
                        material: .sidebar,
                        blendingMode: .behindWindow
                    )
                    AppDesignSystem.Colors.settingsWindowMaterialOverlay
                }
            }
        @unknown default:
            AppDesignSystem.Colors.windowBackground
        }
    }

    private var effectiveReduceTransparency: Bool {
        accessibilityReduceTransparency
            || reduceTransparencyPreview
            || AppDesignSystem.Accessibility.reduceTransparency
    }
}

public struct SettingsTitleBarMaterialBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Environment(\.settingsReduceTransparencyPreview) private var reduceTransparencyPreview

    public init(usesBottomFade: Bool = true) {
        _ = usesBottomFade
    }

    public var body: some View {
        nativeTitleBarBackground
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(
                        AppDesignSystem.Colors.settingsTitleBarBottomTreatment(
                            increaseContrast: AppDesignSystem.Accessibility.increaseContrast
                        )
                    )
                    .frame(height: 1)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var nativeTitleBarBackground: some View {
        switch colorScheme {
        case .light, .dark:
            if effectiveReduceTransparency {
                Rectangle()
                    .fill(AppDesignSystem.Colors.settingsCanvasBackground)
            } else {
                ZStack {
                    Rectangle()
                        .fill(.bar)
                        .background(.bar)
                    AppDesignSystem.Colors.settingsPanelOverlay
                }
            }
        @unknown default:
            Rectangle()
                .fill(AppDesignSystem.Colors.windowBackground)
        }
    }

    private var effectiveReduceTransparency: Bool {
        accessibilityReduceTransparency
            || reduceTransparencyPreview
            || AppDesignSystem.Accessibility.reduceTransparency
    }
}

#Preview {
    SettingsWindowBackground()
}

#Preview("Title Bar Material") {
    SettingsTitleBarMaterialBackground()
        .frame(width: 900, height: AppDesignSystem.Layout.settingsTitleBarMaterialHeight)
}
