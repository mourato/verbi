import AppKit
import SwiftUI

/// A native-feeling macOS segmented control with a "liquid glass" frosted material aesthetic.
///
/// Mimics the vibrancy, specular highlight, and backdrop-blur material found in macOS
/// toolbars (e.g., Apple Calendar's Day/Week/Month/Year switcher), while functioning
/// cleanly in both window toolbars and body views.
///
/// Features:
/// - Liquid frosted glass background using `.ultraThinMaterial` with specular border highlights
/// - Smooth animated sliding pill indicator via `matchedGeometryEffect`
/// - Respects `accessibilityReduceMotion` (instant switch) and `accessibilityReduceTransparency`
/// - Automatic support for Dark / Light appearances
/// - Optional `fillsWidth` mode to evenly distribute segment widths
/// - Supports arbitrary items with titles, system icons, or custom view builders
public struct DSGlassSegmentedControl<Item: Hashable, Content: View>: View {
    @Binding private var selection: Item
    private let items: [Item]
    private let fillsWidth: Bool
    private let content: (Item, Bool) -> Content

    @Namespace private var animationNamespace
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var hoveredItem: Item?

    // MARK: - Initializers

    /// Creates a segmented control with a custom view builder for each segment.
    public init(
        selection: Binding<Item>,
        items: [Item],
        fillsWidth: Bool = false,
        @ViewBuilder content: @escaping (Item, Bool) -> Content
    ) {
        _selection = selection
        self.items = items
        self.fillsWidth = fillsWidth
        self.content = content
    }

    /// Creates a segmented control with text titles and optional SF Symbol icons.
    public init(
        selection: Binding<Item>,
        items: [Item],
        fillsWidth: Bool = false,
        title: @escaping (Item) -> String,
        icon: ((Item) -> String?)? = nil
    ) where Content == AnyView {
        _selection = selection
        self.items = items
        self.fillsWidth = fillsWidth
        content = { item, isSelected in
            AnyView(
                HStack(spacing: AppDesignSystem.Layout.spacing6) {
                    if let iconName = icon?(item) {
                        Image(systemName: iconName)
                            .accessibilityHidden(true)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    }
                    Text(title(item))
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                }
            )
        }
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                segmentButton(for: item)
            }
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .padding(3)
        .background(trackBackground)
        .overlay(trackBorder)
        .clipShape(Capsule())
        .accessibilityElement(children: .contain)
    }

    // MARK: - Segment Button

    @ViewBuilder
    private func segmentButton(for item: Item) -> some View {
        let isSelected = selection == item
        let isHovered = hoveredItem == item && !isSelected

        Button {
            select(item)
        } label: {
            content(item, isSelected)
                .foregroundStyle(labelForeground(isSelected: isSelected))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                selectionPill
            } else if isHovered {
                hoverPill
            }
        }
        .onHover { hovering in
            hoveredItem = hovering ? item : nil
        }
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }

    // MARK: - Selection & Hover Indicators

    private var selectionPill: some View {
        Capsule()
            .fill(pillBackground)
            .overlay(pillBorder)
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.10),
                radius: colorScheme == .dark ? 3 : 2,
                x: 0,
                y: 1
            )
            .matchedGeometryEffect(id: "glass_selection_pill", in: animationNamespace)
    }

    private var hoverPill: some View {
        Capsule()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
            .transition(.opacity)
    }

    // MARK: - Styling Tokens

    @ViewBuilder
    private var trackBackground: some View {
        if reduceTransparency {
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.03))
                )
        }
    }

    private var trackBorder: some View {
        Capsule()
            .strokeBorder(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color.white.opacity(0.18), Color.white.opacity(0.04)]
                        : [Color.white.opacity(0.65), Color.black.opacity(0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.75
            )
    }

    private var pillBackground: some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(nsColor: .controlAccentColor).opacity(0.2))
        }

        if colorScheme == .dark {
            return AnyShapeStyle(Color.white.opacity(0.20))
        } else {
            return AnyShapeStyle(Color.white.opacity(0.92))
        }
    }

    private var pillBorder: some View {
        Capsule()
            .strokeBorder(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color.white.opacity(0.35), Color.white.opacity(0.08)]
                        : [Color.white, Color.white.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.5
            )
    }

    private func labelForeground(isSelected: Bool) -> some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.primary)
        } else {
            return AnyShapeStyle(Color.secondary)
        }
    }

    // MARK: - Actions

    private func select(_ item: Item) {
        if reduceMotion {
            selection = item
        } else {
            withAnimation(AppleMotion.animation(reduceMotion: reduceMotion, kind: .interactive)) {
                selection = item
            }
        }
    }
}

// MARK: - Previews

#Preview("DSGlassSegmentedControl") {
    VStack(spacing: 24) {
        PreviewStateContainer("dia") { selection in
            DSGlassSegmentedControl(
                selection: selection,
                items: ["dia", "semana", "mês", "ano"],
                title: { $0.capitalized }
            )
        }

        PreviewStateContainer("chat") { selection in
            DSGlassSegmentedControl(
                selection: selection,
                items: ["chat", "transcription", "notes"],
                fillsWidth: true,
                title: { $0.capitalized },
                icon: { item in
                    switch item {
                    case "chat": "bubble.left.and.bubble.right.fill"
                    case "transcription": "waveform"
                    default: "note.text"
                    }
                }
            )
        }
    }
    .padding(32)
    .background(Color(nsColor: .windowBackgroundColor))
}
