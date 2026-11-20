import Combine
import Foundation
import SwiftUI
import VerbiCoreInfrastructure

@MainActor
public class OnboardingViewModel: ObservableObject {
    @Published public var currentStep: OnboardingStep = .welcome

    @Published public private(set) var isCompleted: Bool = false

    @Published public private(set) var skippedSteps: Set<OnboardingStep> = []

    public var canGoBack: Bool {
        currentStep != .welcome
    }

    public var canContinue: Bool {
        true
    }

    public var totalSteps: Int {
        OnboardingStep.allCases.count
    }

    private let settings = AppSettingsStore.shared
    private var cancellables = Set<AnyCancellable>()

    public init() {
        setupBindings()
    }

    public func goToNextStep() {
        guard let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
            completeOnboarding()
            return
        }
        currentStep = nextStep
    }

    public func goToPreviousStep() {
        guard let previousStep = OnboardingStep(rawValue: currentStep.rawValue - 1) else {
            return
        }
        currentStep = previousStep
    }

    public func skipCurrentStep() {
        guard currentStep.isSkippable else { return }
        skippedSteps.insert(currentStep)
        goToNextStep()
    }

    public func completeOnboarding() {
        isCompleted = true
        settings.hasCompletedOnboarding = true
    }

    public func enableMeetingRecording() {
        settings.isMeetingTranscriptionEnabled = true
    }

    public func resetOnboarding() {
        currentStep = .welcome
        isCompleted = false
        skippedSteps.removeAll()
        settings.hasCompletedOnboarding = false
    }

    public func wasSkipped(_ step: OnboardingStep) -> Bool {
        skippedSteps.contains(step)
    }

    private func setupBindings() {
        settings.$hasCompletedOnboarding
            .receive(on: DispatchQueue.main)
            .assign(to: &$isCompleted)
    }
}
