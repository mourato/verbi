import AppKit
import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct DSModifierShortcutEditor: View {
    @Binding private var shortcut: ShortcutDefinition?
    private let conflictMessage: String?
    private let showsTitle: Bool
    private let maxInputWidth: CGFloat?

    @StateObject private var recorder = ShortcutRecorderController()
    @State private var isPopoverPresented = false
    @State private var localStatus: RecordingStatus = .idle
    @State private var localConflictMessage: String?
    @State private var attemptedShortcut: ShortcutDefinition?
    @State private var closeTask: Task<Void, Never>?
    @State private var restartTask: Task<Void, Never>?

    private enum RecordingStatus {
        case idle
        case recording
        case success
        case failure
    }

    public init(
        shortcut: Binding<ShortcutDefinition?>,
        conflictMessage: String?,
        showsTitle: Bool = true,
        maxInputWidth: CGFloat? = 200,
    ) {
        _shortcut = shortcut
        self.conflictMessage = conflictMessage
        self.showsTitle = showsTitle
        self.maxInputWidth = maxInputWidth
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsTitle {
                Text("settings.shortcuts.modifier.title".localized)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            shortcutInputField
                .frame(maxWidth: maxInputWidth, alignment: .leading)
                .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
                    recordingPopover
                        .frame(width: 360)
                        .padding(12)
                }

            if let conflict = conflictMessage, !isPopoverPresented {
                Text(conflict)
                    .font(.caption)
                    .foregroundStyle(AppDesignSystem.Colors.error)
            }
        }
        .onChange(of: conflictMessage) { _, newValue in
            guard isPopoverPresented, attemptedShortcut != nil else {
                return
            }

            if let newValue {
                closeTask?.cancel()
                localStatus = .failure
                localConflictMessage = newValue
                scheduleRecordingRestart()
            }
        }
        .onChange(of: recorder.previewLabels) { _, newValue in
            guard !newValue.isEmpty else {
                return
            }
            localStatus = .recording
            localConflictMessage = nil
        }
        .onChange(of: isPopoverPresented) { _, isPresented in
            if isPresented {
                beginRecordingSession(resetState: true)
            } else {
                stopRecording(cancelled: true)
            }
        }
        .onDisappear {
            stopRecording(cancelled: true)
            closeTask?.cancel()
            restartTask?.cancel()
        }
    }

    private var shortcutInputField: some View {
        HStack(spacing: AppDesignSystem.Layout.spacing6) {
            Button {
                openRecordingPopover()
            } label: {
                Group {
                    if isPopoverPresented {
                        Text("settings.shortcuts.modifier.press_keys".localized)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppDesignSystem.Colors.accent)
                            .frame(minWidth: 100)
                    } else if displayLabels.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "return")
                                .font(.system(size: 11, weight: .semibold))
                            Text("settings.shortcuts.modifier.input_placeholder".localized)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(AppDesignSystem.Colors.accent)
                        .frame(minWidth: 104)
                    } else {
                        ShortcutChipRow(labels: displayLabels, colorStyle: .neutral)
                    }
                }
            }
            .buttonStyle(ShortcutKeycapButtonStyle(isRecording: isPopoverPresented))
            .help(
                isPopoverPresented
                    ? "settings.shortcuts.modifier.popover.hint".localized
                    : "settings.shortcuts.modifier.input_placeholder".localized,
            )

            if shortcut != nil, !isPopoverPresented {
                Button {
                    clearShortcut()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help("settings.shortcuts.modifier.clear".localized)
                .accessibilityLabel("settings.shortcuts.modifier.clear".localized)
            }
        }
    }

    private var recordingPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text("settings.shortcuts.modifier.popover.recording".localized)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("settings.shortcuts.modifier.popover.example".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    isPopoverPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(AppDesignSystem.Layout.compactInset)
                        .background(
                            Circle()
                                .fill(AppDesignSystem.Colors.secondaryFill),
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("common.cancel".localized)
            }

            ShortcutChipRow(labels: popoverLabels, colorStyle: popoverColorStyle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let localConflictMessage {
                Text(localConflictMessage)
                    .font(.caption)
                    .foregroundStyle(AppDesignSystem.Colors.error)
            } else if localStatus == .success {
                Text("settings.shortcuts.modifier.popover.success".localized)
                    .font(.caption)
                    .foregroundStyle(AppDesignSystem.Colors.success)
            } else {
                Text("settings.shortcuts.modifier.popover.hint".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var displayLabels: [String] {
        labels(for: shortcut)
    }

    private var popoverLabels: [String] {
        if !recorder.previewLabels.isEmpty {
            return recorder.previewLabels
        }
        if let attemptedShortcut {
            return labels(for: attemptedShortcut)
        }
        return displayLabels
    }

    private var popoverColorStyle: ShortcutChipColorStyle {
        switch localStatus {
        case .success:
            .success
        case .failure:
            .error
        case .idle, .recording:
            .neutral
        }
    }

    private func openRecordingPopover() {
        isPopoverPresented = true
    }

    private func clearShortcut() {
        closeTask?.cancel()
        restartTask?.cancel()
        attemptedShortcut = nil
        localStatus = .idle
        localConflictMessage = nil
        stopRecording(cancelled: true)
        shortcut = nil
        isPopoverPresented = false
    }

    private func beginRecordingSession(resetState: Bool) {
        closeTask?.cancel()
        restartTask?.cancel()

        if resetState {
            localStatus = .recording
            localConflictMessage = nil
            attemptedShortcut = nil
        }

        recorder.start { capturedShortcut in
            handleCapturedShortcut(capturedShortcut)
        }
    }

    private func stopRecording(cancelled: Bool) {
        recorder.stopRecording(cancelled: cancelled)
    }

    private func handleCapturedShortcut(_ capturedShortcut: ShortcutDefinition) {
        attemptedShortcut = capturedShortcut
        localStatus = .recording
        localConflictMessage = nil

        shortcut = capturedShortcut

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard attemptedShortcut == capturedShortcut else {
                return
            }

            if conflictMessage == nil, shortcut == capturedShortcut {
                localStatus = .success
                closeTask?.cancel()
                closeTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled else { return }
                    isPopoverPresented = false
                }
            } else if let conflictMessage {
                closeTask?.cancel()
                localStatus = .failure
                localConflictMessage = conflictMessage
                scheduleRecordingRestart()
            }
        }
    }

    private func scheduleRecordingRestart() {
        closeTask?.cancel()
        restartTask?.cancel()
        restartTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, isPopoverPresented else { return }
            beginRecordingSession(resetState: false)
        }
    }

    private func labels(for shortcut: ShortcutDefinition?) -> [String] {
        guard let shortcut else {
            return []
        }

        var labels = shortcut.modifiers.map { $0.tokenLabel(in: shortcut.modifiers) }

        if let primaryKey = shortcut.primaryKey {
            labels.append(primaryKey.display)
            return labels
        }

        if shortcut.trigger == .doubleTap, labels.count == 1 {
            labels.append(labels[0])
        }
        return labels
    }
}

