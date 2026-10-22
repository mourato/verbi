import SwiftUI

public struct PressableButtonStyle: ButtonStyle {
    private let pressedScale: CGFloat
    private let pressedOpacity: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(pressedScale: CGFloat = 0.97, pressedOpacity: Double = 0.82) {
        self.pressedScale = pressedScale
        self.pressedOpacity = pressedOpacity
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : scale(isPressed: configuration.isPressed))
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(
                AppleMotion.animation(reduceMotion: reduceMotion, kind: .press),
                value: configuration.isPressed
            )
    }

    private func scale(isPressed: Bool) -> CGFloat {
        isPressed ? pressedScale : 1
    }
}

public extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle {
        PressableButtonStyle()
    }
}
