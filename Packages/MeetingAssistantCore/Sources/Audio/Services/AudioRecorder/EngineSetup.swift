import AppKit
import Atomics
@preconcurrency import AVFoundation
import Combine
import CoreAudio
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import os.log

extension AudioRecorder {
    func increaseDefaultMicrophoneInputVolumeIfPossible() {
        guard deviceManager.setDefaultInputVolumeToMaximum() else {
            AppLogger.debug(
                "Unable to set default microphone input volume to maximum (property not available or not settable).",
                category: .recordingManager
            )
            return
        }

        AppLogger.info(
            "Default microphone input volume set to maximum at recording start.",
            category: .recordingManager
        )
    }

    /// Resolves the target sample rate for the recording session.
    ///
    /// When recording microphone audio, the input device's native (nominal) sample rate
    /// is preferred. Using the output node rate instead can cause USB audio devices to
    /// enter a perpetual "reconfig pending" loop when in/out rates differ, producing silence.
    func resolveTargetSampleRate(
        engine: AVAudioEngine,
        source: RecordingSource
    ) -> Double {
        // Try the input device's nominal sample rate first (most reliable for USB mics)
        if source.requiresMicrophonePermission,
           let inputUnit = engine.inputNode.audioUnit
        {
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

            if status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown),
               let nominalRate = deviceManager.getDeviceNominalSampleRate(for: deviceID),
               nominalRate > 0
            {
                AppLogger.info(
                    "Using input device nominal sample rate",
                    category: .recordingManager,
                    extra: [
                        "deviceID": deviceID,
                        "deviceName": deviceManager.getDeviceName(for: deviceID) ?? "Unknown",
                        "nominalRate": nominalRate
                    ]
                )
                return nominalRate
            }
        }

        // Fallback: engine output node (hardware output rate)
        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if outputRate > 0 {
            AppLogger.info(
                "Falling back to output node sample rate",
                category: .recordingManager,
                extra: ["outputRate": outputRate]
            )
            return outputRate
        }

