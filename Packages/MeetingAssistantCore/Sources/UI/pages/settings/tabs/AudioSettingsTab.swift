import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

// MARK: - Audio Settings Tab

enum AudioInputMode: CaseIterable, Identifiable, Hashable {
    case systemDefault
    case customDevice

    var id: Self {
        self
    }

    var titleKey: String {
        switch self {
        case .systemDefault:
            "settings.general.audio_input_mode.system_default"
        case .customDevice:
            "settings.general.audio_input_mode.custom_device"
        }
    }

    var descriptionKey: String {
        switch self {
        case .systemDefault:
            "settings.general.audio_input_mode.system_default_desc"
        case .customDevice:
            "settings.general.audio_input_mode.custom_device_desc"
        }
    }
}

struct AudioDeviceOption: Identifiable {
    let id: String
    let device: AudioInputDevice?

    static let fallback = AudioDeviceOption(id: "__system_default_fallback__", device: nil)
}

/// Tab for shared audio hardware settings like devices, formats, and system muting.
public struct AudioSettingsTab: View {
    @State var viewModel = GeneralSettingsViewModel()
    @State private var previewingSound: SoundFeedbackSound?
    @State private var previewResetTask: Task<Void, Never>?
    @State var selectedCustomPowerSource = PowerSourceStateProvider().currentPowerSourceState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let showsHeader: Bool
    private let onBack: (() -> Void)?

    public init(showsHeader: Bool = true, onBack: (() -> Void)? = nil) {
        self.showsHeader = showsHeader
        self.onBack = onBack
    }

    public var body: some View {
        SettingsFormPage {
            VStack(alignment: .leading, spacing: 8) {
                if let onBack {
                    SettingsChildPageBackButton(action: onBack)
                }
                SettingsFormSectionHeader(title: "settings.section.audio".localized, icon: "waveform.path")
                if showsHeader {
                    Text("settings.general.audio_devices_desc".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } content: {
            Section {
                Picker("settings.general.audio_format".localized, selection: $viewModel.audioFormat) {
                    ForEach(AppSettingsStore.AudioFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                SettingsFormSectionHeader(title: "settings.general.audio_format".localized, icon: "waveform.path")
            }

            // Audio Devices
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    audioInputModePicker

                    if audioInputMode == .systemDefault {
                        systemDefaultDeviceSection
                            .transition(SettingsMotion.sectionTransition(reduceMotion: reduceMotion))
                    } else {
                        customDeviceSection
                            .transition(SettingsMotion.sectionTransition(reduceMotion: reduceMotion))
                    }

                    Divider()

                    Picker(
                        "settings.general.recording_media_handling".localized,
                        selection: $viewModel.recordingMediaHandlingMode,
                    ) {
                        ForEach(AppSettingsStore.RecordingMediaHandlingMode.allCases, id: \.self) { mode in
                            Text(mode.displayNameKey.localized).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    if viewModel.usesDuckingControls {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("settings.general.audio_ducking".localized) {
                                HStack(spacing: 10) {
                                    Image(systemName: "speaker.slash")
                                        .foregroundStyle(.secondary)

                                    Slider(
                                        value: audioDuckingSliderBinding,
                                        in: 0...100,
                                        step: 1,
                                    )
                                    .controlSize(.small)
                                    .frame(minWidth: 120, maxWidth: 220)

                                    Image(systemName: "speaker.wave.2")
                                        .foregroundStyle(.secondary)

                                    Text(
                                        String(
                                            format: "settings.general.audio_ducking_percent".localized,
                                            viewModel.audioDuckingLevelPercent,
                                        ),
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(minWidth: 36, alignment: .trailing)
                                }
                            }

                            Text("settings.general.audio_ducking_note".localized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            if viewModel.recordingMediaHandlingMode == .pauseMedia {
                                Text("settings.general.recording_media_handling_pause_note".localized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .transition(SettingsMotion.sectionTransition(reduceMotion: reduceMotion))
                    }

                    Divider()

                    DSToggleRow(
                        "settings.general.auto_increase_microphone_volume".localized,
                        tooltip: "settings.general.auto_increase_microphone_volume_tooltip".localized,
                        isOn: $viewModel.autoIncreaseMicrophoneVolume,
                    )
                }
            } header: {
                SettingsFormSectionHeader(title: "settings.general.audio_devices".localized, icon: "mic.fill")
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    DSToggleRow(
                        "settings.general.remove_silence_before_processing".localized,
                        description: "settings.general.remove_silence_before_processing_desc".localized,
                        isOn: $viewModel.removeSilenceBeforeProcessing,
                    )

                    Text("settings.general.remove_silence_before_processing_note".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                SettingsFormSectionHeader(title: "settings.general.audio_processing".localized, icon: "waveform.badge.minus")
            }

            // Sound Feedback
            Section {
                DSToggleRow(
                    "settings.general.sound_feedback.enabled".localized,
                    description: "settings.general.sound_feedback.enabled_desc".localized,
                    isOn: $viewModel.soundFeedbackEnabled.animated(),
                )

                if viewModel.soundFeedbackEnabled {
                    soundPickerRow(
                        title: "settings.general.sound_feedback.start_sound".localized,
                        selection: $viewModel.recordingStartSound,
                    )

                    soundPickerRow(
                        title: "settings.general.sound_feedback.stop_sound".localized,
                        selection: $viewModel.recordingStopSound,
                    )
                    .transition(SettingsMotion.sectionTransition(reduceMotion: reduceMotion))
                }
            } header: {
                SettingsFormSectionHeader(title: "settings.general.sound_feedback".localized, icon: "speaker.wave.2.fill")
            }

        }
    }

    private func soundPickerRow(title: String, selection: Binding<SoundFeedbackSound>) -> some View {
        HStack {
            SettingsTitleWithPopover(title: title)

            Spacer()

            Picker(title, selection: selection) {
                ForEach(SoundFeedbackSound.allCases, id: \.self) { sound in
                    Text(sound.displayName).tag(sound)
                }
            }
            .pickerStyle(.menu)

            Button {
                previewSound(selection.wrappedValue)
            } label: {
                Image(systemName: previewingSound == selection.wrappedValue ? "speaker.wave.2.circle.fill" : "play.circle.fill")
                    .font(.title3)
                    .settingsPulseSymbolEffect(
                        isActive: previewingSound == selection.wrappedValue,
                        reduceMotion: reduceMotion,
                    )
            }
            .buttonStyle(.borderless)
            .disabled(selection.wrappedValue == .none)
            .accessibilityLabel("settings.general.sound_feedback.preview".localized)
            .accessibilityHint("settings.general.sound_feedback.enabled_desc".localized)
        }
    }

    private var audioDuckingSliderBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.audioDuckingLevelPercent) },
            set: { viewModel.audioDuckingLevelPercent = Int($0.rounded()) },
        )
    }

    private func previewSound(_ sound: SoundFeedbackSound) {
        guard sound != .none else { return }
        previewResetTask?.cancel()
        previewingSound = sound
        SoundFeedbackService.shared.preview(sound)
        previewResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            previewingSound = nil
        }
    }
}

#Preview {
    AudioSettingsTab()
}
