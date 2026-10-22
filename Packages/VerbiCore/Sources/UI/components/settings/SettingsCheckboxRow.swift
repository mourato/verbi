import SwiftUI

/// Checkbox-style boolean row for draft values committed by Save/Create/Apply.
public struct SettingsCheckboxRow: View {
    private let title: String
    private let description: String?
    @Binding private var isOn: Bool

    public init(_ title: String, description: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.description = description
        _isOn = isOn
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            if let description, !description.isEmpty {
                SettingsTitleWithPopover(title: title, helperMessage: description)
            } else {
                Text(title)
            }
        }
        .toggleStyle(.checkbox)
        .accessibilityLabel(title)
    }
}

#Preview("Settings Checkbox Row") {
    PreviewStateContainer(true) { isOn in
        Form {
            Section {
                SettingsCheckboxRow(
                    "Post-processing",
                    description: "Apply enhancement after transcription.",
                    isOn: isOn
                )
                SettingsCheckboxRow("Markdown output", isOn: .constant(false))
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
