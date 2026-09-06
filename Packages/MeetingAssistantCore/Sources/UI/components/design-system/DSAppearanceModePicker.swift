import MeetingAssistantCoreInfrastructure
import SwiftUI

/// Horizontal thumbnail picker for appearance mode (Cue / System Settings style).
public struct DSAppearanceModePicker: View {
    @Binding private var selection: AppearanceMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(selection: Binding<AppearanceMode>) {
        _selection = selection
    }

    public var body: some View {
        HStack(spacing: 14) {
            ForEach(Self.displayOrder, id: \.self) { mode in
                AppearanceThumbnailView(
                    mode: mode,
                    isSelected: selection == mode,
                ) {
                    withAnimation(AppleMotion.animation(reduceMotion: reduceMotion, kind: .interactive)) {
                        selection = mode
                    }
                }
            }
        }
        .padding(.vertical, AppDesignSystem.Layout.spacing4)
        .accessibilityElement(children: .contain)
    }

    /// Cue order: System → Light → Dark (independent of enum declaration order).
    private static let displayOrder: [AppearanceMode] = [.system, .light, .dark]
}

/// Individual appearance mode thumbnail with window chrome preview.
struct AppearanceThumbnailView: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppDesignSystem.Layout.spacing6) {
                thumbnailPreview
                    .overlay(
                        RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius, style: .continuous)
                            .stroke(isSelected ? AppDesignSystem.Colors.accent : Color.clear, lineWidth: 3),
                    )
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)

                Text(mode.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? AppDesignSystem.Colors.accent : Color.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var thumbnailPreview: some View {
        switch mode {
        case .system:
            splitThumbnail
        case .light:
            singleThumbnail(isDark: false)
        case .dark:
            singleThumbnail(isDark: true)
        }
    }

    private var splitThumbnail: some View {
        HStack(spacing: 0) {
            windowPreview(isDark: false)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: AppDesignSystem.Layout.smallCornerRadius,
                        bottomLeadingRadius: AppDesignSystem.Layout.smallCornerRadius,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0,
                        style: .continuous,
                    ),
                )

            windowPreview(isDark: true)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: AppDesignSystem.Layout.smallCornerRadius,
                        topTrailingRadius: AppDesignSystem.Layout.smallCornerRadius,
                        style: .continuous,
                    ),
                )
        }
        .frame(width: 72, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius, style: .continuous))
    }

    private func singleThumbnail(isDark: Bool) -> some View {
        windowPreview(isDark: isDark)
            .frame(width: 72, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius, style: .continuous))
    }

    private func windowPreview(isDark: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: AppDesignSystem.Layout.spacing4) {
                Circle()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 6, height: 6)
                Circle()
                    .fill(Color.yellow.opacity(0.9))
                    .frame(width: 6, height: 6)
                Circle()
                    .fill(Color.green.opacity(0.9))
                    .frame(width: 6, height: 6)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppDesignSystem.Layout.spacing6)
            .padding(.vertical, 5)
            .background(isDark ? Color(white: 0.22) : Color(white: 0.92))

            HStack(spacing: 0) {
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
                            .frame(height: 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(AppDesignSystem.Layout.spacing4)
                .frame(width: 22)
                .background(isDark ? Color(white: 0.18) : Color(white: 0.95))

                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                        .frame(height: 4)
                    Spacer(minLength: 0)
                }
                .padding(AppDesignSystem.Layout.spacing6)
                .frame(maxWidth: .infinity)
                .background(isDark ? Color(white: 0.14) : Color.white)
            }
        }
        .background(isDark ? Color(white: 0.14) : Color.white)
    }
}

#Preview("Appearance Picker") {
    PreviewStateContainer(AppearanceMode.system) { mode in
        DSAppearanceModePicker(selection: mode)
            .padding()
            .frame(width: 400)
    }
}
