import AppKit
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

// MARK: - Pulsing Animation Modifier

/// Modifier that adds a subtle pulsing animation.
struct PulsingModifier: ViewModifier {
    let isActive: Bool
    let speed: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.75 : 1.0)
            .scaleEffect(isPulsing ? 1.08 : 1.0)
            .onAppear { updateAnimation() }
            .onChange(of: isActive) { _, _ in updateAnimation() }
            .onChange(of: speed) { _, _ in updateAnimation() }
            .onChange(of: reduceMotion) { _, _ in updateAnimation() }
    }

    private func updateAnimation() {
        guard isActive, !reduceMotion else {
            isPulsing = false
            return
        }
        withAnimation(.easeInOut(duration: speed).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
}

struct ActionIconButton: View {
    enum Style {
        case neutral
        case success
        case warning
    }

    let symbol: String
    let helpKey: String
    let keyboardShortcut: KeyEquivalent?
    let style: Style
    let action: @Sendable () -> Void

    @State private var isHovered = false

    init(
        symbol: String,
        helpKey: String,
        keyboardShortcut: KeyEquivalent? = nil,
        style: Style = .neutral,
        action: @escaping @Sendable () -> Void
    ) {
        self.symbol = symbol
        self.helpKey = helpKey
        self.keyboardShortcut = keyboardShortcut
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(AppTypography.indicatorControlIconFont())
                .foregroundStyle(controlForeground)
                .frame(width: 28, height: 28)
                .background(controlBackground)
                .clipShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(helpKey.localized)
        .help(helpKey.localized)
        .onHover { hovering in
            isHovered = hovering
        }
        .modifier(KeyboardShortcutModifier(key: keyboardShortcut))
    }

    private var controlBackground: some ShapeStyle {
        switch style {
        case .neutral:
            if isHovered {
                return AnyShapeStyle(Color.white.opacity(0.14))
            }
            return AnyShapeStyle(Color.clear)
        case .success:
            if isHovered {
                return AnyShapeStyle(AppDesignSystem.Colors.success.opacity(0.85))
            }
            return AnyShapeStyle(AppDesignSystem.Colors.success.opacity(0.76))
        case .warning:
            if isHovered {
                return AnyShapeStyle(AppDesignSystem.Colors.error.opacity(0.82))
            }
            return AnyShapeStyle(AppDesignSystem.Colors.error.opacity(0.68))
        }
    }

    private var controlForeground: Color {
        switch style {
        case .warning:
            AppDesignSystem.Colors.overlayStatusForeground
        case .neutral, .success:
            AppDesignSystem.Colors.overlayForeground
        }
    }
}

struct KeyboardShortcutModifier: ViewModifier {
    let key: KeyEquivalent?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: [])
        } else {
            content
        }
    }
}

struct RecordingPostProcessingWarningDescriptor: Equatable {
    let issue: EnhancementsInferenceReadinessIssue
    let mode: IntelligenceKernelMode

    var settingsSection: String {
        SettingsSection.intelligence.rawValue
    }

    var localizedMessage: String {
        messageKey.localized(with: modeDisplayName)
    }

    var messageKey: String {
        switch issue {
        case .missingModel:
            "recording_indicator.post_processing_warning.missing_model"
        case .missingAPIKey:
            "recording_indicator.post_processing_warning.missing_api_key"
        case .invalidBaseURL:
            "recording_indicator.post_processing_warning.invalid_base_url"
        }
    }

    private var modeDisplayName: String {
        switch mode {
        case .meeting:
            "recording_indicator.post_processing_warning.mode.meeting".localized
        case .dictation:
            "recording_indicator.post_processing_warning.mode.dictation".localized
        case .assistant:
            "recording_indicator.post_processing_warning.mode.assistant".localized
        }
    }

    func openSettings(using openSection: (String) -> Void) {
        openSection(settingsSection)
    }
}

enum FloatingRecordingIndicatorViewUtilities {
    enum MainContentMode: Equatable {
        case waveform
        case processingStatus
    }

    static let actionButtonSize: CGFloat = 28
    static let dividerWidth: CGFloat = 1
    private static let confirmationSampleSeconds = 9

