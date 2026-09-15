import AppKit
import Combine
import MeetingAssistantCoreAI
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

// MARK: - Onboarding View

/// Main container view that orchestrates all onboarding steps.
public struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @ObservedObject var permissionViewModel: PermissionViewModel
    @ObservedObject var shortcutViewModel: ShortcutSettingsViewModel
    @ObservedObject var assistantShortcutViewModel: AssistantShortcutSettingsViewModel
    @ObservedObject var modelManager: FluidAIModelManager

    let onComplete: () -> Void
    let refreshPermissions: @MainActor () async -> Void
    @State private var stepDirection: OnboardingStepDirection = .forward
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        viewModel: OnboardingViewModel,
        permissionViewModel: PermissionViewModel,
        shortcutViewModel: ShortcutSettingsViewModel,
        assistantShortcutViewModel: AssistantShortcutSettingsViewModel,
        modelManager: FluidAIModelManager,
        refreshPermissions: @escaping @MainActor () async -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.permissionViewModel = permissionViewModel
        self.shortcutViewModel = shortcutViewModel
        self.assistantShortcutViewModel = assistantShortcutViewModel
        self.modelManager = modelManager
        self.refreshPermissions = refreshPermissions
        self.onComplete = onComplete
    }

    public var body: some View {
        OnboardingContainer {
            VStack(spacing: 0) {
                OnboardingStepIndicator(
                    currentStep: viewModel.currentStep,
                    totalSteps: OnboardingStep.allCases.count
                )
                .padding(.top, 4)

                contentView
                    .id(viewModel.currentStep)
                    .frame(maxHeight: .infinity)
                    .transition(stepTransition)
                    .animation(
                        AppleMotion.animation(reduceMotion: reduceMotion, kind: .default),
                        value: viewModel.currentStep
                    )

                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.currentStep {
        case .welcome:
            OnboardingWelcomeView(onGetStarted: { goToNextStep() })

        case .permissions:
            OnboardingPermissionsView(
                viewModel: permissionViewModel,
                onContinue: { goToNextStep() },
                onSkip: viewModel.currentStep.isSkippable ? { skipCurrentStep() } : nil,
                refreshAction: refreshPermissions
            )

        case .shortcuts:
            OnboardingShortcutsView(
                viewModel: shortcutViewModel,
                assistantViewModel: assistantShortcutViewModel,
                onContinue: { goToNextStep() },
                onSkip: viewModel.currentStep.isSkippable ? { skipCurrentStep() } : nil
            )

        case .downloadModels:
            OnboardingDownloadModelsView(
                modelManager: modelManager,
                onContinue: { goToNextStep() },
                onSkip: viewModel.currentStep.isSkippable ? { skipCurrentStep() } : nil
            )

        case .meetingRecording:
            OnboardingMeetingRecordingView(
                readiness: meetingRecordingReadiness,
                onEnable: enableMeetingRecording,
                onOpenPermissions: { navigate(to: .permissions) },
                onOpenModels: { navigate(to: .downloadModels) },
                onContinue: { goToNextStep() },
                onSkip: viewModel.currentStep.isSkippable ? { skipCurrentStep() } : nil
            )

        case .completion:
            OnboardingCompletionView(
                readiness: meetingRecordingReadiness,
                onStartUsing: {
                    viewModel.completeOnboarding()
                    onComplete()
                }
            )
        }
    }

    private var meetingRecordingReadiness: OnboardingMeetingRecordingReadiness {
        OnboardingMeetingRecordingReadiness(
            microphoneGranted: permissionViewModel.microphoneState.isAuthorized,
            screenRecordingGranted: permissionViewModel.screenState.isAuthorized,
            transcriptionModelReady: modelManager.isASRInstalled,
            isMeetingRecordingEnabled: AppSettingsStore.shared.isMeetingTranscriptionEnabled,
            wasSkipped: viewModel.wasSkipped(.meetingRecording)
        )
    }

    private func goToNextStep() {
        stepDirection = .forward
        viewModel.goToNextStep()
    }

    private func skipCurrentStep() {
        stepDirection = .forward
        viewModel.skipCurrentStep()
    }

    private func navigate(to step: OnboardingStep) {
        stepDirection = step.rawValue >= viewModel.currentStep.rawValue ? .forward : .backward
        viewModel.currentStep = step
    }

    private func enableMeetingRecording() {
        viewModel.enableMeetingRecording()
        goToNextStep()
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else {
            return .opacity
        }

        let insertionEdge: Edge = stepDirection == .forward ? .trailing : .leading
        let removalEdge: Edge = stepDirection == .forward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }
}

private enum OnboardingStepDirection {
    case forward
    case backward
}

@MainActor
private func makeOnboardingViewModel(step: OnboardingStep) -> OnboardingViewModel {
    let viewModel = OnboardingViewModel()
    viewModel.currentStep = step
    return viewModel
}

@MainActor
private func makePermissionViewModel() -> PermissionViewModel {
    PermissionViewModel(
        manager: PermissionStatusManager(),
        requestMicrophone: {},
        requestScreen: {},
        openMicrophoneSettings: {},
        openScreenSettings: {},
        requestAccessibility: {},
        openAccessibilitySettings: {}
    )
}

#Preview("Onboarding - Welcome") {
    OnboardingView(
        viewModel: makeOnboardingViewModel(step: .welcome),
        permissionViewModel: makePermissionViewModel(),
        shortcutViewModel: ShortcutSettingsViewModel(),
        assistantShortcutViewModel: AssistantShortcutSettingsViewModel(),
        modelManager: FluidAIModelManager.shared,
        refreshPermissions: {},
        onComplete: {}
    )
    .frame(width: 650, height: 550)
}

#Preview("Onboarding - Permissions") {
    OnboardingView(
        viewModel: makeOnboardingViewModel(step: .permissions),
        permissionViewModel: makePermissionViewModel(),
        shortcutViewModel: ShortcutSettingsViewModel(),
        assistantShortcutViewModel: AssistantShortcutSettingsViewModel(),
        modelManager: FluidAIModelManager.shared,
        refreshPermissions: {},
        onComplete: {}
    )
    .frame(width: 650, height: 550)
}

#Preview("Onboarding - Shortcuts") {
    OnboardingView(
        viewModel: makeOnboardingViewModel(step: .shortcuts),
        permissionViewModel: makePermissionViewModel(),
        shortcutViewModel: ShortcutSettingsViewModel(),
        assistantShortcutViewModel: AssistantShortcutSettingsViewModel(),
        modelManager: FluidAIModelManager.shared,
        refreshPermissions: {},
        onComplete: {}
    )
    .frame(width: 650, height: 550)
}

#Preview("Onboarding - Meeting Recording") {
    OnboardingView(
        viewModel: makeOnboardingViewModel(step: .meetingRecording),
        permissionViewModel: makePermissionViewModel(),
        shortcutViewModel: ShortcutSettingsViewModel(),
        assistantShortcutViewModel: AssistantShortcutSettingsViewModel(),
        modelManager: FluidAIModelManager.shared,
        refreshPermissions: {},
        onComplete: {}
    )
    .frame(width: 650, height: 550)
}
