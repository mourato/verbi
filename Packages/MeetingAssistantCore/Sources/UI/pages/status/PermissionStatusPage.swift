import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

// MARK: - Permission Status View

/// A view that displays individual permission status with visual indicators.
/// Shows each permission type with an icon and its current authorization state.
public struct PermissionStatusView: View {
    @ObservedObject var viewModel: PermissionViewModel
    private let requiredSource: RecordingSource

    public var onDismiss: (() -> Void)?

    public init(
        viewModel: PermissionViewModel,
        requiredSource: RecordingSource = .all,
        onDismiss: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.requiredSource = requiredSource
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 12) {
            headerSection

            VStack(spacing: 8) {
                PermissionRowView(
                    permission: PermissionInfo(type: .microphone, state: viewModel.microphoneState),
                    onRequest: { Task { await viewModel.requestMicrophonePermission() } },
                    onOpenSettings: { viewModel.openMicrophoneSystemSettings() }
                )

                PermissionRowView(
                    permission: PermissionInfo(type: .screenRecording, state: viewModel.screenState),
                    onRequest: { Task { await viewModel.requestScreenPermission() } },
                    onOpenSettings: { viewModel.openScreenSystemSettings() }
                )

                PermissionRowView(
                    permission: PermissionInfo(type: .accessibility, state: viewModel.accessibilityState),
                    onRequest: { viewModel.requestAccessibilityPermission() },
                    onOpenSettings: { viewModel.openAccessibilitySystemSettings() }
                )
            }

            if !requiredPermissionsGranted {
                permissionWarning
            }
        }
    } // body

    private var requiredPermissions: [PermissionType] {
        requiredSource.requiredPermissionTypes + [.accessibility]
    }

    private var requiredPermissionsGranted: Bool {
        requiredSource.requiredPermissionsGranted(
            microphone: viewModel.microphoneState,
            screenRecording: viewModel.screenState
        ) && viewModel.accessibilityState.isAuthorized
    }

    private var grantedCount: Int {
        var count = 0
        for permission in requiredPermissions where permissionState(for: permission).isAuthorized {
            count += 1
        }
        return count
    }

    private var requiredCount: Int {
        requiredPermissions.count
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            Image(systemName: PermissionConstants.Icons.shieldCheckered)
                .font(.title2)
                .foregroundStyle(headerIconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("permissions.system_title".localized)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("permissions.granted_count".localized(with: grantedCount, requiredCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var permissionWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: PermissionConstants.Icons.exclamationMarkTriangle)
                .foregroundStyle(AppDesignSystem.Colors.warning)
                .font(.title3)

            Text("permissions.warning".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var headerIconColor: Color {
        requiredPermissionsGranted ? AppDesignSystem.Colors.success : AppDesignSystem.Colors.warning
    }

    private func permissionState(for type: PermissionType) -> PermissionState {
        switch type {
        case .microphone:
            viewModel.microphoneState
        case .screenRecording:
            viewModel.screenState
        case .accessibility:
            viewModel.accessibilityState
        }
    }
}

// MARK: - Permission Row View

/// Individual row showing a single permission's status.
struct PermissionRowView: View {
    let permission: PermissionInfo
    let onRequest: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Permission type icon
            ZStack {
                Circle()
                    .fill(permission.iconBackgroundColor)
                    .frame(width: 36, height: 36)

                Image(systemName: permission.type.iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(permission.iconForegroundColor)
            }

            // Permission info
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.type.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(permission.type.permissionDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Status indicator and action button
            statusIndicator
        }
        .padding(.vertical, 10)
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        HStack(spacing: 8) {
            // Status icon with animation
            Image(systemName: permission.state.iconName)
                .font(.title3)
                .foregroundStyle(permission.statusColor)
                .symbolEffect(
                    .pulse, options: .nonRepeating, isActive: permission.state == .notDetermined
                )

            // Action button when not granted
            if !permission.state.isAuthorized {
                actionButton
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch permission.actionType {
        case .request:
            Button("permissions.request".localized) {
                onRequest()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(AppDesignSystem.Colors.accent)

        case .openSettings:
            Button("permissions.configure".localized) {
                onOpenSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

        case .none:
            EmptyView()
        }
    }
}

// MARK: - Compact Permission Status View

/// A compact inline view showing permission status with minimal space.
public struct CompactPermissionStatusView: View {
    @ObservedObject private var permissionManager: PermissionStatusManager

    public init(permissionManager: PermissionStatusManager) {
        self.permissionManager = permissionManager
    }

    public var body: some View {
        HStack(spacing: 12) {
            CompactPermissionIndicator(
                permission: permissionManager.microphonePermission
            )

            CompactPermissionIndicator(
                permission: permissionManager.screenRecordingPermission
            )

            CompactPermissionIndicator(
                permission: permissionManager.accessibilityPermission
            )
        }
    }
}

/// Compact indicator for a single permission.
struct CompactPermissionIndicator: View {
    let permission: PermissionInfo

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: permission.type.iconName)
                .font(.caption)
                .foregroundStyle(permission.state.isAuthorized ? .primary : .secondary)

            Image(systemName: permission.state.iconName)
                .font(.caption2)
                .foregroundStyle(permission.statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(permission.statusColor.opacity(0.5))
        )
        .help("\(permission.type.displayName): \(permission.state.displayName)")
    }
}

// MARK: - Previews

#Preview("Full Permission View - All Granted") {
    let manager = PermissionStatusManager()
    manager.updateMicrophoneState(.granted)
    manager.updateScreenRecordingState(.granted)
    manager.updateAccessibilityState(.granted)

    let vm = PermissionViewModel(
        manager: manager,
        requestMicrophone: {},
        requestScreen: {},
        openMicrophoneSettings: {},
        openScreenSettings: {},
        requestAccessibility: {},
        openAccessibilitySettings: {}
    )

    return PermissionStatusView(viewModel: vm)
        .frame(width: 320)
        .padding()
}

#Preview("Full Permission View - Mixed States") {
    let manager = PermissionStatusManager()
    manager.updateMicrophoneState(.granted)
    manager.updateScreenRecordingState(.denied)
    manager.updateAccessibilityState(.notDetermined)

    let vm = PermissionViewModel(
        manager: manager,
        requestMicrophone: {},
        requestScreen: {},
        openMicrophoneSettings: {},
        openScreenSettings: {},
        requestAccessibility: {},
        openAccessibilitySettings: {}
    )

    return PermissionStatusView(viewModel: vm)
        .frame(width: 320)
        .padding()
}

#Preview("Full Permission View - Not Determined") {
    let manager = PermissionStatusManager()

    let vm = PermissionViewModel(
        manager: manager,
        requestMicrophone: {},
        requestScreen: {},
        openMicrophoneSettings: {},
        openScreenSettings: {},
        requestAccessibility: {},
        openAccessibilitySettings: {}
    )

    return PermissionStatusView(viewModel: vm)
        .frame(width: 320)
        .padding()
}

#Preview("Compact Permission View") {
    let manager = PermissionStatusManager()
    manager.updateMicrophoneState(.granted)
    manager.updateScreenRecordingState(.notDetermined)
    manager.updateAccessibilityState(.denied)

    return CompactPermissionStatusView(permissionManager: manager)
        .padding()
}
