import Combine
import Foundation
import MeetingAssistantCore

extension AppDelegate {
    func setupCapabilityObservation() {
        guard !hasConfiguredCapabilityObservers else { return }
        hasConfiguredCapabilityObservers = true

        settingsStore.$isMeetingTranscriptionEnabled
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                self?.applyMeetingTranscriptionCapabilityState(isEnabled: isEnabled)
                self?.refreshRecordingUIState()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .map { [settingsStore] _ in settingsStore.autoStartRecording }
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.applyAutomaticMeetingRecordingState()
            }
            .store(in: &cancellables)

        settingsStore.$isAssistantIntegrationsEnabled
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.assistantShortcutController.refresh()
                self?.refreshRecordingUIState()
            }
            .store(in: &cancellables)

        settingsStore.$isAssistantEnabled
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                self?.applyAssistantCapabilityState(isEnabled: isEnabled)
                self?.refreshRecordingUIState()
            }
            .store(in: &cancellables)
    }

    func applyMeetingTranscriptionCapabilityState(isEnabled: Bool) {
        applyAutomaticMeetingRecordingState()

        // Local models are prepared by the meeting capture path, not by enabling the capability.
        guard !isEnabled else { return }

        if recordingManager.currentCapturePurpose == .meeting,
           recordingManager.isRecording || recordingManager.isStartingRecording
        {
            Task {
                await recordingManager.cancelRecording()
            }
        }

        _ = FluidAIModelManager.shared.unloadDiarizationFromMemoryIfPossible()
        _ = FluidAIModelManager.shared.unloadASRFromMemoryIfPossible()
    }

    private func applyAssistantCapabilityState(isEnabled: Bool) {
        assistantShortcutController.refresh()

        guard !isEnabled else { return }

        if assistantVoiceCommandService.isRecording || assistantVoiceCommandService.isProcessing {
            Task {
                await assistantVoiceCommandService.cancelRecording()
            }
        }
    }

    private func applyAutomaticMeetingRecordingState() {
        recordingManager.setAutomaticMeetingRecordingEnabled(
            settingsStore.isMeetingTranscriptionEnabled && settingsStore.autoStartRecording
        )
    }
}
