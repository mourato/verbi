import SwiftUI

enum ShortcutChipColorStyle {
    case neutral
    case success
    case error
}

/// Compact macOS-style keycap chips for shortcut display (Cue visual base).
struct ShortcutChipRow: View {
    let labels: [String]
    let colorStyle: ShortcutChipColorStyle

    var body: some View {
        if labels.isEmpty {
            Text("settings.shortcuts.modifier.none".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: AppDesignSystem.Layout.spacing2) {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(chipForeground)
                        .frame(
                            minWidth: AppDesignSystem.Layout.keyCapSide,
                            minHeight: AppDesignSystem.Layout.keyCapSide,
                        )
                        .padding(.horizontal, AppDesignSystem.Layout.spacing4)
                        .background(
                            RoundedRectangle(
                                cornerRadius: AppDesignSystem.Layout.chipCornerRadius,
                                style: .continuous,
                            )
                            .fill(chipBackground),
                        )
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: AppDesignSystem.Layout.chipCornerRadius,
                                style: .continuous,
                            )
                            .strokeBorder(chipBorder, lineWidth: 1),
                        )
                }
            }
        }
    }

    private var chipBackground: Color {
        switch colorStyle {
        case .neutral:
            Color.secondary.opacity(0.12)
        case .success:
            AppDesignSystem.Colors.success.opacity(0.2)
        case .error:
            AppDesignSystem.Colors.error.opacity(0.2)
        }
    }

    private var chipBorder: Color {
        switch colorStyle {
        case .neutral:
            Color.primary.opacity(0.15)
        case .success:
            AppDesignSystem.Colors.success.opacity(0.35)
        case .error:
            AppDesignSystem.Colors.error.opacity(0.35)
        }
    }

    private var chipForeground: Color {
        switch colorStyle {
        case .neutral:
            Color.secondary
        case .success:
            AppDesignSystem.Colors.success
        case .error:
            AppDesignSystem.Colors.error
        }
    }
}
