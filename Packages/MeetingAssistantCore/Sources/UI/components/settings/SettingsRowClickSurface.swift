import SwiftUI

public struct SettingsRowButtonStyle: ButtonStyle {
    private let reduceMotion: Bool

    public init(reduceMotion: Bool = false) {
        self.reduceMotion = reduceMotion
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.isSettingsRowPressed, configuration.isPressed)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.99)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(
                AppleMotion.animation(reduceMotion: reduceMotion, kind: .press),
                value: configuration.isPressed,
            )
    }
}

extension EnvironmentValues {
    @Entry var isSettingsRowPressed: Bool = false
}

private struct SettingsRowContentWrapper<Content: View>: View {
    @Environment(\.isSettingsRowPressed) private var isPressed
    let content: (Bool) -> Content

    var body: some View {
        content(isPressed)
    }
}

public struct SettingsRowClickSurface<Content: View>: View {
    private let onSingleClick: (() -> Void)?
    private let onDoubleClick: (() -> Void)?
    private let content: (Bool) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        onSingleClick: (() -> Void)? = nil,
        onDoubleClick: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.onSingleClick = onSingleClick
        self.onDoubleClick = onDoubleClick
        self.content = { _ in content() }
    }

    public init(
        onSingleClick: (() -> Void)? = nil,
        onDoubleClick: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Bool) -> Content,
    ) {
        self.onSingleClick = onSingleClick
        self.onDoubleClick = onDoubleClick
        self.content = content
    }

    public var body: some View {
        let primaryAction = onSingleClick ?? onDoubleClick
        let rowButton = Button {
            primaryAction?()
        } label: {
            SettingsRowContentWrapper(content: content)
                .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowButtonStyle(reduceMotion: reduceMotion))

        if let onDoubleClick {
            rowButton.simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    onDoubleClick()
                },
            )
        } else {
            rowButton
        }
    }
}

#Preview("Settings Row Click Surface") {
    SettingsRowClickSurface(
        onSingleClick: {},
        onDoubleClick: {},
        content: {
            Text("Example row")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.quaternary)
        },
    )
    .frame(width: 320)
    .padding()
}
