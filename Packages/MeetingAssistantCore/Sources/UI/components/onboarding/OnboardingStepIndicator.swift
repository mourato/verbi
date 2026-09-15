import SwiftUI

// MARK: - Onboarding Step Indicator

/// A visual indicator showing progress through the onboarding steps.
public struct OnboardingStepIndicator: View {
    let currentStep: OnboardingStep
    let totalSteps: Int

    public init(currentStep: OnboardingStep, totalSteps: Int = OnboardingStep.allCases.count) {
        self.currentStep = currentStep
        self.totalSteps = totalSteps
    }

    public var body: some View {
        HStack(spacing: 12) {
            ForEach(OnboardingStep.allCases) { step in
                StepCircle(
                    step: step,
                    isCompleted: step.rawValue < currentStep.rawValue,
                    isCurrent: step == currentStep
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("onboarding.step".localized(with: currentStep.index, totalSteps))
    }
}

// MARK: - Step Circle

private struct StepCircle: View {
    let step: OnboardingStep
    let isCompleted: Bool
    let isCurrent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var circleSize: CGFloat = 32

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: circleSize, height: circleSize)

            if isCompleted {
                Image(systemName: "checkmark")
                    .font(AppTypography.onboardingStepCompletedIcon)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            } else {
                Text("\(step.index)")
                    .font(AppTypography.onboardingStepLabel)
                    .foregroundStyle(foregroundColor)
            }
        }
        .overlay(
            Circle()
                .strokeBorder(borderColor, lineWidth: 2)
        )
        .animation(AppleMotion.animation(reduceMotion: reduceMotion, kind: .default), value: isCompleted)
        .animation(AppleMotion.animation(reduceMotion: reduceMotion, kind: .default), value: isCurrent)
    }

    private var backgroundColor: Color {
        if isCompleted {
            .accentColor
        } else if isCurrent {
            .accentColor.opacity(0.2)
        } else {
            .clear
        }
    }

    private var foregroundColor: Color {
        isCurrent ? .accentColor : .secondary
    }

    private var borderColor: Color {
        (isCompleted || isCurrent) ? .accentColor : .secondary.opacity(0.3)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        OnboardingStepIndicator(currentStep: .welcome)
        OnboardingStepIndicator(currentStep: .permissions)
        OnboardingStepIndicator(currentStep: .shortcuts)
        OnboardingStepIndicator(currentStep: .downloadModels)
        OnboardingStepIndicator(currentStep: .meetingRecording)
        OnboardingStepIndicator(currentStep: .completion)
    }
    .padding()
    .frame(width: 500)
}
