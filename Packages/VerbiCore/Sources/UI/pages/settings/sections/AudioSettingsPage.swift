import SwiftUI
import VerbiCoreAI
import VerbiCoreAudio
import VerbiCoreCommon
import VerbiCoreData
import VerbiCoreDomain
import VerbiCoreInfrastructure

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
public struct AudioSettingsPage: View {
    @State var viewModel = GeneralSettingsViewModel()
    @State private var isPreviewingSound = false
    @State private var previewResetTask: Task<Void, Never>?
    @State var selectedCustomPowerSource = PowerSourceStateProvider().currentPowerSourceState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let showsHeader: Bool

    public init(showsHeader: Bool = true) {
        self.showsHeader = showsHeader
    }

    public var body: some View {
        SettingsFormPage {
            VStack(alignment: .leading, spacing: 8) {
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
                        selection: $viewModel.recordingMediaHandlingMode
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
                                        in: 0 ... 100,
                                        step: 1
                                    )
                                    .controlSize(.small)
                                    .frame(minWidth: 120, maxWidth: 220)

                                    Image(systemName: "speaker.wave.2")
                                        .foregroundStyle(.secondary)

                                    Text(
                                        String(
                                            format: "settings.general.audio_ducking_percent".localized,
                                            viewModel.audioDuckingLevelPercent
                                        )
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
                        isOn: $viewModel.autoIncreaseMicrophoneVolume
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
                        isOn: $viewModel.removeSilenceBeforeProcessing
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
                    isOn: $viewModel.soundFeedbackEnabled.animated()
                )

                if viewModel.soundFeedbackEnabled {
                    soundCuePickerRow
                        .transition(SettingsMotion.sectionTransition(reduceMotion: reduceMotion))

                    soundVolumeSliderRow
                        .transition(SettingsMotion.sectionTransition(reduceMotion: reduceMotion))
                }
            } header: {
                SettingsFormSectionHeader(title: "settings.general.sound_feedback".localized, icon: "speaker.wave.2.fill")
            }
        }
    }

    private var soundCuePickerRow: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Picker(
                    "settings.general.sound_feedback.sound".localized,
                    selection: soundFeedbackCueBinding
                ) {
                    ForEach(SoundFeedbackCue.allCases) { cue in
                        Text(cue.displayName).tag(cue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("settings.general.sound_feedback.sound".localized)

                Button {
                    previewCue(viewModel.soundFeedbackCue)
                } label: {
                    Image(systemName: isPreviewingSound ? "speaker.wave.2.circle.fill" : "play.circle.fill")
                        .font(.title3)
                        .settingsPulseSymbolEffect(
                            isActive: isPreviewingSound,
                            reduceMotion: reduceMotion
                        )
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("settings.general.sound_feedback.preview".localized)
                .accessibilityHint("settings.general.sound_feedback.preview_hint".localized)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("settings.general.sound_feedback.sound".localized)
                Text("settings.general.sound_feedback.sound_desc".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var soundVolumeSliderRow: some View {
        LabeledContent("settings.general.sound_feedback.volume".localized) {
            HStack(spacing: 10) {
                Image(systemName: "speaker.slash")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Slider(
                    value: soundFeedbackVolumeSliderBinding,
                    in: 0 ... 100,
                    step: 5
                ) { editing in
                    if !editing {
                        SoundFeedbackService.shared.previewAtVolume(
                            viewModel.soundFeedbackVolume,
                            cue: viewModel.soundFeedbackCue
                        )
                    }
                }
                .controlSize(.small)
                .frame(minWidth: 120, maxWidth: 220)
                .accessibilityLabel("settings.general.sound_feedback.volume".localized)
                .accessibilityValue(soundFeedbackVolumeLabel)

                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(soundFeedbackVolumeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 36, alignment: .trailing)
            }
        }
    }

    private var soundFeedbackCueBinding: Binding<SoundFeedbackCue> {
        Binding(
            get: { viewModel.soundFeedbackCue },
            set: { newCue in
                viewModel.soundFeedbackCue = newCue
                previewCue(newCue)
            }
        )
    }

    private var soundFeedbackVolumeSliderBinding: Binding<Double> {
        Binding(
            get: { Double((viewModel.soundFeedbackVolume * 100).rounded()) },
            set: { viewModel.soundFeedbackVolume = Float($0 / 100.0) }
        )
    }

    private var soundFeedbackVolumeLabel: String {
        String(
            format: "settings.general.sound_feedback.volume_percent".localized,
            Int((viewModel.soundFeedbackVolume * 100).rounded())
        )
    }

    private var audioDuckingSliderBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.audioDuckingLevelPercent) },
            set: { viewModel.audioDuckingLevelPercent = Int($0.rounded()) }
        )
    }

    private func previewCue(_ cue: SoundFeedbackCue) {
        previewResetTask?.cancel()
        isPreviewingSound = true
        SoundFeedbackService.shared.preview(cue)
        previewResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            isPreviewingSound = false
        }
    }
}

#Preview {
    AudioSettingsPage()
}
