import Combine
import Foundation
import MeetingAssistantCoreInfrastructure
import SwiftUI

// MARK: - Onboarding View Model

/// Manages state and navigation for the onboarding flow.
@MainActor
public class OnboardingViewModel: ObservableObject {
    // MARK: - Published Properties

    /// The current step in the onboarding flow.
    @Published public var currentStep: OnboardingStep = .welcome

    /// Whether the onboarding has been completed.
    @Published public private(set) var isCompleted: Bool = false

    /// Set of steps that were skipped by the user.
    @Published public private(set) var skippedSteps: Set<OnboardingStep> = []

    // MARK: - Computed Properties

    /// Whether the user can navigate back from the current step.
    public var canGoBack: Bool {
        currentStep != .welcome
    }

    /// Whether the user can continue from the current step.
    /// Always true for welcome and completion steps.
    /// For permissions/shortcuts, the user can always continue (skip is available).
    public var canContinue: Bool {
        true
    }

    /// The total number of steps in the onboarding flow.
    public var totalSteps: Int {
        OnboardingStep.allCases.count
    }

    // MARK: - Private Properties

    private let settings = AppSettingsStore.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init() {
        setupBindings()
    }

    // MARK: - Public Methods

    /// Advances to the next step in the onboarding flow.
    public func goToNextStep() {
        guard let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
            // Already at the last step, complete onboarding
            completeOnboarding()
            return
        }
        currentStep = nextStep
    }

    /// Returns to the previous step in the onboarding flow.
    public func goToPreviousStep() {
        guard let previousStep = OnboardingStep(rawValue: currentStep.rawValue - 1) else {
            return
        }
        currentStep = previousStep
    }

    /// Skips the current step and advances to the next one.
    public func skipCurrentStep() {
        guard currentStep.isSkippable else { return }
        skippedSteps.insert(currentStep)
        goToNextStep()
    }

    /// Marks the onboarding as completed and persists the state.
    public func completeOnboarding() {
        isCompleted = true
        settings.hasCompletedOnboarding = true
    }

    /// Enables Meeting Recording during onboarding.
    public func enableMeetingRecording() {
        settings.isMeetingTranscriptionEnabled = true
    }

    /// Resets the onboarding state (for testing/debug purposes).
    public func resetOnboarding() {
        currentStep = .welcome
        isCompleted = false
        skippedSteps.removeAll()
        settings.hasCompletedOnboarding = false
    }

    /// Checks if a specific step was skipped.
    public func wasSkipped(_ step: OnboardingStep) -> Bool {
        skippedSteps.contains(step)
    }

    // MARK: - Private Methods

    private func setupBindings() {
        // Observe settings changes
        settings.$hasCompletedOnboarding
            .receive(on: DispatchQueue.main)
            .assign(to: &$isCompleted)
    }
}
