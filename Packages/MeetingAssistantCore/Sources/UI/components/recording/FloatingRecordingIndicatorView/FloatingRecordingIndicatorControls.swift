import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

extension FloatingRecordingIndicatorView {
    func promptPickerControl(size: IndicatorSize) -> some View {
        Menu {
            Button {
                applyPostProcessingSelection(nil)
            } label: {
                Label(
                    "recording_indicator.prompt.none".localized,
                    systemImage: "nosign"
                )
            }

            Divider()

            ForEach(promptPickerPrompts) { prompt in
                Button {
                    applyPostProcessingSelection(prompt.id)
                } label: {
                    Label(prompt.title, systemImage: prompt.icon)
                }
            }
        } label: {
            let promptIcon = FloatingRecordingIndicatorViewUtilities.promptIconImage(
                symbolName: currentPromptIconName,
                size: size
            )
            Image(nsImage: promptIcon)
                .renderingMode(.original)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
                .accessibilityHidden(true)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("recording_indicator.prompt.help".localized)
        .accessibilityValue(currentPromptTitle)
        .help("recording_indicator.prompt.help".localized)
        .highPriorityGesture(TapGesture())
    }

    func languagePickerControl(size: IndicatorSize) -> some View {
        Menu {
            ForEach(DictationOutputLanguage.allCases, id: \.self) { language in
                Button {
                    recordingManager.setDictationSessionOutputLanguageOverride(language)
                } label: {
                    Text(language.displayName)
                }
            }
        } label: {
            let flagIcon = FloatingRecordingIndicatorViewUtilities.languageFlagImage(
                currentDictationOutputLanguage.flagEmoji,
                size: size
            )
            Image(nsImage: flagIcon)
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 24, height: 24, alignment: .center)
                .contentShape(Rectangle())
                .accessibilityHidden(true)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("settings.rules_per_app.language.title".localized)
        .accessibilityValue(currentDictationOutputLanguage.localizedName)
        .help("settings.rules_per_app.language.title".localized)
        .highPriorityGesture(TapGesture())
    }

    var promptPickerPrompts: [PostProcessingPrompt] {
        usesMeetingPromptSource ? settingsStore.meetingAvailablePrompts : settingsStore.dictationAvailablePrompts
    }

    var currentPromptIconName: String {
        if !usesMeetingPromptSource {
            if settingsStore.isDictationPostProcessingDisabled {
                return "nosign"
            }
            return (settingsStore.selectedDictationPrompt ?? .defaultPrompt).icon
        }

        if settingsStore.isMeetingPostProcessingDisabled {
            return "nosign"
        }

        return settingsStore.selectedPrompt?.icon ?? "doc.text"
    }

    var currentPromptTitle: String {
        if !usesMeetingPromptSource {
            if settingsStore.isDictationPostProcessingDisabled {
                return "recording_indicator.prompt.none".localized
            }
            return (settingsStore.selectedDictationPrompt ?? .defaultPrompt).title
        }

        if settingsStore.isMeetingPostProcessingDisabled {
            return "recording_indicator.prompt.none".localized
        }

        return settingsStore.selectedPrompt?.title ?? "recording_indicator.prompt.none".localized
    }

    func applyPostProcessingSelection(_ promptId: UUID?) {
        let selectionId = promptId ?? AppSettingsStore.noPostProcessingPromptId

        if !usesMeetingPromptSource {
            settingsStore.dictationSelectedPromptId = selectionId
            return
        }

        settingsStore.meetingTypeAutoDetectEnabled = false
        if recordingManager.currentMeeting?.type == .autodetect {
            recordingManager.overrideCurrentMeetingType(.general)
        }

        settingsStore.selectedPromptId = selectionId
    }

    /// Meeting mic/notes exist for the session; pill reveal is separate so super stays expanded.
    var showsMeetingMicrophoneControl: Bool {
        renderState.kind == .meeting && isRecordingMode
    }

    var showsMeetingNotesControl: Bool {
        renderState.kind == .meeting && isRecordingMode
    }

    var showsMeetingTimerInPill: Bool {
        overlayLayout.showsMeetingTimer && isRecordingMode
    }

    var showsExpandedMeetingMicrophoneControl: Bool {
        showsMeetingMicrophoneControl && revealsExpandedControls
    }

    var showsExpandedMeetingNotesControl: Bool {
        showsMeetingNotesControl && revealsExpandedControls
    }

    var meetingMicrophoneControl: some View {
        ActionIconButton(
            symbol: recordingManager.isMeetingMicrophoneEnabled ? "mic.fill" : "mic.slash.fill",
            helpKey: recordingManager.isMeetingMicrophoneEnabled
                ? "recording_indicator.microphone.enabled.help"
                : "recording_indicator.microphone.disabled.help",
            keyboardShortcut: nil,
            style: recordingManager.isMeetingMicrophoneEnabled ? .neutral : .warning
        ) {
            Task {
                await recordingManager.toggleMeetingMicrophone()
            }
        }
    }

    var meetingNotesControl: some View {
        ActionIconButton(
            symbol: recordingManager.isMeetingNotesPanelVisible ? "note.text" : "note.text.badge.plus",
            helpKey: recordingManager.isMeetingNotesPanelVisible
                ? "recording_indicator.meeting_notes.hide.help"
                : "recording_indicator.meeting_notes.show.help",
            keyboardShortcut: nil,
            style: .neutral
        ) {
            Task { @MainActor in
                recordingManager.toggleMeetingNotesPanel()
            }
        }
    }

    func inlinePromptControl(size: IndicatorSize) -> some View {
        promptPickerControl(size: size)
            .frame(
                width: FloatingRecordingIndicatorViewUtilities.promptSize(for: size),
                height: FloatingRecordingIndicatorViewUtilities.controlHeight(for: size)
            )
    }

    func inlineLanguageControl(size: IndicatorSize) -> some View {
        languagePickerControl(size: size)
            .frame(
                width: FloatingRecordingIndicatorViewUtilities.promptSize(for: size),
                height: FloatingRecordingIndicatorViewUtilities.controlHeight(for: size)
            )
    }

    var usesInlineDictationSelectors: Bool {
        renderState.kind == .dictation && (style == .classic || style == .mini)
    }

    var showsInlinePromptSelector: Bool {
        usesInlineDictationSelectors && revealsExpandedControls && overlayLayout.showsPromptSelector
    }

    var showsInlineLanguageSelector: Bool {
        usesInlineDictationSelectors && revealsExpandedControls && overlayLayout.showsLanguageSelector
    }

    var showsExternalPromptSelector: Bool {
        overlayLayout.showsPromptSelector && !usesInlineDictationSelectors && revealsExpandedControls
    }

    var showsExternalLanguageSelector: Bool {
        overlayLayout.showsLanguageSelector && !usesInlineDictationSelectors && revealsExpandedControls
    }

    func promptSelectionPill(size: IndicatorSize) -> some View {
        promptPickerControl(size: size)
            .frame(
                width: FloatingRecordingIndicatorViewUtilities.promptSize(for: size),
                height: FloatingRecordingIndicatorViewUtilities.controlHeight(for: size)
            )
            .background(.ultraThinMaterial)
            .background(AppDesignSystem.Colors.recordingIndicatorAuxiliaryBackground)
            .overlay(
                Capsule()
                    .strokeBorder(AppDesignSystem.Colors.recordingIndicatorStroke, lineWidth: 1)
            )
            .clipShape(Capsule())
            .onHover { hovering in
                handlePromptRegionHover(hovering)
            }
    }

    func languageSelectionPill(size: IndicatorSize) -> some View {
        languagePickerControl(size: size)
            .frame(
                width: FloatingRecordingIndicatorViewUtilities.promptSize(for: size),
                height: FloatingRecordingIndicatorViewUtilities.controlHeight(for: size)
            )
            .background(.ultraThinMaterial)
            .background(AppDesignSystem.Colors.recordingIndicatorAuxiliaryBackground)
            .overlay(
                Capsule()
                    .strokeBorder(AppDesignSystem.Colors.recordingIndicatorStroke, lineWidth: 1)
            )
            .clipShape(Capsule())
            .onHover { hovering in
                handlePromptRegionHover(hovering)
            }
    }

    func handleMainRegionHover(_ hovering: Bool) {
        guard isRecordingMode else { return }

        isMainRegionHovered = hovering
        if hovering {
            isPromptSessionArmed = true
            hoverCollapseTask?.cancel()
            if reduceMotion {
                isHovering = true
            } else {
                withAnimation(AppleMotion.interactiveSpring) {
                    isHovering = true
                }
            }
            return
        }

        collapseAfterDelayIfNeeded()
    }

    func handlePromptRegionHover(_ hovering: Bool) {
        guard isRecordingMode else { return }

        isPromptRegionHovered = hovering
        if hovering, isPromptSessionArmed {
            hoverCollapseTask?.cancel()
            return
        }

        collapseAfterDelayIfNeeded()
    }

    func collapseAfterDelayIfNeeded() {
        guard isRecordingMode else { return }
        guard !isMainRegionHovered else { return }
        if isPromptRegionHovered, isPromptSessionArmed {
            return
        }
        guard isHovering else { return }

        hoverCollapseTask?.cancel()
        hoverCollapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 110_000_000)
            guard !Task.isCancelled else { return }
            guard !isMainRegionHovered else { return }
            if isPromptRegionHovered, isPromptSessionArmed {
                return
            }

            if reduceMotion {
                isHovering = false
            } else {
                withAnimation(AppleMotion.interactiveSpring) {
                    isHovering = false
                }
            }
            isPromptSessionArmed = false
        }
    }

    var currentDictationOutputLanguage: DictationOutputLanguage {
        if let previewLanguageOverride {
            return previewLanguageOverride
        }
        return recordingManager.effectiveDictationOutputLanguageForCurrentRecording
    }
}
