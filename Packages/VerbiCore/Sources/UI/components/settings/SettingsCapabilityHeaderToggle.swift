import SwiftUI

/// Immediate-effect capability toggle for Meetings, Assistant, and Integrations headers.
public struct SettingsCapabilityHeaderToggle: View {
    private let titleKey: String
    @Binding private var isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(titleKey: String, isOn: Binding<Bool>) {
        self.titleKey = titleKey
        _isOn = isOn
    }

    public var body: some View {
        Toggle(titleKey.localized, isOn: $isOn.animated(using: SettingsMotion.sectionAnimation))
            .toggleStyle(.switch)
            .accessibilityLabel(titleKey.localized)
            .animation(SettingsMotion.sectionAnimation(reduceMotion: reduceMotion), value: isOn)
    }
}

#Preview {
    SettingsCapabilityHeaderToggle(titleKey: "settings.capabilities.assistant", isOn: .constant(true))
        .padding()
}
