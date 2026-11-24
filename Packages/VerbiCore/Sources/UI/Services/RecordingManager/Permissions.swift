import AVFoundation
import Combine
import Foundation
import os.log
import UserNotifications
import VerbiCoreAI
import VerbiCoreAudio
import VerbiCoreCommon
import VerbiCoreData
import VerbiCoreDomain
import VerbiCoreInfrastructure

public extension RecordingManager {
    func checkPermission() async {
        await checkPermission(for: recordingSource)
    }

    func checkPermission(for source: RecordingSource) async {
        let microphoneRecorder = source == .microphone ? dictationRecorder : meetingRecorder
        let micPermission = await microphoneRecorder.hasPermission()
        let screenPermission = await systemRecorder.hasPermission()
        let accessibilityState = AccessibilityPermissionService.currentState()

        let micState = microphoneRecorder.getPermissionState()
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

    func requestPermission() async {
        await requestPermission(for: recordingSource)
    }

    func requestPermission(for source: RecordingSource) async {
        if source.requiresMicrophonePermission {
            let microphoneRecorder = source == .microphone ? dictationRecorder : meetingRecorder
            await microphoneRecorder.requestPermission()
        }
        if source.requiresScreenRecordingPermission {
            await systemRecorder.requestPermission()
        }
        await checkPermission(for: source)
    }

    func openPermissionSettings() {
        systemRecorder.openSettings()
    }

    func openMicrophoneSettings() {
        activeAudioRecorder.openSettings()
    }

    func requestAccessibilityPermission() {
        AccessibilityPermissionService.requestPermission()
        permissionStatus.updateAccessibilityState(AccessibilityPermissionService.currentState())
    }

    func openAccessibilitySettings() {
        AccessibilityPermissionService.openSystemSettings()
    }
}