    static func mainContentMode(for renderState: RecordingIndicatorRenderState) -> MainContentMode {
        renderState.mode == .processing ? .processingStatus : .waveform
    }

    static func confirmationFont(for size: FloatingRecordingIndicatorView.IndicatorSize) -> NSFont {
        switch size {
        case .classic, .super:
            .systemFont(ofSize: 13, weight: .semibold)
        case .mini:
            .systemFont(ofSize: 12, weight: .semibold)
        }
    }

    static func confirmationMessageWidth(for size: FloatingRecordingIndicatorView.IndicatorSize) -> CGFloat {
        let sample = "recording_indicator.auto_meeting_confirmation.countdown.other".localized(
            with: confirmationSampleSeconds
        ) as NSString
        return ceil(sample.size(withAttributes: [.font: confirmationFont(for: size)]).width)
    }

    static func confirmationPillWidth(for size: FloatingRecordingIndicatorView.IndicatorSize) -> CGFloat {
        let elementWidths = [
            AppDesignSystem.Layout.recordingIndicatorDotSize,
            confirmationMessageWidth(for: size),
            actionButtonSize
        ]
        return (horizontalPadding(for: size, expanded: false) * 2)
            + elementWidths.reduce(0, +)
            + (CGFloat(elementWidths.count - 1) * contentSpacing(for: size))
    }

    static func controlHeight(for size: FloatingRecordingIndicatorView.IndicatorSize) -> CGFloat {
        switch size {
        case .classic:
            AppDesignSystem.Layout.recordingIndicatorClassicHeight
        case .mini:
            AppDesignSystem.Layout.recordingIndicatorMiniHeight
        case .super:
            AppDesignSystem.Layout.recordingIndicatorSuperFooterHeight
        }
    }

    static func contentSpacing(for size: FloatingRecordingIndicatorView.IndicatorSize) -> CGFloat {
        switch size {
        case .classic:
            AppDesignSystem.Layout.recordingIndicatorClassicInnerSpacing
        case .mini:
            AppDesignSystem.Layout.recordingIndicatorMiniInnerSpacing
        case .super:
            AppDesignSystem.Layout.recordingIndicatorSuperInnerSpacing
        }
    }

    static func controlSpacing(for size: FloatingRecordingIndicatorView.IndicatorSize) -> CGFloat {
        contentSpacing(for: size)
    }

    static func promptSize(for size: FloatingRecordingIndicatorView.IndicatorSize) -> CGFloat {
        switch size {
        case .classic:
            AppDesignSystem.Layout.recordingIndicatorClassicPromptSize
        case .mini:
            AppDesignSystem.Layout.recordingIndicatorMiniPromptSize
        case .super:
            AppDesignSystem.Layout.recordingIndicatorSuperPromptSize
        }
    }

    static func formatRecordingDuration(startTime: Date?, at date: Date) -> String {
        guard let startTime else { return "00:00" }

        let duration = max(0, date.timeIntervalSince(startTime))
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00"
    }

    static func timerReservedWidth(for size: FloatingRecordingIndicatorView.IndicatorSize) -> CGFloat {
        let sample = "00:00:00" as NSString
        return ceil(sample.size(withAttributes: [.font: timerFont(for: size)]).width)
    }

    static func timerFont(for _: FloatingRecordingIndicatorView.IndicatorSize) -> NSFont {
        AppTypography.indicatorTimerNSFont()
    }

    static func processingProgressReservedWidth(for size: FloatingRecordingIndicatorView.IndicatorSize) -> CGFloat {
        processingStatusWidth(for: size, processingSnapshot: nil)
    }

    static func processingStatusWidth(
        for size: FloatingRecordingIndicatorView.IndicatorSize,
        processingSnapshot: RecordingIndicatorProcessingSnapshot?
    ) -> CGFloat {
        let textWidth = ceil(
            (processingText(for: processingSnapshot) as NSString).size(
                withAttributes: [.font: processingStatusFont(for: size)]
            ).width
        )
        let dotsWidth: CGFloat = 15
        let totalWidth = textWidth + 6 + dotsWidth
        return min(
            max(totalWidth, processingStatusMinWidth(for: size)),
            processingStatusMaxWidth(for: size)
        )
    }

