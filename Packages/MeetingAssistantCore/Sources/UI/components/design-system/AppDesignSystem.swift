import AppKit
import SwiftUI

/// Project-wide design system (tokens + shared components).
///
/// Goals:
/// - Prefer macOS-native semantics (materials + semantic colors)
/// - Centralize spacing/typography/radius/shadows (DRY)
/// - Keep styling consistent across Settings, Menu Bar, and in-app views
public enum AppDesignSystem {

    public enum SettingsSurfaceIntensity {
        case subtle
        case regular
        case strong
    }

    public enum Accessibility {
        public static var reduceTransparency: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }

        public static var increaseContrast: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        }
    }

    // MARK: - Colors

    public enum Colors {
        static func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
            if let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua]) {
                return bestMatch == .darkAqua
            }

            return appearance.name.rawValue.localizedCaseInsensitiveContains("dark")
        }

        static func resolveColor(
            in appearance: NSAppearance,
            _ provider: () -> NSColor,
        ) -> NSColor {
            var resolvedColor: NSColor?
            appearance.performAsCurrentDrawingAppearance {
                resolvedColor = provider()
            }
            return resolvedColor ?? provider()
        }

        private static func dynamicNSColor(
            light: @escaping @autoclosure () -> NSColor,
            dark: @escaping @autoclosure () -> NSColor,
        ) -> NSColor {
            NSColor(name: nil) { appearance in
                resolveColor(in: appearance) {
                    if isDarkAppearance(appearance) {
                        dark()
                    } else {
                        light()
                    }
                }
            }
        }

        public static var accent: Color {
            Color(nsColor: .controlAccentColor)
        }

        public static var secondaryAccent: Color {
            accent.opacity(0.8)
        }

        public static var onAccent: Color {
            .white
        }

        public static let success = Color(nsColor: .systemGreen)
        public static let warning = Color(nsColor: .systemOrange)
        public static let error = Color(nsColor: .systemRed)
        public static let neutral = Color(nsColor: .systemGray)

        public static var iconHighlight: Color {
            accent
        }

        public static let aiGradient = LinearGradient(
            colors: [Color.orange, Color.red],
            startPoint: .topLeading,
            endPoint: .bottomTrailing,
        )

        public static var dashboardHeroGradient: LinearGradient {
            LinearGradient(
                colors: [accent.opacity(0.8), accent],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
        }

        public static let recording = Color.red
        public static let recordingOverlayBackground = recording.opacity(0.9)
        public static let overlayBackground = Color.black.opacity(0.9)
        public static let overlayDivider = Color.white.opacity(0.2)
        public static let overlayForeground = Color.white
        public static let overlayStatusForeground = Color.black
        public static let overlayForegroundMuted = Color.white.opacity(0.85)
        public static let recordingIndicatorMaterialTint = Color.black.opacity(0.22)
        public static let recordingIndicatorStroke = Color.white.opacity(0.22)
        public static let recordingIndicatorAuxiliaryBackground = Color.black.opacity(0.14)

        public static let windowBackground = Color(NSColor.windowBackgroundColor)
        public static let controlBackground = Color(NSColor.controlBackgroundColor)
        public static let textBackground = Color(NSColor.textBackgroundColor)
        public static let separator = Color(NSColor.separatorColor)

        static func settingsCanvasBackgroundNSColor() -> NSColor {
            .windowBackgroundColor
        }

        public static var settingsCanvasBackground: Color {
            Color(nsColor: settingsCanvasBackgroundNSColor())
        }

        public static var settingsWindowMaterialOverlay: Color {
            settingsCanvasBackground.opacity(0.50)
        }

        public static var settingsPanelOverlay: Color {
            settingsCanvasBackground.opacity(0.42)
        }

        public static var settingsMaterialCard: Color {
            settingsMaterialCardFill(reduceTransparency: false)
        }

        public static var settingsMaterialStroke: Color {
            settingsMaterialCardStroke(increaseContrast: Accessibility.increaseContrast)
        }

        public static func settingsMaterialCardFill(
            reduceTransparency: Bool,
            intensity: AppDesignSystem.SettingsSurfaceIntensity = .subtle,
        ) -> Color {
            if reduceTransparency {
                return settingsCardBackground(intensity: intensity)
            }

            switch intensity {
            case .subtle:
                return Color(nsColor: .controlBackgroundColor).opacity(0.58)
            case .regular:
                return Color(nsColor: .controlBackgroundColor).opacity(0.68)
            case .strong:
                return Color(nsColor: .textBackgroundColor).opacity(0.74)
            }
        }

        public static func settingsMaterialCardStroke(increaseContrast: Bool) -> Color {
            separator.opacity(increaseContrast ? 0.62 : 0.36)
        }

        public static func settingsTitleBarBottomTreatment(increaseContrast: Bool) -> Color {
            separator.opacity(increaseContrast ? 0.78 : 0.42)
        }

        public static var glassBackground: Color {
            windowBackground
        }

        public static var settingsGlassBackground: Color {
            settingsCanvasBackground
        }

        public static var settingsTitleBarTint: Color {
            windowBackground
        }

        public static var settingsTitleBarDivider: Color {
            separator
        }

        public static var cardBackground: Color {
            controlBackground
        }

        public static var settingsCardBackground: Color {
            settingsCardBackground(intensity: .subtle)
        }

        static func settingsCardBackgroundNSColor(
            intensity: AppDesignSystem.SettingsSurfaceIntensity = .subtle,
        ) -> NSColor {
            switch intensity {
            case .subtle:
                .controlBackgroundColor
            case .regular:
                .underPageBackgroundColor
            case .strong:
                .textBackgroundColor
            }
        }

        public static func settingsCardBackground(
            intensity: AppDesignSystem.SettingsSurfaceIntensity = .subtle,
        ) -> Color {
            Color(nsColor: settingsCardBackgroundNSColor(intensity: intensity))
        }

        public static func settingsInlineBackground(
            intensity: AppDesignSystem.SettingsSurfaceIntensity = .subtle,
        ) -> Color {
            switch intensity {
            case .subtle:
                Color(nsColor: .underPageBackgroundColor)
            case .regular:
                Color(nsColor: .controlBackgroundColor)
            case .strong:
                Color(nsColor: .textBackgroundColor)
            }
        }

        public static var cardStroke: Color {
            separator
        }

        public static var settingsCardStroke: Color {
            settingsMaterialStroke
        }

        public static var subtleFill: Color {
            Color(nsColor: .controlBackgroundColor)
        }

        public static var subtleFill2: Color {
            Color(nsColor: .underPageBackgroundColor)
        }

        public static var secondaryFill: Color {
            Color(nsColor: .textBackgroundColor)
        }

        public static var selectionFill: Color {
            Color(nsColor: .selectedContentBackgroundColor)
        }

        public static var selectionStroke: Color {
            Color(nsColor: .selectedContentBackgroundColor)
        }

        public static var selectedContentForeground: Color {
            Color(nsColor: .alternateSelectedControlTextColor)
        }

        public static var selectedContentSecondaryForeground: Color {
            selectedContentForeground.opacity(0.82)
        }

        public static func primaryTextStyle(isSelected: Bool = false) -> AnyShapeStyle {
            isSelected
                ? AnyShapeStyle(selectedContentForeground)
                : AnyShapeStyle(.primary)
        }

        public static func secondaryTextStyle(isSelected: Bool = false) -> AnyShapeStyle {
            isSelected
                ? AnyShapeStyle(selectedContentSecondaryForeground)
                : AnyShapeStyle(.secondary)
        }

        public static var topFadeLeading: Color {
            windowBackground
        }

        public static var topFadeTrailing: Color {
            windowBackground
        }

        public static var settingsTopFadeLeading: Color {
            settingsCanvasBackground
        }

        public static var settingsTopFadeTrailing: Color {
            settingsCanvasBackground
        }
    }

    // MARK: - Layout

    public enum Layout {
        public static let spacing2: CGFloat = 2
        public static let spacing4: CGFloat = 4
        public static let spacing6: CGFloat = 6
        public static let spacing8: CGFloat = 8
        public static let spacing10: CGFloat = 10
        public static let spacing12: CGFloat = 12
        public static let spacing16: CGFloat = 16
        public static let spacing20: CGFloat = 20
        public static let spacing24: CGFloat = 24

        public static let tinyCornerRadius: CGFloat = 4
        public static let chipCornerRadius: CGFloat = 6
        public static let smallCornerRadius: CGFloat = 8
        public static let cardCornerRadius: CGFloat = 12
        public static let largeCornerRadius: CGFloat = 16

        /// Minimum side length for shortcut keycap chips.
        public static let keyCapSide: CGFloat = 18

        public static let heroCornerRadius: CGFloat = 16
        public static let heroPadding: CGFloat = 24

        public static let cardPadding: CGFloat = 14
        public static let sectionSpacing: CGFloat = 16
        public static let itemSpacing: CGFloat = 10

        public static let controlHeight: CGFloat = 34
        public static let compactButtonHeight: CGFloat = 30
        public static let settingsTitleBarMaterialHeight: CGFloat = 56
        public static let recordingIndicatorMiniHeight: CGFloat = 38
        public static let recordingIndicatorClassicHeight: CGFloat = 42
        public static let recordingIndicatorSuperHeight: CGFloat = 98

        public static let recordingIndicatorPanelWidth: CGFloat = 380
        public static let modeEditorPanelWidth: CGFloat = 400

        // Recording Indicator Metrics
        public static let recordingIndicatorClassicPromptSize: CGFloat = 42
        public static let recordingIndicatorMiniPromptSize: CGFloat = 38
        public static let recordingIndicatorSuperPromptSize: CGFloat = 110

        public static let recordingIndicatorClassicInnerSpacing: CGFloat = 12
        public static let recordingIndicatorMiniInnerSpacing: CGFloat = 8
        public static let recordingIndicatorSuperInnerSpacing: CGFloat = 10

        public static let recordingIndicatorClassicWaveCount: Int = 18
        public static let recordingIndicatorMiniWaveCount: Int = 9
        public static let recordingIndicatorSuperWaveCount: Int = 72

        public static let recordingIndicatorClassicWaveHeight: CGFloat = 24
        public static let recordingIndicatorMiniWaveHeight: CGFloat = 20
        public static let recordingIndicatorSuperWaveHeight: CGFloat = 34

        public static let recordingIndicatorWaveformBarWidth: CGFloat = 2
        public static let recordingIndicatorWaveformBarSpacing: CGFloat = 2
        public static let recordingIndicatorSuperWaveformBarWidth: CGFloat = 1.5
        public static let recordingIndicatorSuperWaveformBarSpacing: CGFloat = 1.25
        public static let recordingIndicatorWaveformMinHeight: CGFloat = 2
        public static let recordingIndicatorWaveformMaxHeight: CGFloat = 24

        public static let recordingIndicatorDotSize: CGFloat = 8
        public static let recordingIndicatorMiniDotSize: CGFloat = 8
        public static let recordingIndicatorPromptGap: CGFloat = 2
        public static let recordingIndicatorSidePadding: CGFloat = 8
        public static let recordingIndicatorSuperHorizontalPadding: CGFloat = 14
        public static let recordingIndicatorSuperVerticalPadding: CGFloat = 14
        public static let recordingIndicatorSuperFooterHeight: CGFloat = 30
        public static let recordingIndicatorSuperFooterSpacing: CGFloat = 8
        public static let recordingIndicatorSuperFooterGroupSpacing: CGFloat = 12
        public static let recordingIndicatorSuperFooterChipHeight: CGFloat = 22
        public static let recordingIndicatorSuperFooterChipHorizontalPadding: CGFloat = 8
        public static let recordingIndicatorSuperFooterIconWidth: CGFloat = 24
        public static let recordingIndicatorSuperActionStopWidth: CGFloat = 64
        public static let recordingIndicatorSuperActionCancelWidth: CGFloat = 86
        public static let recordingIndicatorSuperCornerRadius: CGFloat = 18

        public static let shadowRadius: CGFloat = 10
        public static let shadowX: CGFloat = 0
        public static let shadowY: CGFloat = 5
        public static let shadowRadiusSmall: CGFloat = 6
        public static let shadowYSmall: CGFloat = 3
        public static let recordingIndicatorMainShadowRadius: CGFloat = 10
        public static let recordingIndicatorMainShadowY: CGFloat = 5
        public static let recordingIndicatorAuxShadowRadius: CGFloat = 6
        public static let recordingIndicatorAuxShadowY: CGFloat = 3
        public static let recordingIndicatorHoverEnterResponse: CGFloat = 0.22
        public static let recordingIndicatorHoverEnterDamping: CGFloat = 0.86
        public static let recordingIndicatorHoverExitResponse: CGFloat = 0.26
        public static let recordingIndicatorHoverExitDamping: CGFloat = 0.9

        public static let maxCompactTextFieldWidth: CGFloat = 200
        public static let textAreaPadding: CGFloat = spacing8

        public static let narrowPickerWidth: CGFloat = 140
        public static let smallPickerWidth: CGFloat = 150

        public static let chartHeight: CGFloat = 220
        public static let indentation: CGFloat = 24
        public static let smallPadding: CGFloat = 4
        public static let compactInset: CGFloat = spacing6

    }
}