#Preview("Empty") {
    PreviewStateContainer(ShortcutDefinition?.none) { shortcut in
        DSModifierShortcutEditor(
            shortcut: shortcut,
            conflictMessage: nil,
        )
        .padding()
        .frame(width: 560)
    }
}

#Preview("Conflict") {
    PreviewStateContainer(
        Optional(
            ShortcutDefinition(
                modifiers: [.rightCommand],
                primaryKey: nil,
                trigger: .doubleTap,
            ),
        ),
    ) { shortcut in
        DSModifierShortcutEditor(
            shortcut: shortcut,
            conflictMessage: "settings.shortcuts.modifier.conflict".localized(with: "Meeting Shortcut"),
        )
        .padding()
        .frame(width: 560)
    }
}

/// Transparent keycap-button chrome; recording uses a light accent highlight.
struct ShortcutKeycapButtonStyle: ButtonStyle {
    let isRecording: Bool
    var horizontalPadding: CGFloat = 6
    var verticalPadding: CGFloat = 4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isRecording ? AppDesignSystem.Colors.accent.opacity(0.08) : Color.clear),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isRecording ? AppDesignSystem.Colors.accent.opacity(0.5) : Color.clear,
                        lineWidth: 1,
                    ),
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .animation(
                AppleMotion.animation(reduceMotion: reduceMotion, kind: .press),
                value: configuration.isPressed,
            )
    }
}