    static func processingStatusFont(for size: FloatingRecordingIndicatorView.IndicatorSize) -> NSFont {
        let pointSize: CGFloat = switch size {
        case .classic, .super:
            12
        case .mini:
            11
        }
        return .systemFont(ofSize: pointSize, weight: .semibold)
    }

    static func processingStatusMinWidth(for size: FloatingRecordingIndicatorView.IndicatorSize) -> CGFloat {
        switch size {
        case .classic:
            112
        case .mini:
            92
        case .super:
            128
        }
    }

    static func processingStatusMaxWidth(for size: FloatingRecordingIndicatorView.IndicatorSize) -> CGFloat {
        switch size {
        case .classic:
            220
        case .mini:
            180
        case .super:
            240
        }
    }

    static func processingText(for snapshot: RecordingIndicatorProcessingSnapshot?) -> String {
        (snapshot ?? defaultProcessingSnapshot()).step.localizedTitleKey.localized
    }

    static func defaultProcessingSnapshot(
        for renderState: RecordingIndicatorRenderState = RecordingIndicatorRenderState(
            mode: .processing,
            kind: .dictation
        )
    ) -> RecordingIndicatorProcessingSnapshot {
        let step: RecordingIndicatorProcessingStep = switch renderState.kind {
        case .assistant, .assistantIntegration:
            .transcribingCommand
        case .dictation, .meeting:
            .transcribingAudio
        }
        return RecordingIndicatorProcessingSnapshot(step: step)
    }

    static func horizontalPadding(for size: FloatingRecordingIndicatorView.IndicatorSize, expanded: Bool) -> CGFloat {
        if expanded {
            return AppDesignSystem.Layout.recordingIndicatorSidePadding
        }

        switch size {
        case .classic, .mini:
            return max(AppDesignSystem.Layout.recordingIndicatorSidePadding, 16)
        case .super:
            return AppDesignSystem.Layout.recordingIndicatorSuperHorizontalPadding
        }
    }

    static func clusterWidth(
        for size: FloatingRecordingIndicatorView.IndicatorSize,
        renderState: RecordingIndicatorRenderState,
        processingSnapshot: RecordingIndicatorProcessingSnapshot? = nil
    ) -> CGFloat {
        var width = AppDesignSystem.Layout.recordingIndicatorDotSize + contentSpacing(for: size)

        switch mainContentMode(for: renderState) {
        case .waveform:
            width += waveformWidth(for: size)
        case .processingStatus:
            width += processingStatusWidth(for: size, processingSnapshot: processingSnapshot)
        }

        return width
    }

    static func buttonGroupWidth(for size: FloatingRecordingIndicatorView.IndicatorSize) -> CGFloat {
        actionButtonSize + controlSpacing(for: size) + dividerWidth
    }

    static func externalAuxiliaryControlCount(
        for size: FloatingRecordingIndicatorView.IndicatorSize,
        renderState: RecordingIndicatorRenderState,
        layout: RecordingIndicatorOverlayLayout
    ) -> Int {
        if usesInlineDictationSelectors(for: size, renderState: renderState) {
            return 0
        }
        return [layout.showsPromptSelector, layout.showsLanguageSelector].count(where: { $0 })
    }

    static func mainPillWidth(
        for size: FloatingRecordingIndicatorView.IndicatorSize,
        renderState: RecordingIndicatorRenderState,
        layout: RecordingIndicatorOverlayLayout,
        expanded: Bool,
        processingSnapshot: RecordingIndicatorProcessingSnapshot? = nil
    ) -> CGFloat {
        if case .confirmingAutomaticMeetingStart = renderState.mode {
            return confirmationPillWidth(for: size)
        }

        var elementWidths: [CGFloat] = [
            clusterWidth(for: size, renderState: renderState, processingSnapshot: processingSnapshot)
        ]

        if renderState.kind == .meeting, renderState.mode == .recording {
            elementWidths.append(actionButtonSize)
            elementWidths.append(dividerWidth)
            elementWidths.append(actionButtonSize)

            if layout.showsMeetingTimer {
                elementWidths.append(dividerWidth)
                elementWidths.append(timerReservedWidth(for: size))
            }
        }

        if expanded, renderState.mode == .recording {
            elementWidths.insert(buttonGroupWidth(for: size), at: 0)

            if usesInlineDictationSelectors(
                for: size,
                renderState: renderState
            ) {
                if layout.showsPromptSelector {
                    elementWidths.append(dividerWidth)
                    elementWidths.append(promptSize(for: size))
                }

                if layout.showsLanguageSelector {
                    elementWidths.append(dividerWidth)
                    elementWidths.append(promptSize(for: size))
                }
            }

            elementWidths.append(buttonGroupWidth(for: size))
        }

        let spacingCount = max(0, elementWidths.count - 1)
        return (horizontalPadding(for: size, expanded: expanded) * 2)
            + elementWidths.reduce(0, +)
            + (CGFloat(spacingCount) * contentSpacing(for: size))
    }

