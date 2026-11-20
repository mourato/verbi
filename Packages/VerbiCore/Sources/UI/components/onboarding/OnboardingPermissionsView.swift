import SwiftUI
import VerbiCoreDomain

public struct OnboardingPermissionsView: View {
    @ObservedObject var viewModel: PermissionViewModel
    let onContinue: () -> Void
    let onSkip: (() -> Void)?
    let refreshAction: (@MainActor () async -> Void)?

    public init(
        viewModel: PermissionViewModel,
        onContinue: @escaping () -> Void,
        onSkip: (() -> Void)? = nil,
        refreshAction: (@MainActor () async -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onContinue = onContinue
        self.onSkip = onSkip
        self.refreshAction = refreshAction
    }

    public var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                Text("onboarding.permissions.title".localized)
                    .font(.title2)
                    .fontWeight(.bold)

                Text("onboarding.permissions.subtitle".localized)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 20)

            VStack(spacing: 12) {
                ForEach(OnboardingPermissionItem.allPermissions, id: \.type) { item in
                    OnboardingPermissionRow(
                        item: item,
                        status: permissionStatus(for: item.type),
                        onGrant: { requestPermission(for: item.type) },
                        onOpenSettings: { openSystemSettings(for: item.type) }
                    )
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            HStack(spacing: 16) {
                if onSkip != nil {
                    Button(action: { onSkip?() }) {
                        Text("onboarding.skip".localized)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                }

                Button("onboarding.continue".localized, action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.allPermissionsGranted)
            }
            .frame(maxWidth: 400)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: 550)
        .onAppear {
            if let refreshAction {
                viewModel.startPeriodicRefresh(refreshAction: refreshAction)
            }
        }
        .onDisappear {
            viewModel.stopPeriodicRefresh()
        }
    }

    private func permissionStatus(for type: OnboardingPermissionType) -> PermissionState {
        switch type {
        case .microphone: viewModel.microphoneState
        case .screenRecording: viewModel.screenState
        case .accessibility: viewModel.accessibilityState
        }
    }

    private func requestPermission(for type: OnboardingPermissionType) {
        Task {
            switch type {
            case .microphone:
                await viewModel.requestMicrophonePermission()
            case .screenRecording:
                await viewModel.requestScreenPermission()
            case .accessibility:
                viewModel.requestAccessibilityPermission()
            }
        }
    }

    private func openSystemSettings(for type: OnboardingPermissionType) {
        switch type {
        case .microphone:
            viewModel.openMicrophoneSystemSettings()
        case .screenRecording:
            viewModel.openScreenSystemSettings()
        case .accessibility:
            viewModel.openAccessibilitySystemSettings()
        }
    }
}

#Preview {
    let mockManager = PermissionStatusManager()
    let viewModel = PermissionViewModel(
        manager: mockManager,
        requestMicrophone: {},
        requestScreen: {},
        openMicrophoneSettings: {},
        openScreenSettings: {},
        requestAccessibility: {},
        openAccessibilitySettings: {}
    )

    OnboardingPermissionsView(
        viewModel: viewModel,
        onContinue: {},
        onSkip: {}
    )
    .frame(width: 600, height: 550)
}
