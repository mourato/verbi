import SwiftUI

/// Local back control for Settings child destinations and in-page stacks.
public struct SettingsChildPageBackButton: View {
    private let titleKey: String
    private let action: () -> Void

    public init(
        titleKey: String = "settings.section.settings",
        action: @escaping () -> Void
    ) {
        self.titleKey = titleKey
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(titleKey.localized, systemImage: "chevron.left")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityHint("common.back".localized)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        SettingsChildPageBackButton {}
        SettingsChildPageBackButton(titleKey: "settings.section.activity") {}
        SettingsChildPageBackButton(titleKey: "common.back") {}
    }
    .padding()
}