    static func promptIconImage(
        symbolName: String,
        size: FloatingRecordingIndicatorView.IndicatorSize
    ) -> NSImage {
        let fallbackName = "doc.text"
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: promptIconSize(for: size), weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))

        let rawImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: fallbackName, accessibilityDescription: nil)
            ?? NSImage()
        let configured = rawImage.withSymbolConfiguration(symbolConfig) ?? rawImage
        configured.isTemplate = false
        return configured
    }

    static func languageFlagImage(
        _ emoji: String,
        size: FloatingRecordingIndicatorView.IndicatorSize
    ) -> NSImage {
        emojiImage(emoji, pointSize: languageFlagPointSize(for: size))
    }

    private static func promptIconSize(for size: FloatingRecordingIndicatorView.IndicatorSize) -> CGFloat {
        switch size {
        case .classic:
            14
        case .mini:
            14
        case .super:
            12
        }
    }

    private static func languageFlagPointSize(for size: FloatingRecordingIndicatorView.IndicatorSize) -> CGFloat {
        switch size {
        case .classic:
            18
        case .mini:
            13
        case .super:
            13
        }
    }

    static func superFooterChipHeight() -> CGFloat {
        AppDesignSystem.Layout.recordingIndicatorSuperFooterChipHeight
    }

    static func superFooterChipWidth(for contentWidth: CGFloat) -> CGFloat {
        contentWidth + (AppDesignSystem.Layout.recordingIndicatorSuperFooterChipHorizontalPadding * 2)
    }

    static func superFooterSpacing() -> CGFloat {
        AppDesignSystem.Layout.recordingIndicatorSuperFooterSpacing
    }

    static func superFooterGroupSpacing() -> CGFloat {
        AppDesignSystem.Layout.recordingIndicatorSuperFooterGroupSpacing
    }

    static func superFooterIconWidth() -> CGFloat {
        AppDesignSystem.Layout.recordingIndicatorSuperFooterIconWidth
    }

    static func superActionWidth(kind: FloatingRecordingIndicatorView.SuperActionKind) -> CGFloat {
        let titleKey = switch kind {
        case .stop:
            "recording_indicator.super.stop"
        case .cancel:
            "recording_indicator.super.cancel"
        }

        let title = titleKey.localized as NSString
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let textWidth = ceil(title.size(withAttributes: [.font: font]).width)
        let iconWidth: CGFloat = 12
        let spacing: CGFloat = 6
        let horizontalPadding: CGFloat = 24

        return ceil(textWidth + iconWidth + spacing + horizontalPadding)
    }

    static func superActionGroupWidth(for renderState: RecordingIndicatorRenderState) -> CGFloat {
        guard renderState.mode == .recording else { return 0 }

        return superActionWidth(kind: .stop)
            + superFooterSpacing()
            + superActionWidth(kind: .cancel)
    }

    static func superFooterLeadingWidth(
        layout: RecordingIndicatorOverlayLayout,
        renderState: RecordingIndicatorRenderState
    ) -> CGFloat {
        guard renderState.mode == .recording else { return 0 }

        var widths: [CGFloat] = []
        if layout.showsPromptSelector {
            widths.append(superFooterChipWidth(for: promptSize(for: .super)))
        }
        if layout.showsLanguageSelector {
            widths.append(superFooterChipWidth(for: superFooterIconWidth()))
        }
        if layout.showsMeetingTimer {
            widths.append(superFooterChipWidth(for: timerReservedWidth(for: .super)))
        }
        if renderState.kind == .meeting {
            widths.append(superFooterChipWidth(for: superFooterIconWidth()))
            widths.append(superFooterChipWidth(for: superFooterIconWidth()))
        }

        guard !widths.isEmpty else { return 0 }
        return widths.reduce(0, +)
            + (CGFloat(max(0, widths.count - 1)) * superFooterSpacing())
    }

    static func superShowsFooter(
        layout: RecordingIndicatorOverlayLayout,
        renderState: RecordingIndicatorRenderState
    ) -> Bool {
        superFooterLeadingWidth(layout: layout, renderState: renderState) > 0
            || superActionGroupWidth(for: renderState) > 0
    }

    static func superBodyWidth(
        renderState: RecordingIndicatorRenderState,
        processingSnapshot: RecordingIndicatorProcessingSnapshot? = nil
    ) -> CGFloat {
        (AppDesignSystem.Layout.recordingIndicatorSuperHorizontalPadding * 2)
            + clusterWidth(for: .super, renderState: renderState, processingSnapshot: processingSnapshot)
    }

    static func superFooterWidth(
        layout: RecordingIndicatorOverlayLayout,
        renderState: RecordingIndicatorRenderState
    ) -> CGFloat {
        guard superShowsFooter(layout: layout, renderState: renderState) else { return 0 }

        let leadingWidth = superFooterLeadingWidth(layout: layout, renderState: renderState)
        let trailingWidth = superActionGroupWidth(for: renderState)
        let groupSpacing: CGFloat = leadingWidth > 0 && trailingWidth > 0 ? superFooterGroupSpacing() : 0

        return (AppDesignSystem.Layout.recordingIndicatorSuperHorizontalPadding * 2)
            + leadingWidth
            + trailingWidth
            + groupSpacing
    }

    static func superCardWidth(
        layout: RecordingIndicatorOverlayLayout,
        renderState: RecordingIndicatorRenderState,
        processingSnapshot: RecordingIndicatorProcessingSnapshot? = nil
    ) -> CGFloat {
        if case .confirmingAutomaticMeetingStart = renderState.mode {
            return confirmationPillWidth(for: .super)
        }

        return max(
            superBodyWidth(renderState: renderState, processingSnapshot: processingSnapshot),
            superFooterWidth(layout: layout, renderState: renderState)
        )
    }

    static func superCardHeight(
        layout: RecordingIndicatorOverlayLayout,
        renderState: RecordingIndicatorRenderState
    ) -> CGFloat {
        let baseHeight = (AppDesignSystem.Layout.recordingIndicatorSuperVerticalPadding * 2)
            + waveformHeight(for: .super)

        if case .confirmingAutomaticMeetingStart = renderState.mode {
            return baseHeight
        }

        guard superShowsFooter(layout: layout, renderState: renderState) else {
            return baseHeight
        }

        return baseHeight
            + superFooterChipHeight()
            + AppDesignSystem.Layout.recordingIndicatorSuperVerticalPadding
            + dividerWidth
    }

    private static func emojiImage(_ emoji: String, pointSize: CGFloat) -> NSImage {
        let imageSize = NSSize(width: 24, height: 24)
        let image = NSImage(size: imageSize)
        image.lockFocus()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: pointSize),
            .paragraphStyle: paragraphStyle
        ]

        let attributed = NSAttributedString(string: emoji, attributes: attributes)
        let drawRect = NSRect(
            x: 0,
            y: (imageSize.height - pointSize) / 2,
            width: imageSize.width * 1.06,
            height: pointSize * 1.06
        )
        attributed.draw(in: drawRect)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func usesInlineDictationSelectors(
        for size: FloatingRecordingIndicatorView.IndicatorSize,
        renderState: RecordingIndicatorRenderState
    ) -> Bool {
        renderState.mode == .recording
            && renderState.kind == .dictation
            && size != .super
    }
}

#Preview("Action Icon Button", traits: .sizeThatFitsLayout) {
    ActionIconButton(
        symbol: "arrow.up",
        helpKey: "recording_indicator.stop.help",
        keyboardShortcut: nil,
        style: .neutral
    ) {
        // Preview only
    }
    .padding()
    .background(AppDesignSystem.Colors.neutral.opacity(0.8))
}
