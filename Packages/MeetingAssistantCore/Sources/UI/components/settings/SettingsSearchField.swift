import MeetingAssistantCoreCommon
import SwiftUI

struct SettingsSearchField: View {
    private enum Layout {
        static let height: CGFloat = 32
        static let horizontalPadding: CGFloat = 10
        static let cornerRadius: CGFloat = AppDesignSystem.Layout.largeCornerRadius
    }

    enum Style {
        case standard
        case history
    }

    @Binding var text: String
    let placeholder: String
    var style: Style = .standard

    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Environment(\.settingsReduceTransparencyPreview) private var reduceTransparencyPreview

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13, weight: .medium))

            TextField("", text: $text, prompt: Text(placeholder))
                .textFieldStyle(.plain)
                .focused($isFocused)
                .accessibilityLabel(placeholder)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("metrics.calendar.event.clear".localized)
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .frame(height: Layout.height)
        .background(cardBackground)
        .onExitCommand {
            if !text.isEmpty {
                text = ""
            } else {
                isFocused = false
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    @ViewBuilder
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)

        switch style {
        case .standard:
            shape
                .fill(AppDesignSystem.Colors.cardBackground)
                .overlay {
                    shape.strokeBorder(
                        isFocused ? Color.accentColor : AppDesignSystem.Colors.cardStroke,
                        lineWidth: isFocused ? 2 : 0.5,
                    )
                }
        case .history:
            shape
                .fill(
                    AppDesignSystem.Colors.settingsMaterialCardFill(
                        reduceTransparency: accessibilityReduceTransparency || reduceTransparencyPreview,
                        intensity: .subtle,
                    ),
                )
                .overlay {
                    shape.strokeBorder(
                        isFocused ? Color.accentColor : settingsCardStroke,
                        lineWidth: isFocused ? 2 : settingsCardStrokeWidth,
                    )
                }
        }
    }

    private var settingsCardStroke: Color {
        AppDesignSystem.Colors.settingsMaterialCardStroke(
            increaseContrast: AppDesignSystem.Accessibility.increaseContrast,
        )
    }

    private var settingsCardStrokeWidth: CGFloat {
        AppDesignSystem.Accessibility.increaseContrast ? 0.75 : 0.5
    }
}

#Preview("Settings Search Field") {
    @Previewable @State var searchText = "Transcript"

    return VStack(spacing: 16) {
        SettingsSearchField(
            text: $searchText,
            placeholder: "settings.transcriptions.search_placeholder".localized,
            style: .history,
        )

        SettingsSearchField(
            text: .constant(""),
            placeholder: "settings.transcriptions.search_placeholder".localized,
            style: .history,
        )

        SettingsSearchField(
            text: .constant(""),
            placeholder: "settings.transcriptions.search_placeholder".localized,
            style: .standard,
        )
    }
    .padding(16)
    .frame(width: 360)
}
