import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct DSThemePicker: View {
    @Binding private var selection: AppThemeColor
    private let circleSpacing: CGFloat
    private let itemFrameSize: CGFloat

    public init(
        selection: Binding<AppThemeColor>,
        circleSpacing: CGFloat = 12,
        itemFrameSize: CGFloat = 40
    ) {
        _selection = selection
        self.circleSpacing = circleSpacing
        self.itemFrameSize = itemFrameSize
    }

    public var body: some View {
        HStack(spacing: circleSpacing) {
            ForEach(AppThemeColor.allCases, id: \.self) { color in
                colorCircle(color)
            }
        }
    }

    @ViewBuilder
    private func colorCircle(_ color: AppThemeColor) -> some View {
        let isSelected = selection == color

        Button {
            selection = color
        } label: {
            ZStack {
                if color == .system {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                center: .center
                            )
                        )
                } else {
                    Circle()
                        .fill(Color(nsColor: color.nsColor))
                }
            }
            .frame(width: 28, height: 28)
            .overlay {
                if isSelected {
                    Circle()
                        .stroke(color == .system ? AppDesignSystem.Colors.settingsCardStroke : Color(nsColor: color.nsColor), lineWidth: 3)
                        .frame(width: 36, height: 36)
                }
            }
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(color == .system ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.white))
                        .shadow(color: .black.opacity(color == .system ? 0.1 : 0.3), radius: 1, x: 0, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: itemFrameSize, height: itemFrameSize)
        .contentShape(Rectangle())
    }
}

#Preview("Theme Picker") {
    PreviewStateContainer(AppThemeColor.system) { selection in
        DSThemePicker(selection: selection)
            .padding()
    }
}
