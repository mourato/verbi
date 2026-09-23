import AVFoundation
import CoreAudio
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

extension AudioRecorder {
    func scheduleInputDeviceRecoveryIfNeeded(for devices: [AudioInputDevice]) {
        guard isRecording,
              !isRecoveringInputDevice,
              let source = activeRecordingSource,
              source.requiresMicrophonePermission,
              audioEngine != nil,
              simpleRecorder == nil,
              fallbackRecorder == nil
        else {
            return
        }

        let activeInputUID = currentInputDeviceUID()
        let desiredInputUID = desiredInputDeviceUID(from: devices)
        guard Self.shouldRecoverInputDevice(
            activeInputUID: activeInputUID,
            desiredInputUID: desiredInputUID,
            availableDevices: devices
        ) else {
            return
        }

        inputDeviceRecoveryTask?.cancel()
        inputDeviceRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Constants.inputDeviceRecoveryDebounce)
            guard !Task.isCancelled else { return }
            await self?.recoverInputDevice(after: devices)
        }
    }

    func recoverInputDevice(after devices: [AudioInputDevice]) async {
        guard !isRecoveringInputDevice,
              isRecording,
              let source = activeRecordingSource,
              source.requiresMicrophonePermission,
              let outputURL = currentRecordingURL,
              audioEngine != nil
        else {
            return
        }

        let activeInputUID = currentInputDeviceUID()
        let desiredInputUID = desiredInputDeviceUID(from: devices)
        guard Self.shouldRecoverInputDevice(
            activeInputUID: activeInputUID,
            desiredInputUID: desiredInputUID,
            availableDevices: devices
        ) else {
            return
        }

        isRecoveringInputDevice = true
        defer {
            isRecoveringInputDevice = false
            inputDeviceRecoveryTask = nil
        }

        AppLogger.warning(
            "Recovering microphone input after device change",
            category: .recordingManager,
            extra: [
                "source": source.rawValue,
                "activeInputUID": activeInputUID ?? "nil",
                "desiredInputUID": desiredInputUID ?? "nil",
                "availableDevices": devices.map(\.id).joined(separator: ",")
            ]
        )

        validationTimer?.invalidate()
        validationTimer = nil
        publishSilenceMeterSnapshot()
        partialBufferState.clear()
        await worker.prepareForGraphRecovery()
        cleanupEngine()

        let engine = injectedEngine ?? AVAudioEngine()
        audioEngine = engine

        let targetSampleRate = resolveTargetSampleRate(engine: engine, source: source)

        do {
            try await setupGraphAndStart(
                engine: engine,
                writingTo: outputURL,
                source: source,
                retryCount: 0,
                sampleRate: targetSampleRate,
                reuseExistingWorker: true
            )
            publishSilenceMeterSnapshot()
        } catch {
            AppLogger.error(
                "Failed to recover microphone input after device change",
                category: .recordingManager,
                error: error
            )
            self.error = error
            if let onRecordingError {
                onRecordingError(error)
            } else {
                _ = await stopRecording()
            }
        }
    }

    func currentInputDeviceUID() -> String? {
        guard let inputUnit = audioEngine?.inputNode.audioUnit else { return nil }

        var deviceID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioUnitGetProperty(
            inputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            &size
        )

        guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return deviceManager.getDeviceUID(for: deviceID)
    }

    func desiredInputDeviceUID(from devices: [AudioInputDevice]) -> String? {
        let settings = AppSettingsStore.shared
        if settings.useSystemDefaultInput {
            return defaultInputDeviceUID(from: devices)
        }

        if let preferredUID = microphoneInputSelectionResolver.preferredCustomMicrophoneUID(settings: settings),
           devices.contains(where: { $0.id == preferredUID })
        {
            return preferredUID
        }

        return defaultInputDeviceUID(from: devices)
    }

    func defaultInputDeviceUID(from devices: [AudioInputDevice]) -> String? {
        if let defaultDevice = devices.first(where: \.isDefault) {
            return defaultDevice.id
        }

        if let defaultDeviceID = deviceManager.getDefaultInputDeviceIDRaw() {
            return deviceManager.getDeviceUID(for: defaultDeviceID)
        }

        return nil
    }

    func publishSilenceMeterSnapshot() {
        let silentBarLevels = Array(repeating: Float(-160.0), count: currentBarPowerLevels.count)
        publishMeterSnapshot(
            averagePower: -160.0,
            peakPower: -160.0,
            barPowerLevels: silentBarLevels
        )
    }

    nonisolated static func shouldRecoverInputDevice(
        activeInputUID: String?,
        desiredInputUID: String?,
        availableDevices: [AudioInputDevice]
    ) -> Bool {
        let availableDeviceIDs = Set(availableDevices.map(\.id))

        guard let activeInputUID else {
            return true
        }

        if !availableDeviceIDs.contains(activeInputUID) {
            return true
        }

        guard let desiredInputUID else {
            return false
        }

        return desiredInputUID != activeInputUID && availableDeviceIDs.contains(desiredInputUID)
    }
}
