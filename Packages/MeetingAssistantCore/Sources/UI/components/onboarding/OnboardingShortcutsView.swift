import MeetingAssistantCoreInfrastructure
import SwiftUI

// MARK: - Onboarding Shortcuts View

/// Third step of onboarding - configuring keyboard shortcuts.
public struct OnboardingShortcutsView: View {
    @ObservedObject var viewModel: ShortcutSettingsViewModel
    @ObservedObject var assistantViewModel: AssistantShortcutSettingsViewModel
    let onContinue: () -> Void
    let onSkip: (() -> Void)?

    public init(
        viewModel: ShortcutSettingsViewModel,
        assistantViewModel: AssistantShortcutSettingsViewModel,
        onContinue: @escaping () -> Void,
        onSkip: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.assistantViewModel = assistantViewModel
        self.onContinue = onContinue
        self.onSkip = onSkip
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "keyboard")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)

                Text("onboarding.shortcuts.title".localized)
                    .font(.title2)
                    .fontWeight(.bold)

                Text("onboarding.shortcuts.subtitle".localized)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 20)

            // Shortcuts List
            VStack(spacing: 16) {
                ForEach(OnboardingShortcutItem.allShortcuts, id: \.type) { item in
                    OnboardingShortcutRow(
                        item: item,
                        viewModel: viewModel,
                        assistantViewModel: assistantViewModel
                    )
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            // Navigation Buttons
            HStack(spacing: 16) {
                // Skip button (left)
                if onSkip != nil {
                    Button(action: { onSkip?() }) {
                        Text("onboarding.skip".localized)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                }

                // Continue button (right)
                Button("onboarding.continue".localized, action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: 400)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: 550)
    }
}

// MARK: - Onboarding Shortcut Row

private struct OnboardingShortcutRow: View {
    let item: OnboardingShortcutItem
    @ObservedObject var viewModel: ShortcutSettingsViewModel
    @ObservedObject var assistantViewModel: AssistantShortcutSettingsViewModel

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: iconName(for: item.type))
                .font(.system(size: 24))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                )

            // Title
            VStack(alignment: .leading, spacing: 4) {
                Text(item.titleKey.localized)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("onboarding.shortcuts.current".localized(with: currentShortcutSummary))
                    .font(.caption)
                    .foregroundStyle(isConfigured ? Color.secondary : Color.orange)
            }

            Spacer()

            // Use Default Button
            Button(action: useDefaultShortcut) {
                Text(
                    isUsingDefault
                        ? "onboarding.shortcuts.default_set".localized
                        : "onboarding.shortcuts.use_default".localized
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isUsingDefault)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    private func iconName(for type: OnboardingShortcutType) -> String {
        switch type {
        case .dictation: "text.bubble"
        case .meeting: "video"
        case .assistant: "wand.and.stars"
        }
    }

    private func useDefaultShortcut() {
        switch item.type {
        case .dictation:
            viewModel.dictationShortcutDefinition = OnboardingShortcutFeedbackFormatter.defaultDefinition(for: .dictation)
        case .meeting:
            viewModel.meetingShortcutDefinition = OnboardingShortcutFeedbackFormatter.defaultDefinition(for: .meeting)
        case .assistant:
            assistantViewModel.assistantShortcutDefinition = OnboardingShortcutFeedbackFormatter.defaultDefinition(for: .assistant)
        }
    }

    private var currentShortcutDefinition: ShortcutDefinition? {
        OnboardingShortcutFeedbackFormatter.currentDefinition(
            for: item.type,
            shortcutViewModel: viewModel,
            assistantViewModel: assistantViewModel
        )
    }

    private var isConfigured: Bool {
        currentShortcutDefinition != nil
    }

    private var isUsingDefault: Bool {
        OnboardingShortcutFeedbackFormatter.isUsingDefault(
            current: currentShortcutDefinition,
            type: item.type
        )
    }

    private var currentShortcutSummary: String {
        OnboardingShortcutFeedbackFormatter.summary(for: currentShortcutDefinition)
    }
}

@MainActor
enum OnboardingShortcutFeedbackFormatter {
    static func currentDefinition(
        for type: OnboardingShortcutType,
        shortcutViewModel: ShortcutSettingsViewModel,
        assistantViewModel: AssistantShortcutSettingsViewModel
    ) -> ShortcutDefinition? {
        switch type {
        case .dictation:
            shortcutViewModel.dictationShortcutDefinition
        case .meeting:
            shortcutViewModel.meetingShortcutDefinition
        case .assistant:
            assistantViewModel.assistantShortcutDefinition
        }
    }

    static func defaultDefinition(for type: OnboardingShortcutType) -> ShortcutDefinition {
        switch type {
        case .dictation:
            AppSettingsStore.defaultDictationShortcutDefinition
        case .meeting:
            AppSettingsStore.defaultMeetingShortcutDefinition
        case .assistant:
            AppSettingsStore.defaultAssistantShortcutDefinition
        }
    }

    static func isUsingDefault(current: ShortcutDefinition?, type: OnboardingShortcutType) -> Bool {
        current == defaultDefinition(for: type)
    }

    static func summary(for definition: ShortcutDefinition?) -> String {
        guard let definition else {
            return "onboarding.shortcuts.not_configured".localized
        }

        let modifierTokens = definition.modifiers.map { modifier in
            switch modifier {
            case .leftCommand, .rightCommand, .command:
                "⌘"
            case .leftShift, .rightShift, .shift:
                "⇧"
            case .leftOption, .rightOption, .option:
                "⌥"
            case .leftControl, .rightControl, .control:
                "⌃"
            case .fn:
                "Fn"
            }
        }

        if let primaryKey = definition.primaryKey {
            return (modifierTokens + [primaryKey.display]).joined(separator: " ")
        }

        if definition.trigger == .doubleTap, modifierTokens.count == 1 {
            return (modifierTokens + [modifierTokens[0]]).joined(separator: " ")
        }

        return modifierTokens.joined(separator: " ")
    }
}

// MARK: - Preview

#Preview {
    OnboardingShortcutsView(
        viewModel: ShortcutSettingsViewModel(),
        assistantViewModel: AssistantShortcutSettingsViewModel(),
        onContinue: {},
        onSkip: {}
    )
    .frame(width: 600, height: 550)
}
