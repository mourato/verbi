import AppKit
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

/// Floating indicator view that shows waveform during recording and a dedicated status during processing.
public struct FloatingRecordingIndicatorView: View {
    @ObservedObject var audioMonitor: AudioLevelMonitor
    @ObservedObject var recordingManager: RecordingManager
    @ObservedObject var settingsStore: AppSettingsStore
    let navigationService = NavigationService.shared
    let style: RecordingIndicatorStyle
    let renderState: RecordingIndicatorRenderState
    let processingSnapshot: RecordingIndicatorProcessingSnapshot?
    let isAnimationActive: Bool
    let previewLanguageOverride: DictationOutputLanguage?
    let onStop: @Sendable () -> Void
    let onCancel: @Sendable () -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var isHovering = false
    @State var hoverCollapseTask: Task<Void, Never>?
    @State var isMainRegionHovered = false
    @State var isPromptRegionHovered = false
    @State var isPromptSessionArmed = false
    @State var isSilenceWarningDialogPresented = false
    @State private var isAccessibilityControlsRevealed = false
    @FocusState var isKeyboardFocused: Bool

    public init(
        audioMonitor: AudioLevelMonitor,
        style: RecordingIndicatorStyle,
        renderState: RecordingIndicatorRenderState,
        processingSnapshot: RecordingIndicatorProcessingSnapshot? = nil,
        isAnimationActive: Bool = true,
        previewLanguageOverride: DictationOutputLanguage? = nil,
        recordingManager: RecordingManager = .shared,
        settingsStore: AppSettingsStore = .shared,
        onStop: @escaping @Sendable () -> Void,
        onCancel: @escaping @Sendable () -> Void
    ) {
        self.audioMonitor = audioMonitor
        self.style = style
        self.renderState = renderState
        self.processingSnapshot = processingSnapshot
        self.isAnimationActive = isAnimationActive
        self.previewLanguageOverride = previewLanguageOverride
        _recordingManager = ObservedObject(wrappedValue: recordingManager)
        _settingsStore = ObservedObject(wrappedValue: settingsStore)
        self.onStop = onStop
        self.onCancel = onCancel
    }

    public var body: some View {
        switch renderState.mode {
        case .error:
            errorView
        case .confirmingAutomaticMeetingStart:
            switch style {
            case .classic:
                confirmationPill(size: .classic)
            case .mini:
                confirmationPill(size: .mini)
            case .super:
                confirmationPill(size: .super)
            case .none:
                EmptyView()
            }
        case .starting, .recording, .processing:
            switch style {
            case .classic:
                indicatorPill(size: .classic)
            case .mini:
                indicatorPill(size: .mini)
            case .super:
                superIndicatorCard
            case .none:
                EmptyView()
            }
        }
    }

    // MARK: - Indicator Pill

    enum IndicatorSize {
        case classic
        case mini
        case `super`
    }

    enum SuperActionKind {
        case stop
        case cancel
    }

    func indicatorPill(size: IndicatorSize) -> some View {
        HStack(spacing: AppDesignSystem.Layout.recordingIndicatorPromptGap) {
            mainPill(size: size)

            if showsExternalPromptSelector {
                promptSelectionPill(size: size)
            }

            if showsExternalLanguageSelector {
                languageSelectionPill(size: size)
            }
        }
        .onDisappear {
            hoverCollapseTask?.cancel()
            hoverCollapseTask = nil
            isMainRegionHovered = false
            isPromptRegionHovered = false
            isPromptSessionArmed = false
            isKeyboardFocused = false
            resetAccessibilityControls()
        }
        .onChange(of: isRecordingMode) { _, isRecording in
            if !isRecording {
                resetAccessibilityControls()
            }
        }
        // Keep warning overlays out of layout sizing to prevent NSPanel constraint loops
        // when warnings appear/disappear while the panel uses a fixed content size.
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
            y: AppDesignSystem.Layout.shadowY
        )
    }

    /// Keeps VoiceOver-revealed controls visible while the user navigates into them.
    var revealsExpandedControls: Bool {
        guard isRecordingMode else { return false }
        return isHovering || isKeyboardFocused || isAccessibilityControlsRevealed
    }

    func revealAccessibilityControls() {
        isAccessibilityControlsRevealed = true
    }

    func resetAccessibilityControls() {
        isAccessibilityControlsRevealed = false
    }
}
