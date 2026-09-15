import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

extension AudioSettingsTab {
    var audioInputMode: AudioInputMode {
        viewModel.useSystemDefaultInput ? .systemDefault : .customDevice
    }

    var audioInputModeBinding: Binding<AudioInputMode> {
        Binding(
            get: { audioInputMode },
            set: { mode in
                viewModel.useSystemDefaultInput = mode == .systemDefault
                if mode == .customDevice {
                    selectedCustomPowerSource = viewModel.currentPowerSourceState
                }
            }
        )
    }

    var audioInputModePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: audioInputModeBinding) {
                ForEach(AudioInputMode.allCases) { mode in
                    Text(mode.titleKey.localized)
                        .tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 360, alignment: .leading)

            Text(audioInputMode.descriptionKey.localized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var systemDefaultDeviceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("settings.general.current_device".localized)
                .font(.subheadline)
                .fontWeight(.semibold)

            SettingsInlineList(
                items: [AudioDeviceOption(id: viewModel.systemDefaultInputDevice?.id ?? "__current_system_default__", device: viewModel.systemDefaultInputDevice)],
                emptyText: "settings.general.audio_devices_empty".localized,
                containerStyle: .plain
            ) { option in
                audioDeviceStatusRow(
                    iconSystemName: option.device == nil ? "desktopcomputer" : "mic.fill",
                    title: option.device?.name ?? "settings.general.device_not_selected".localized,
                    description: option.device == nil ? "settings.general.current_device_empty_desc".localized : "settings.general.current_device_desc".localized,
                    isSelected: false,
                    badges: option.device == nil ? [] : [BadgeConfig(title: "settings.general.device_active".localized, kind: .success)]
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    var customDeviceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("settings.general.power_based_microphone_desc".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            customPowerSourcePicker

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    Text("settings.general.available_devices".localized)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Spacer()

                    Button {
                        viewModel.refreshAudioInputDevices()
                    } label: {
                        Label("settings.general.refresh".localized, systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppDesignSystem.Colors.accent)
                }

                SettingsInlineList(
                    items: audioDeviceOptions(for: selectedCustomPowerSource),
                    emptyText: "settings.general.audio_devices_empty".localized,
                    containerStyle: .plain
                ) { option in
                    audioDeviceSelectionRow(option: option, powerSource: selectedCustomPowerSource)
                }
            }
        }
    }

    var selectedCustomPowerSourceBinding: Binding<String> {
        Binding(
            get: { selectedCustomPowerSource.rawValue },
            set: { rawValue in
                guard let powerSource = PowerSourceState(rawValue: rawValue) else { return }
                selectedCustomPowerSource = powerSource
            }
        )
    }

    var customPowerSourcePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: selectedCustomPowerSourceBinding) {
                Text("settings.general.microphone_when_charging".localized)
                    .tag(PowerSourceState.charging.rawValue)

                Text("settings.general.microphone_on_battery".localized)
                    .tag(PowerSourceState.battery.rawValue)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 360, alignment: .leading)

            Text(customPowerSourceDescriptionKey.localized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var customPowerSourceDescriptionKey: String {
        switch selectedCustomPowerSource {
        case .charging:
            "settings.general.microphone_when_charging_desc"
        case .battery:
            "settings.general.microphone_on_battery_desc"
        }
    }

    func audioDeviceOptions(for powerSource: PowerSourceState) -> [AudioDeviceOption] {
        let selectedUID = viewModel.microphoneUID(for: powerSource)
        let currentPowerSource = viewModel.currentPowerSourceState

        let sortedDevices = viewModel.availableDevices.sorted { lhs, rhs in
            let lhsRank = audioDeviceSortRank(device: lhs, selectedUID: selectedUID, powerSource: powerSource, currentPowerSource: currentPowerSource)
            let rhsRank = audioDeviceSortRank(device: rhs, selectedUID: selectedUID, powerSource: powerSource, currentPowerSource: currentPowerSource)

            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return sortedDevices.map { AudioDeviceOption(id: $0.id, device: $0) } + [.fallback]
    }

    func audioDeviceSortRank(
        device: AudioInputDevice,
        selectedUID: String?,
        powerSource: PowerSourceState,
        currentPowerSource: PowerSourceState
    ) -> Int {
        if device.id == selectedUID, powerSource == currentPowerSource {
            return 0
        }

        if device.id == selectedUID {
            return 1
        }

        if device.isDefault {
            return 2
        }

        if !device.isAvailable {
            return 4
        }

        return 3
    }

    func audioDeviceSelectionRow(option: AudioDeviceOption, powerSource: PowerSourceState) -> some View {
        let selectedUID = viewModel.microphoneUID(for: powerSource)
        let isSelected = option.device?.id == selectedUID || (option.device == nil && selectedUID == nil)
        let isActiveSelection = isSelected && powerSource == viewModel.currentPowerSourceState

        return Button {
            viewModel.setMicrophoneUID(option.device?.id, for: powerSource)
        } label: {
            audioDeviceStatusRow(
                iconSystemName: audioDeviceIconSystemName(for: option.device),
                title: option.device?.name ?? "settings.general.device_not_selected".localized,
                description: audioDeviceDescription(for: option.device),
                isSelected: isSelected,
                badges: audioDeviceBadges(for: option.device, isActiveSelection: isActiveSelection)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(audioDeviceAccessibilityLabel(for: option, powerSource: powerSource))
    }

    func audioDeviceStatusRow(
        iconSystemName: String,
        title: String,
        description: String?,
        isSelected: Bool,
        badges: [BadgeConfig]
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconSystemName)
                .foregroundStyle(isSelected ? AppDesignSystem.Colors.accent : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(AppDesignSystem.Colors.primaryTextStyle(isSelected: isSelected))

                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(AppDesignSystem.Colors.secondaryTextStyle(isSelected: isSelected))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                ForEach(badges) { badge in
                    DSBadge(badge.title, kind: badge.kind)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppDesignSystem.Colors.success)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? AppDesignSystem.Colors.selectionFill : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                .stroke(
                    isSelected ? AppDesignSystem.Colors.selectionStroke : Color.clear,
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius))
    }

    func audioDeviceDescription(for device: AudioInputDevice?) -> String? {
        guard let device else {
            return "settings.general.device_not_selected_desc".localized
        }

        if !device.isAvailable {
            return "settings.general.device_unavailable_desc".localized
        }

        return nil
    }

    func audioDeviceBadges(for device: AudioInputDevice?, isActiveSelection: Bool) -> [BadgeConfig] {
        var badges: [BadgeConfig] = []

        if isActiveSelection {
            badges.append(BadgeConfig(title: "settings.general.device_active".localized, kind: .success))
        }

        if let device {
            if !device.isAvailable {
                badges.append(BadgeConfig(title: "settings.general.device_unavailable".localized, kind: .warning))
            } else if device.isDefault {
                badges.append(BadgeConfig(title: "settings.general.device_default".localized, kind: .neutral))
            }
        }

        return badges
    }

    func audioDeviceIconSystemName(for device: AudioInputDevice?) -> String {
        guard let device else {
            return "arrow.uturn.backward.circle"
        }

        if !device.isAvailable {
            return "mic.slash"
        }

        return device.isDefault ? "mic.fill" : "mic"
    }

    func audioDeviceAccessibilityLabel(for option: AudioDeviceOption, powerSource: PowerSourceState) -> String {
        let powerSourceLabel = powerSource == .charging
            ? "settings.general.microphone_when_charging".localized
            : "settings.general.microphone_on_battery".localized

        let deviceName = option.device?.name ?? "settings.general.device_not_selected".localized
        return "\(powerSourceLabel): \(deviceName)"
    }
}

struct BadgeConfig: Identifiable {
    let id = UUID()
    let title: String
    let kind: DSBadge.Kind
}
