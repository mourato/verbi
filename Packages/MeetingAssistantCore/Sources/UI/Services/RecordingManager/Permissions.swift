import AVFoundation
import Combine
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import os.log
import UserNotifications

// MARK: - Permissions

public extension RecordingManager {
    func checkPermission() async {
        await checkPermission(for: recordingSource)
    }

    func checkPermission(for source: RecordingSource) async {
        let micPermission = await micRecorder.hasPermission()
        let screenPermission = await systemRecorder.hasPermission()
        let accessibilityState = AccessibilityPermissionService.currentState()

        // Update individual permission states using detailed state methods
        let micState = micRecorder.getPermissionState()
        let screenState = systemRecorder.getPermissionState()

        permissionStatus.updateMicrophoneState(micState)
        permissionStatus.updateScreenRecordingState(screenState)
        permissionStatus.updateAccessibilityState(accessibilityState)

        let hasPermissions = source.requiredPermissionsGranted(
            microphone: micPermission,
            screenRecording: screenPermission
        )

        await recordingActor.setPermissions(hasPermissions)
        hasRequiredPermissions = await recordingActor.permissionsState
    }

    /// Request permissions required for the provided source.
    func requestPermission() async {
        await requestPermission(for: recordingSource)
    }

    func requestPermission(for source: RecordingSource) async {
        if source.requiresMicrophonePermission {
            await micRecorder.requestPermission()
        }
        if source.requiresScreenRecordingPermission {
            await systemRecorder.requestPermission()
        }
        await checkPermission(for: source)
    }

    /// Open System Preferences to Screen Recording settings.
    func openPermissionSettings() {
        systemRecorder.openSettings()
    }

    /// Open System Preferences to Microphone settings.
    func openMicrophoneSettings() {
        micRecorder.openSettings()
    }

    func requestAccessibilityPermission() {
        AccessibilityPermissionService.requestPermission()
        permissionStatus.updateAccessibilityState(AccessibilityPermissionService.currentState())
    }

    func openAccessibilitySettings() {
        AccessibilityPermissionService.openSystemSettings()
    }
}
