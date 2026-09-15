import Combine
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

@MainActor
public class PermissionViewModel: ObservableObject {
    // MARK: - Dependencies

    private let permissionManager: PermissionStatusManager
    // Optional: We might need a way to trigger requests back to RecordingManager
    // Or we keep requests in RecordingViewModel and just observe state here?
    // Better: Inject a closure or protocol for requests to decouple.
    private let requestMicrophoneAction: () async -> Void
    private let requestScreenAction: () async -> Void
    private let requestAccessibilityAction: () -> Void
    private let openMicrophoneSettingsAction: () -> Void
    private let openScreenSettingsAction: () -> Void
    private let openAccessibilitySettingsAction: () -> Void

    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private var refreshAction: (@MainActor () async -> Void)?

    // MARK: - Published Properties

    @Published public private(set) var microphoneState: PermissionState = .notDetermined
    @Published public private(set) var screenState: PermissionState = .notDetermined
    @Published public private(set) var accessibilityState: PermissionState = .notDetermined

    // MARK: - Init

    public init(
        manager: PermissionStatusManager,
        requestMicrophone: @escaping () async -> Void,
        requestScreen: @escaping () async -> Void,
        openMicrophoneSettings: @escaping () -> Void,
        openScreenSettings: @escaping () -> Void,
        requestAccessibility: @escaping () -> Void,
        openAccessibilitySettings: @escaping () -> Void
    ) {
        permissionManager = manager
        requestMicrophoneAction = requestMicrophone
        requestScreenAction = requestScreen
        openMicrophoneSettingsAction = openMicrophoneSettings
        openScreenSettingsAction = openScreenSettings
        requestAccessibilityAction = requestAccessibility
        openAccessibilitySettingsAction = openAccessibilitySettings

        setupBindings()
    }

    /// Configure periodic refresh with a custom refresh action.
    public func startPeriodicRefresh(refreshAction: @escaping @MainActor () async -> Void) {
        self.refreshAction = refreshAction
        Task { @MainActor [weak self] in
            await self?.refreshAction?()
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAction?()
            }
        }
    }

    /// Stop the periodic refresh timer.
    public func stopPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Actions

    public func requestMicrophonePermission() async {
        await requestMicrophoneAction()
    }

    public func requestScreenPermission() async {
        await requestScreenAction()
    }

    public func openMicrophoneSystemSettings() {
        openMicrophoneSettingsAction()
    }

    public func openScreenSystemSettings() {
        openScreenSettingsAction()
    }

    public func requestAccessibilityPermission() {
        requestAccessibilityAction()
    }

    public func openAccessibilitySystemSettings() {
        openAccessibilitySettingsAction()
    }

    public var allPermissionsGranted: Bool {
        microphoneState == .granted && screenState == .granted && accessibilityState == .granted
    }

    // MARK: - Private

    private func setupBindings() {
        permissionManager.$microphonePermission
            .map(\.state)
            .receive(on: DispatchQueue.main)
            .assign(to: &$microphoneState)

        permissionManager.$screenRecordingPermission
            .map(\.state)
            .receive(on: DispatchQueue.main)
            .assign(to: &$screenState)

        permissionManager.$accessibilityPermission
            .map(\.state)
            .receive(on: DispatchQueue.main)
            .assign(to: &$accessibilityState)
    }
}
