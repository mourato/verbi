import SwiftUI

enum SettingsMotion {
    static var sectionAnimation: Animation {
        AppleMotion.defaultSpring
    }

    static func sectionTransition(reduceMotion: Bool = false) -> AnyTransition {
        AppleMotion.transition(reduceMotion: reduceMotion, edge: .top)
    }

    static func sectionAnimation(reduceMotion: Bool) -> Animation? {
        AppleMotion.animation(reduceMotion: reduceMotion, kind: .default)
    }

    static func expandableAnimation(reduceMotion: Bool) -> Animation? {
        AppleMotion.disclosureAnimation(reduceMotion: reduceMotion)
    }

    static func sidePanelAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.32)
    }

    static func sidePanelTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .move(edge: .trailing).combined(with: .opacity)
    }
}

extension Binding {
    func animated(using animation: Animation = SettingsMotion.sectionAnimation) -> Binding<Value> {
        transaction(Transaction(animation: animation))
    }
}

extension View {
    func settingsAnimated(
        reduceMotion: Bool,
        animation: Animation = SettingsMotion.sectionAnimation,
        value: some Equatable
    ) -> some View {
        self.animation(reduceMotion ? AppleMotion.reduceMotionFade : animation, value: value)
    }

    @ViewBuilder
    func settingsPulseSymbolEffect(
        value: some Equatable,
        reduceMotion: Bool,
        options: SymbolEffectOptions = .repeating
    ) -> some View {
        if reduceMotion {
            self
        } else {
            symbolEffect(.pulse, options: options, value: value)
        }
    }

    @ViewBuilder
    func settingsPulseSymbolEffect(
        isActive: Bool,
        reduceMotion: Bool
    ) -> some View {
        if reduceMotion {
            self
        } else {
            symbolEffect(.pulse, isActive: isActive)
        }
    }
}