        // Last resort: default constant
        AppLogger.warning(
            "Using default sample rate constant as last resort",
            category: .recordingManager,
            extra: ["defaultRate": Constants.outputSampleRate]
        )
        return Constants.outputSampleRate
    }

    func setupGraphAndStart(
        engine: AVAudioEngine,
        writingTo outputURL: URL,
        source: RecordingSource,
        retryCount: Int,
        sampleRate: Double,
        reuseExistingWorker: Bool = false
    ) async throws {
        AppLogger.debug("Setting up Audio Engine...", category: .recordingManager)

        let mixer = AVAudioMixerNode()
        engine.attach(mixer)

        mixerNode = mixer

        // Apply custom microphone selection before configuring the engine graph.
        // This uses a system default input override instead of AUHAL device manipulation,
        // avoiding aggregate device creation that destabilizes Bluetooth audio.
        var originalDefaultInputID: AudioObjectID?
        if source.requiresMicrophonePermission, retryCount == 0 {
            originalDefaultInputID = applyPreferredInputDeviceOverride()
        } else if source.requiresMicrophonePermission, !AppSettingsStore.shared.useSystemDefaultInput {
            AppLogger.warning(
                "Retrying startup with system default input to bypass unstable custom device selection",
                category: .recordingManager,
                extra: ["retryCount": retryCount]
            )
        }

        // Small delay to let CoreAudio propagate the default device change.
        // Without this, the engine may still see the previous default.
        if originalDefaultInputID != nil {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        AppLogger.debug("Configuring inputs...", category: .recordingManager)
        try configureInputs(engine: engine, mixer: mixer, source: source, sampleRate: sampleRate)

        // Log current input device for debugging (read-only, no AudioUnitSetProperty)
        if let inputUnit = engine.inputNode.audioUnit {
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

            if status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) {
                let deviceName = deviceManager.getDeviceName(for: deviceID) ?? "Unknown"
                let usable = deviceManager.isUsableInputDeviceID(deviceID)
                AppLogger.info(
                    "Current input device after graph setup",
                    category: .recordingManager,
                    extra: ["deviceID": deviceID, "name": deviceName, "usable": usable]
                )
            }
        }

        AppLogger.debug("Configuring worker...", category: .recordingManager)
        if reuseExistingWorker {
            installWorkerTap(on: mixer)
        } else {
            try await configureWorker(writingTo: outputURL, mixer: mixer)
        }

        // Increase maximum frames per slice to avoid kAudioUnitErr_TooManyFramesToProcess (-10874)
        // when hardware or drivers send buffers larger than the default 512 frames.
        // Using 2048 to reduce HALC overload risk while still handling most buffer sizes.
        let safeMaxFrames: AVAudioFrameCount = 2048
        engine.mainMixerNode.auAudioUnit.maximumFramesToRender = safeMaxFrames
        mixer.auAudioUnit.maximumFramesToRender = safeMaxFrames
        engine.outputNode.auAudioUnit.maximumFramesToRender = safeMaxFrames

        // Also apply to inputNode if we are using it (to be safe against Input AU errors too)
        if source == .microphone || source == .all {
            engine.inputNode.auAudioUnit.maximumFramesToRender = safeMaxFrames
        }

        AppLogger.debug(
            "Set maximumFramesToRender to \(safeMaxFrames) for mainMixer, mixer, and outputNode",
            category: .recordingManager
        )

        AppLogger.debug("Starting engine...", category: .recordingManager)
        try await startAudioEngine(engine, outputURL: outputURL, source: source, retryCount: retryCount)

        // Restore the original system default input device now that the engine is running.
        // The running engine has latched onto the device and won't be affected.
        restoreSystemDefaultInputDevice(originalDefaultInputID)

        currentRecordingURL = outputURL
        dumpAudioDiagnostics(engine: engine, source: source)
        AppLogger.debug("Audio Engine setup complete.", category: .recordingManager)
    }

    private func configureInputs(
        engine: AVAudioEngine,
        mixer: AVAudioMixerNode,
        source: RecordingSource,
        sampleRate: Double
    ) throws {
        if source == .microphone || source == .all {
            AppLogger.debug("Connecting Microphone...", category: .recordingManager)
            try connectMicrophone(to: engine, mixer: mixer)
        }

        if source == .system || source == .all {
            AppLogger.debug("Connecting System Audio...", category: .recordingManager)
            try connectSystemAudio(to: engine, mixer: mixer, sampleRate: sampleRate)
        }

        // Connect mixer to mainMixer without forcing a specific format.
        // This allows the engine to align with the hardware output sample rate (e.g., 44.1kHz or 48kHz)
        // preventing "Invalid Element" (-10877) errors due to failed graph updates or incompatible conversions.
        let mainMixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        AppLogger.debug("Main Mixer Output Format: \(mainMixerFormat)", category: .recordingManager)

        engine.connect(mixer, to: engine.mainMixerNode, format: mainMixerFormat)
        engine.mainMixerNode.outputVolume = 0.0
    }

    private func connectMicrophone(to engine: AVAudioEngine, mixer: AVAudioMixerNode) throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            // This should already be caught by the check in startRecording, but just in case:
            throw AudioRecorderError.permissionDenied
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: Constants.tapBusNumber)

        guard inputFormat.sampleRate > 0 else {
            AppLogger.warning(
                "Microphone input has invalid sample rate. Skipping connection.",
                category: .recordingManager
            )
            return
        }

        guard inputFormat.channelCount > 0 else {
            AppLogger.warning("Microphone input has 0 channels. Skipping connection.", category: .recordingManager)
            return
        }

        guard inputFormat.commonFormat == .pcmFormatFloat32 else {
            AppLogger.warning(
                "Microphone input format is not Float32 (\(inputFormat.commonFormat.rawValue)). Switching to conversion.",
                category: .recordingManager
            )
            // Instead of skipping, we should let AVAudioEngine handle it or log it clearly
            engine.connect(inputNode, to: mixer, format: inputFormat)
            microphoneMixingDestination = inputNode.destination(forMixer: mixer, bus: Constants.tapBusNumber)
            microphoneMixingDestination?.volume = 1.0
            return
        }

        AppLogger.debug("Connecting Microphone with format: \(inputFormat)", category: .recordingManager)
        engine.connect(inputNode, to: mixer, format: inputFormat)
        microphoneMixingDestination = inputNode.destination(forMixer: mixer, bus: Constants.tapBusNumber)
        microphoneMixingDestination?.volume = 1.0

        if Constants.micDiagnosticsEnabled {
            startMicDiagnostics(for: inputNode)
        }
    }

    private func connectSystemAudio(to engine: AVAudioEngine, mixer: AVAudioMixerNode, sampleRate: Double) throws {
        let sourceNode = createSystemSourceNode(
            queue: systemAudioQueue,
            partialState: partialBufferState
        )

        systemAudioSourceNode = sourceNode
        engine.attach(sourceNode)

        guard let systemFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate, // Use aligned Hardware Rate
            channels: 2,
            interleaved: false
        ) else {
            throw AudioRecorderError.invalidRecordingFormat
        }

        engine.connect(sourceNode, to: mixer, format: systemFormat)
    }

    private func configureWorker(writingTo url: URL, mixer: AVAudioMixerNode) async throws {
        // Use the mixer's actual output format for the Tap.
        // This avoids asking the Tap to perform sample rate conversion, which can be fragile.
        let tapFormat = mixer.outputFormat(forBus: 0)
        AppLogger.debug("Configuring Worker with format: \(tapFormat)", category: .recordingManager)

        try await worker.start(writingTo: url, format: tapFormat, fileFormat: AppSettingsStore.shared.audioFormat)

        installWorkerTap(on: mixer, format: tapFormat)
    }

    private func installWorkerTap(on mixer: AVAudioMixerNode, format: AVAudioFormat? = nil) {
        let worker = worker
        let tapFormat = format ?? mixer.outputFormat(forBus: 0)
        mixer.installTap(
            onBus: 0,
            bufferSize: Constants.tapBufferSize,
            format: tapFormat // Request exact same format to avoid conversion overhead
        ) { @Sendable buffer, _ in
            worker.process(buffer)
        }
    }

    private func startAudioEngine(
        _ engine: AVAudioEngine,
        outputURL: URL,
        source: RecordingSource,
        retryCount: Int
    ) throws {
        AppLogger.debug("Preparing engine...", category: .recordingManager)

        engine.prepare()
        try engine.start()

        AppLogger.debug("Engine started. IsRunning: \(engine.isRunning)", category: .recordingManager)
        isRecording = true
        startValidationTimer(url: outputURL, source: source, retryCount: retryCount)
        AppLogger.info("Audio engine started successfully", category: .recordingManager)
    }

    private func dumpAudioDiagnostics(engine: AVAudioEngine, source: RecordingSource) {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: Constants.tapBusNumber)

        var diagnostics: [String: Any] = [
            "engineRunning": engine.isRunning,
            "source": source.rawValue,
            "inputSampleRate": inputFormat.sampleRate,
            "inputChannels": inputFormat.channelCount,
            "inputCommonFormat": inputFormat.commonFormat.rawValue
        ]

        // Resolve input device identity from audio unit
        if let inputUnit = inputNode.audioUnit {
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

            if status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) {
                diagnostics["inputDeviceID"] = deviceID
                diagnostics["inputDeviceName"] = deviceManager.getDeviceName(for: deviceID) ?? "Unknown"
                diagnostics["inputDeviceUID"] = deviceManager.getDeviceUID(for: deviceID) ?? "Unknown"
                diagnostics["inputDeviceVolume"] = deviceManager.getInputVolume(for: deviceID) as Any
                diagnostics["inputDeviceMuted"] = deviceManager.getInputMute(for: deviceID) as Any
                diagnostics["inputDeviceChannels"] = deviceManager.getInputChannelCount(for: deviceID) as Any
                diagnostics["inputDeviceUsable"] = deviceManager.isUsableInputDeviceID(deviceID)
            } else {
                diagnostics["inputDeviceError"] = "Failed to query (status: \(status), deviceID: \(deviceID))"
            }
        } else {
            diagnostics["inputUnit"] = "nil"
        }

        // System default device for comparison
        if let defaultID = deviceManager.getDefaultInputDeviceIDRaw() {
            diagnostics["systemDefaultDeviceID"] = defaultID
            diagnostics["systemDefaultDeviceName"] = deviceManager.getDeviceName(for: defaultID) ?? "Unknown"
        }

        // Output device info (critical — engine is driven by the output device)
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        diagnostics["outputSampleRate"] = outputFormat.sampleRate
        diagnostics["outputChannels"] = outputFormat.channelCount

        if let outputUnit = engine.outputNode.audioUnit {
            var outputDeviceID: AudioObjectID = 0
            var outSize = UInt32(MemoryLayout<AudioObjectID>.size)
            let outStatus = AudioUnitGetProperty(
                outputUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &outputDeviceID,
                &outSize
            )
            if outStatus == noErr, outputDeviceID != AudioObjectID(kAudioObjectUnknown) {
                diagnostics["outputDeviceID"] = outputDeviceID
                diagnostics["outputDeviceName"] = deviceManager.getDeviceName(for: outputDeviceID) ?? "Unknown"
                if let nominalRate = deviceManager.getDeviceNominalSampleRate(for: outputDeviceID) {
                    diagnostics["outputDeviceNominalRate"] = nominalRate
                }
            } else {
                diagnostics["outputDeviceError"] = "Failed to query (status: \(outStatus), deviceID: \(outputDeviceID))"
            }
        }

        AppLogger.info(
            "Recording audio diagnostic dump",
            category: .recordingManager,
            extra: diagnostics
        )
    }
}
