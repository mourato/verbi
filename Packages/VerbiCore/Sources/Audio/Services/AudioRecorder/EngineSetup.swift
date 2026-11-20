import AppKit
@preconcurrency import AVFoundation
import Combine
import CoreAudio
import Foundation
import os.log
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

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

    func resolveTargetSampleRate(
        engine: AVAudioEngine,
        source: RecordingSource
    ) -> Double {
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

        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if outputRate > 0 {
            AppLogger.info(
                "Falling back to output node sample rate",
                category: .recordingManager,
                extra: ["outputRate": outputRate]
            )
            return outputRate
        }

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

        defer { restoreSystemDefaultInputDevice(originalDefaultInputID) }

        if originalDefaultInputID != nil {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        AppLogger.debug("Configuring inputs...", category: .recordingManager)
        try configureInputs(engine: engine, mixer: mixer, source: source, sampleRate: sampleRate)

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

        let safeMaxFrames: AVAudioFrameCount = 2048
        engine.mainMixerNode.auAudioUnit.maximumFramesToRender = safeMaxFrames
        mixer.auAudioUnit.maximumFramesToRender = safeMaxFrames
        engine.outputNode.auAudioUnit.maximumFramesToRender = safeMaxFrames

        if source == .microphone || source == .all {
            engine.inputNode.auAudioUnit.maximumFramesToRender = safeMaxFrames
        }

        AppLogger.debug(
            "Set maximumFramesToRender to \(safeMaxFrames) for mainMixer, mixer, and outputNode",
            category: .recordingManager
        )

        AppLogger.debug("Starting engine...", category: .recordingManager)
        try await startAudioEngine(
            engine,
            outputURL: outputURL,
            source: source,
            retryCount: retryCount,
            allowsRestart: !reuseExistingWorker
        )

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

        let mainMixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        AppLogger.debug("Main Mixer Output Format: \(mainMixerFormat)", category: .recordingManager)

        engine.connect(mixer, to: engine.mainMixerNode, format: mainMixerFormat)
        engine.mainMixerNode.outputVolume = 0.0
    }

    private func connectMicrophone(to engine: AVAudioEngine, mixer: AVAudioMixerNode) throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
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
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ) else {
            throw AudioRecorderError.invalidRecordingFormat
        }

        engine.connect(sourceNode, to: mixer, format: systemFormat)
    }

    private func configureWorker(writingTo url: URL, mixer: AVAudioMixerNode) async throws {
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
            format: tapFormat
        ) { @Sendable buffer, _ in
            worker.process(buffer)
        }
    }

    private func startAudioEngine(
        _ engine: AVAudioEngine,
        outputURL: URL,
        source: RecordingSource,
        retryCount: Int,
        allowsRestart: Bool
    ) throws {
        guard audioEngine === engine else { throw CancellationError() }
        AppLogger.debug("Preparing engine...", category: .recordingManager)

        engine.prepare()
        try engine.start()

        AppLogger.debug("Engine started. IsRunning: \(engine.isRunning)", category: .recordingManager)
        isRecording = true
        startValidationTimer(url: outputURL, source: source, retryCount: retryCount, allowsRestart: allowsRestart)
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

        if let defaultID = deviceManager.getDefaultInputDeviceIDRaw() {
            diagnostics["systemDefaultDeviceID"] = defaultID
            diagnostics["systemDefaultDeviceName"] = deviceManager.getDeviceName(for: defaultID) ?? "Unknown"
        }

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
