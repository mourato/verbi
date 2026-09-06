import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct DSShortcutControlsRow: View {
    private let title: String
    private let activationMode: Binding<ShortcutActivationMode>?
    private let selectedPresetKey: Binding<PresetShortcutKey>
    private let activationPickerWidth: CGFloat
    private let presetPickerWidth: CGFloat

    public init(
        title: String,
        selectedPresetKey: Binding<PresetShortcutKey>,
        presetPickerWidth: CGFloat = AppDesignSystem.Layout.smallPickerWidth,
    ) {
        self.title = title
        activationMode = nil
        self.selectedPresetKey = selectedPresetKey
        activationPickerWidth = AppDesignSystem.Layout.narrowPickerWidth
        self.presetPickerWidth = presetPickerWidth
    }

    public init(
        title: String,
        activationMode: Binding<ShortcutActivationMode>,
        selectedPresetKey: Binding<PresetShortcutKey>,
        activationPickerWidth: CGFloat = AppDesignSystem.Layout.narrowPickerWidth,
        presetPickerWidth: CGFloat = AppDesignSystem.Layout.smallPickerWidth,
    ) {
        self.title = title
        self.activationMode = activationMode
        self.selectedPresetKey = selectedPresetKey
        self.activationPickerWidth = activationPickerWidth
        self.presetPickerWidth = presetPickerWidth
    }

    public var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
            }

            Spacer()

            if let activationMode {
                DSMenuPicker(selection: activationMode, width: activationPickerWidth) {
                    ForEach(ShortcutActivationMode.allCases, id: \.self) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
            }

            DSMenuPicker(selection: selectedPresetKey, width: presetPickerWidth) {
                ForEach(PresetShortcutKey.allCases, id: \.self) { key in
                    Text(key.displayName).tag(key)
                }
            }
        }
    }
}

#Preview("Preset Shortcut") {
    PreviewStateContainer(PresetShortcutKey.optionCommand) { key in
        DSShortcutControlsRow(
            title: "Quick Recording Shortcut",
            selectedPresetKey: key,
        )
        .padding()
        .frame(width: 520)
    }
}

#Preview("Activation + Preset") {
    PreviewStateContainer(ShortcutActivationMode.holdOrToggle) { mode in
        PreviewStateContainer(PresetShortcutKey.rightCommand) { key in
            DSShortcutControlsRow(
                title: "Prisma Shortcut",
                activationMode: mode,
                selectedPresetKey: key,
            )
            .padding()
            .frame(width: 520)
        }
    }
}
