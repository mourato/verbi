import AppKit
import SwiftUI

public enum AppTypography {
    public static var sidebarIcon: Font {
        .system(size: 14, weight: .medium)
    }

    public static var sidebarLabel: Font {
        .system(size: 14, weight: .medium)
    }

    public static var compactControlLabel: Font {
        .caption.weight(.medium)
    }

    public static var settingsSectionTitle: Font {
        .headline
    }

    public static var settingsSectionDescription: Font {
        .caption
    }

    public static var indicatorCaption: Font {
        .caption2.weight(.semibold)
    }

    public static var onboardingStatusLabel: Font {
        .caption.weight(.medium)
    }

    public static var onboardingStepLabel: Font {
        .caption.weight(.medium)
    }

    public static var onboardingStepCompletedIcon: Font {
        .caption.weight(.semibold)
    }

    public static func onboardingPermissionIcon(size: CGFloat) -> Font {
        // Permission glyphs scale with surrounding title text while retaining symbol geometry.
        .system(size: size)
    }

    public static func indicatorTimerNSFont() -> NSFont {
        // Measured overlay width depends on a deterministic monospaced timer font.
        NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    }

    public static func indicatorPromptFooterFont() -> Font {
        // Compact overlay typography is intentionally fixed to preserve panel width budgets.
        .system(size: 12, weight: .medium)
    }

    public static func indicatorFooterIconFont() -> Font {
        // Compact overlay typography is intentionally fixed to preserve panel width budgets.
        .system(size: 12, weight: .semibold)
    }

    public static func indicatorControlIconFont() -> Font {
        // Compact overlay typography is intentionally fixed to preserve panel width budgets.
        .system(size: 15, weight: .medium)
    }

    public static func indicatorActionFont() -> Font {
        // Compact overlay typography is intentionally fixed to preserve panel width budgets.
        .system(size: 11, weight: .semibold)
    }
}
