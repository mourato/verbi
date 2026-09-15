import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

// MARK: - Assistant Settings Content

/// Content view for Assistant settings, designed for use inside a footerless ModeEditorDrawer.
/// Preserves capability toggle, shortcut editor, visual feedback section,
/// and preview lifecycle management from the former Assistant settings page.
public struct AssistantSettingsContent: View {
    private enum Constants {
        static let previewDurationNanoseconds: UInt64 = 2_000_000_000
    }

    private enum CapabilityLayout {
        static let disabledOpacity = 0.58
    }

    @StateObject private var viewModel = AssistantShortcutSettingsViewModel()
    @StateObject private var settings = AppSettingsStore.shared
    @State private var previewController: AssistantScreenBorderController?
    @State private var previewTask: Task<Void, Never>?
    @State private var isPreviewRunning = false
    @State private var glowSizeInput = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let onClose: () -> Void

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    public var body: some View {
        ModeEditorDrawer(
            headerStyle: .close,
            title: "settings.section.assistant".localized,
            iconSymbol: "sparkle",
            onClose: onClose
        ) {
            Form {
                Section {
                    SettingsCapabilityHeaderToggle(
                        titleKey: "settings.capabilities.assistant",
                        isOn: $settings.isAssistantEnabled
                    )
                }

                assistantControlsSection
                    .disabled(!settings.isAssistantEnabled)
                    .opacity(settings.isAssistantEnabled ? 1 : CapabilityLayout.disabledOpacity)

                visualFeedbackSection
                    .disabled(!settings.isAssistantEnabled)
                    .opacity(settings.isAssistantEnabled ? 1 : CapabilityLayout.disabledOpacity)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            glowSizeInput = String(Int(viewModel.glowSize))
        }
        .onChange(of: viewModel.glowSize) { _, newValue in
            let normalized = String(Int(newValue))
            if glowSizeInput != normalized {
                glowSizeInput = normalized
            }
        }
        .onDisappear {
            stopPreviewIfNeeded()
        }
        .onChange(of: settings.isAssistantEnabled) { _, isEnabled in
            if !isEnabled {
                stopPreviewIfNeeded()
            }
        }
        .animation(
            SettingsMotion.sectionAnimation(reduceMotion: reduceMotion),
            value: settings.isAssistantEnabled
        )
    }

    private var assistantControlsSection: some View {
        ShortcutSettingsSection(
            groupTitle: "settings.assistant.controls".localized,
            groupIcon: "sparkles",
            descriptionText: "settings.assistant.toggle_command_desc".localized,
            settingsContent: {
                VStack(alignment: .leading, spacing: 12) {
                    if let healthPresentation = viewModel.shortcutCaptureHealthPresentation {
                        ShortcutCaptureHealthStatusView(presentation: healthPresentation) {
                            viewModel.openShortcutCaptureHealthAction()
                        }
                    }

                    DSModifierShortcutEditor(
                        shortcut: $viewModel.assistantShortcutDefinition,
                        conflictMessage: viewModel.assistantModifierConflictMessage
                    )
                }
            }
        )
    }

    private var visualFeedbackSection: some View {
        Section {
            HStack(spacing: 8) {
                previewButton
                if isPreviewRunning {
                    Label("settings.assistant.preview_running".localized, systemImage: "waveform.path")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .opacity(reduceMotion ? 1 : 0.75)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                            value: isPreviewRunning
                        )
                }
                Spacer()
            }

            Text("settings.assistant.visual_feedback_desc".localized)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("settings.assistant.border_style".localized, selection: $viewModel.borderStyle) {
                ForEach(AssistantBorderStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)

            LabeledContent("settings.assistant.border_color".localized) {
                DSThemePicker(selection: $viewModel.borderColor, circleSpacing: 4, itemFrameSize: 34)
            }

            if viewModel.borderStyle == .stroke {
                Picker("settings.assistant.border_width".localized, selection: borderWidthSelection) {
                    ForEach(AssistantShortcutSettingsViewModel.borderWidthOptions, id: \.self) { option in
                        Text("\(Int(option)) pt").tag(option)
                    }
                }
                .pickerStyle(.menu)
            } else {
                LabeledContent("settings.assistant.glow_size".localized) {
                    HStack(spacing: 8) {
                        TextField("", text: glowSizeInputBinding)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 56)
                        Text("pt")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
        } header: {
            SettingsFormSectionHeader(title: "settings.assistant.visual_feedback".localized, icon: "rectangle.inset.filled")
        }
    }

    private var previewButton: some View {
        Button("settings.assistant.preview".localized) {
            runVisualFeedbackPreview()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(isPreviewRunning)
    }

    private var borderWidthSelection: Binding<Double> {
        Binding(
            get: { nearestBorderWidthOption(for: viewModel.borderWidth) },
            set: { viewModel.borderWidth = $0 }
        )
    }

    private var glowSizeInputBinding: Binding<String> {
        Binding(
            get: { glowSizeInput },
            set: { newValue in
                let digitsOnly = String(newValue.filter(\.isNumber))
                glowSizeInput = digitsOnly
                if let numericValue = Int(digitsOnly) {
                    viewModel.glowSize = Double(numericValue)
                } else if digitsOnly.isEmpty {
                    viewModel.glowSize = 0
                }
            }
        )
    }

    private func nearestBorderWidthOption(for value: Double) -> Double {
        AssistantShortcutSettingsViewModel.borderWidthOptions.min(
            by: { abs($0 - value) < abs($1 - value) }
        ) ?? AssistantShortcutSettingsViewModel.borderWidthOptions[1]
    }

    private func runVisualFeedbackPreview() {
        guard !isPreviewRunning else { return }

        let settings = AppSettingsStore.shared
        settings.assistantBorderStyle = viewModel.borderStyle
        settings.assistantBorderWidth = nearestBorderWidthOption(for: viewModel.borderWidth)
        settings.assistantGlowSize = max(0, viewModel.glowSize)

        let controller = AssistantScreenBorderController(settingsStore: settings)
        previewController = controller
        isPreviewRunning = true
        controller.show()

        previewTask?.cancel()
        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Constants.previewDurationNanoseconds)
            controller.hide()
            previewController = nil
            isPreviewRunning = false
        }
    }

    private func stopPreviewIfNeeded() {
        previewTask?.cancel()
        previewTask = nil
        previewController?.hide()
        previewController = nil
        isPreviewRunning = false
    }
}

#Preview("Assistant Drawer") {
    AssistantSettingsContent(onClose: {})
        .frame(width: 400, height: 640)
}
