import AppKit
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import SwiftUI

// MARK: - AI Provider Configuration

/// Supported AI providers for post-processing transcriptions.
public enum AIProvider: String, CaseIterable, Codable, Sendable {
    case openai
    case anthropic
    case groq
    case google
    case custom

    public var displayName: String {
        switch self {
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .groq: "Groq"
        case .google: "Google"
        case .custom: "ai.provider.custom".localized
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .openai: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        case .groq: "https://api.groq.com/openai/v1"
        case .google: "https://generativelanguage.googleapis.com/v1beta"
        case .custom: ""
        }
    }

    public var icon: String {
        switch self {
        case .openai: "brain"
        case .anthropic: "sparkles"
        case .groq: "bolt.fill"
        case .google: "g.circle"
        case .custom: "server.rack"
        }
    }

    public var apiKeyURL: URL? {
        switch self {
        case .openai: URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
        case .groq: URL(string: "https://console.groq.com/keys")
        case .google: URL(string: "https://aistudio.google.com/app/apikey")
        case .custom: nil
        }
    }
}

// MARK: - App Language Configuration

/// Supported app languages for UI localization.
public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system
    case english
    case portuguese

    public var displayName: String {
        switch self {
        case .system:
            "settings.general.language.system".localized
        case .english:
            "settings.general.language.english".localized
        case .portuguese:
            "settings.general.language.portuguese".localized
        }
    }
}

// MARK: - Shortcut Activation Mode

/// Modes for how keyboard shortcuts activate recording.
public enum ShortcutActivationMode: String, CaseIterable, Codable, Sendable {
    /// Short press toggles recording; hold acts as push-to-talk (persisted raw value unchanged).
    case holdOrToggle
    /// Press once to start, press again to stop.
    case toggle
    /// Hold to record; release to stop (push-to-talk).
    case hold
    case doubleTap

    public var localizedName: String {
        switch self {
        case .holdOrToggle:
            "settings.shortcuts.activation_mode.hold_or_press".localized
        case .toggle:
            "settings.shortcuts.activation_mode.press".localized
        case .hold:
            "settings.shortcuts.activation_mode.hold".localized
        case .doubleTap:
            "settings.shortcuts.activation_mode.double_tap".localized
        }
    }
}

func normalizedInHouseShortcutDefinition(
    _ definition: ShortcutDefinition,
    activationMode: ShortcutActivationMode,
    allowReturnOrEnter: Bool = true
) -> ShortcutDefinition? {
    _ = activationMode
    guard let primaryKey = definition.primaryKey else {
        return nil
    }

    let isReturnOrEnterKey = primaryKey.keyCode == 0x24 || primaryKey.keyCode == 0x4C
    guard allowReturnOrEnter || !isReturnOrEnterKey else {
        return nil
    }

    let canonicalModifiers = canonicalSimpleOrIntermediateModifiers(definition.modifiers)
    let normalized = ShortcutDefinition(
        modifiers: canonicalModifiers,
        primaryKey: primaryKey,
        trigger: .singleTap
    )
    return normalized.isValid ? normalized : nil
}

func canonicalSimpleOrIntermediateModifiers(
    _ modifiers: [ModifierShortcutKey]
) -> [ModifierShortcutKey] {
    let mapped = modifiers.map { key -> ModifierShortcutKey in
        switch key {
        case .leftCommand, .rightCommand, .command:
            .command
        case .leftShift, .rightShift, .shift:
            .shift
        case .leftOption, .rightOption, .option:
            .option
        case .leftControl, .rightControl, .control:
            .control
        case .fn:
            .fn
        }
    }

    return Array(Set(mapped))
        .sorted { lhs, rhs in
            lhs.sortOrder < rhs.sortOrder
        }
}

// MARK: - Recording Indicator Configuration

/// Style options for the floating recording indicator.
public enum RecordingIndicatorStyle: String, CaseIterable, Codable, Sendable {
    case classic
    case mini
    case `super`
    case none

    public var displayName: String {
        switch self {
        case .classic:
            "settings.general.recording_indicator.style.classic".localized
        case .mini:
            "settings.general.recording_indicator.style.mini".localized
        case .super:
            "settings.general.recording_indicator.style.super".localized
        case .none:
            "settings.general.recording_indicator.style.none".localized
        }
    }
}

/// Position for the floating recording indicator on screen.
public enum RecordingIndicatorPosition: String, CaseIterable, Codable, Sendable {
    case top
    case bottom

    public var displayName: String {
        switch self {
        case .top:
            "settings.general.recording_indicator.position.top".localized
        case .bottom:
            "settings.general.recording_indicator.position.bottom".localized
        }
    }
}

/// Speed options for recording indicator waveform animations.
public enum RecordingIndicatorAnimationSpeed: String, CaseIterable, Codable, Sendable {
    case slow
    case normal
    case fast

    public var displayName: String {
        switch self {
        case .slow:
            "settings.general.recording_indicator.animation_speed.slow".localized
        case .normal:
            "settings.general.recording_indicator.animation_speed.normal".localized
        case .fast:
            "settings.general.recording_indicator.animation_speed.fast".localized
        }
    }
}

// MARK: - Appearance Mode

/// Controls the app's color scheme appearance.
public enum AppearanceMode: String, CaseIterable, Codable, Sendable {
    case light
    case system
    case dark

    public var displayName: String {
        switch self {
        case .light:
            "settings.general.appearance.light".localized
        case .system:
            "settings.general.appearance.system".localized
        case .dark:
            "settings.general.appearance.dark".localized
        }
    }

    public var nsAppearanceName: NSAppearance.Name? {
        switch self {
        case .light:
            .aqua
        case .system:
            nil
        case .dark:
            .darkAqua
        }
    }
}

// MARK: - App Theme Configuration

/// Available colors for the application's accent theme.
public enum AppThemeColor: String, CaseIterable, Codable, Sendable {
    case system
    case orange
    case red
    case pink
    case purple
    case blue
    case cyan
    case green
    case yellow

    /// The NSColor representation for use in AppKit.
    public var nsColor: NSColor {
        switch self {
        case .system: .controlAccentColor
        case .orange: .systemOrange
        case .red: .systemRed
        case .pink: .systemPink
        case .purple: .systemPurple
        case .blue: .systemBlue
        case .cyan: .systemCyan
        case .green: .systemGreen
        case .yellow: .systemYellow
        }
    }

    /// A color that contrasts well with the theme color, for use as text or icons on top of it.
    public var adaptiveForegroundColor: Color {
        switch self {
        case .system:
            .white
        case .yellow, .cyan: .black
        default: .white
        }
    }
}

// MARK: - Assistant Screen Border Configuration

/// Available colors for the Assistant mode screen border.
/// Reuses AppThemeColor logic for consistency.
public typealias AssistantBorderColor = AppThemeColor

/// Style options for the Assistant mode screen border feedback.
public enum AssistantBorderStyle: String, CaseIterable, Codable, Sendable {
    case stroke
    case glow

    public var displayName: String {
        switch self {
        case .stroke:
            "settings.assistant.border_style.stroke".localized
        case .glow:
            "settings.assistant.border_style.glow".localized
        }
    }
}
