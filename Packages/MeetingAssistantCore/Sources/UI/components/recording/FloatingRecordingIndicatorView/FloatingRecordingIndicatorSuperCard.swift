import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

extension FloatingRecordingIndicatorView {
    var superIndicatorCard: some View {
        VStack(spacing: 0) {
            recordingCluster(size: .super)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, AppDesignSystem.Layout.recordingIndicatorSuperHorizontalPadding)
                .padding(.vertical, AppDesignSystem.Layout.recordingIndicatorSuperVerticalPadding)

            if FloatingRecordingIndicatorViewUtilities.superShowsFooter(
                layout: overlayLayout,
                renderState: renderState
            ) {
                Rectangle()
                    .fill(AppDesignSystem.Colors.overlayDivider)
                    .frame(height: 1)

                superFooter
                    .padding(.horizontal, AppDesignSystem.Layout.recordingIndicatorSuperHorizontalPadding)
                    .padding(.vertical, AppDesignSystem.Layout.recordingIndicatorSuperVerticalPadding / 2)
            }
        }
        .frame(
            width: FloatingRecordingIndicatorViewUtilities.superCardWidth(
                layout: overlayLayout,
                renderState: renderState,
                processingSnapshot: activeProcessingSnapshot
            )
        )
        .background(.ultraThinMaterial)
        .background(AppDesignSystem.Colors.recordingIndicatorMaterialTint)
        .overlay(
            RoundedRectangle(
                cornerRadius: AppDesignSystem.Layout.recordingIndicatorSuperCornerRadius,
                style: .continuous
            )
            .strokeBorder(AppDesignSystem.Colors.recordingIndicatorStroke, lineWidth: 1.2)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: AppDesignSystem.Layout.recordingIndicatorSuperCornerRadius,
                style: .continuous
            )
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: AppDesignSystem.Layout.recordingIndicatorSuperCornerRadius,
                style: .continuous
            )
        )
        .onDisappear {
            resetHoverState()
        }
        .overlay(alignment: .top) {
            VStack(spacing: 4) {
                if let warningDescriptor = postProcessingWarningDescriptor {
                    postProcessingReadinessWarningOverlay(warningDescriptor)
                        .transition(warningOverlayTransition)
                }

                if isRecordingMode, audioMonitor.isSilenceWarningVisible {
                    silenceWarningOverlay
                        .transition(warningOverlayTransition)
                }
            }
            .padding(.top, 2)
        }
        .shadow(
            color: .black.opacity(0.15),
            radius: AppDesignSystem.Layout.recordingIndicatorMainShadowRadius,
            x: AppDesignSystem.Layout.shadowX,
            y: AppDesignSystem.Layout.recordingIndicatorMainShadowY
        )
    }

    var superFooter: some View {
        HStack(spacing: FloatingRecordingIndicatorViewUtilities.superFooterGroupSpacing()) {
            if superFooterHasLeadingContent {
                superFooterLeadingContent
            }

            Spacer(minLength: 0)

            if isRecordingMode {
                HStack(spacing: FloatingRecordingIndicatorViewUtilities.superFooterSpacing()) {
                    superActionButton(kind: .stop)
                    superActionButton(kind: .cancel)
                }
            }
        }
        .frame(height: AppDesignSystem.Layout.recordingIndicatorSuperFooterHeight)
    }

    var superFooterHasLeadingContent: Bool {
        overlayLayout.showsPromptSelector
            || overlayLayout.showsLanguageSelector
            || showsMeetingMicrophoneControl
            || showsMeetingNotesControl
    }

    var superFooterLeadingContent: some View {
        HStack(spacing: FloatingRecordingIndicatorViewUtilities.superFooterSpacing()) {
            if overlayLayout.showsPromptSelector {
                promptFooterControl
            }

            if overlayLayout.showsLanguageSelector {
                languageFooterControl
            }

            if showsMeetingMicrophoneControl {
                superFooterIconControl(
                    symbol: recordingManager.isMeetingMicrophoneEnabled ? "mic.fill" : "mic.slash.fill",
                    helpKey: recordingManager.isMeetingMicrophoneEnabled
                        ? "recording_indicator.microphone.enabled.help"
                        : "recording_indicator.microphone.disabled.help",
                    style: recordingManager.isMeetingMicrophoneEnabled ? .neutral : .warning
                ) {
                    Task {
                        await recordingManager.toggleMeetingMicrophone()
                    }
                }
            }

            if showsMeetingNotesControl {
                superFooterIconControl(
                    symbol: recordingManager.isMeetingNotesPanelVisible ? "note.text" : "note.text.badge.plus",
                    helpKey: recordingManager.isMeetingNotesPanelVisible
                        ? "recording_indicator.meeting_notes.hide.help"
                        : "recording_indicator.meeting_notes.show.help"
                ) {
                    Task { @MainActor in
                        recordingManager.toggleMeetingNotesPanel()
                    }
                }
            }
        }
    }

    var promptFooterControl: some View {
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
                size: .super
            )
            superFooterChip {
                HStack(spacing: 6) {
                    Image(nsImage: promptIcon)
                        .renderingMode(.original)
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)

                    Text(currentPromptTitle)
                        .font(AppTypography.indicatorPromptFooterFont())
                        .foregroundStyle(AppDesignSystem.Colors.overlayForegroundMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(width: FloatingRecordingIndicatorViewUtilities.promptSize(for: .super), alignment: .leading)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("recording_indicator.prompt.help".localized)
        .accessibilityValue(currentPromptTitle)
        .help("recording_indicator.prompt.help".localized)
        .highPriorityGesture(TapGesture())
    }

    var languageFooterControl: some View {
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
                size: .super
            )
            superFooterChip {
                Image(nsImage: flagIcon)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .frame(width: FloatingRecordingIndicatorViewUtilities.superFooterIconWidth())
                    .accessibilityHidden(true)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("settings.rules_per_app.language.title".localized)
        .accessibilityValue(currentDictationOutputLanguage.localizedName)
        .help("settings.rules_per_app.language.title".localized)
        .highPriorityGesture(TapGesture())
    }

    func superFooterIconControl(
        symbol: String,
        helpKey: String,
        style: ActionIconButton.Style = .neutral,
        action: @escaping @Sendable () -> Void
    ) -> some View {
        Button(action: action) {
            superFooterChip {
                Image(systemName: symbol)
                    .font(AppTypography.indicatorFooterIconFont())
                    .foregroundStyle(iconForegroundStyle(for: style))
                    .frame(width: FloatingRecordingIndicatorViewUtilities.superFooterIconWidth())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(helpKey.localized)
        .help(helpKey.localized)
    }

    func superActionButton(kind: SuperActionKind) -> some View {
        let titleKey = switch kind {
        case .stop:
            "recording_indicator.super.stop"
        case .cancel:
            "recording_indicator.super.cancel"
        }
        let action = {
            switch kind {
            case .stop:
                onStop()
            case .cancel:
                onCancel()
            }
        }

        return Button(action: action) {
            Label {
                Text(titleKey.localized)
                    .font(AppTypography.indicatorActionFont())
                    .lineLimit(1)
            } icon: {
                Image(systemName: kind == .stop ? "arrow.up" : "trash")
                    .font(AppTypography.indicatorActionFont())
            }
            .foregroundStyle(superActionForegroundColor(for: kind))
            .padding(.horizontal, 12)
            .frame(minWidth: FloatingRecordingIndicatorViewUtilities.superActionWidth(kind: kind))
            .frame(height: 24)
            .background(superActionBackground(for: kind))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(superActionBorderColor(for: kind), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(
            kind == .stop
                ? "recording_indicator.super.stop.help".localized
                : "recording_indicator.super.cancel.help".localized
        )
    }

    func superFooterChip(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 0, content: content)
            .padding(.horizontal, AppDesignSystem.Layout.recordingIndicatorSuperFooterChipHorizontalPadding)
            .frame(height: FloatingRecordingIndicatorViewUtilities.superFooterChipHeight())
            .background(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(AppDesignSystem.Colors.recordingIndicatorStroke.opacity(0.85), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    func iconForegroundStyle(for style: ActionIconButton.Style) -> Color {
        switch style {
        case .neutral:
            AppDesignSystem.Colors.overlayForegroundMuted
        case .success:
            AppDesignSystem.Colors.success
        case .warning:
            AppDesignSystem.Colors.error
        }
    }

    func superActionForegroundColor(for kind: SuperActionKind) -> Color {
        switch kind {
        case .stop:
            .white
        case .cancel:
            AppDesignSystem.Colors.overlayForegroundMuted
        }
    }

    func superActionBackground(for kind: SuperActionKind) -> Color {
        switch kind {
        case .stop:
            AppDesignSystem.Colors.success.opacity(0.82)
        case .cancel:
            Color.white.opacity(0.05)
        }
    }

    func superActionBorderColor(for kind: SuperActionKind) -> Color {
        switch kind {
        case .stop:
            AppDesignSystem.Colors.success.opacity(0.9)
        case .cancel:
            AppDesignSystem.Colors.recordingIndicatorStroke.opacity(0.9)
        }
    }
}
