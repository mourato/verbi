import AudioToolbox
import Foundation
import MeetingAssistantCoreCommon

/// Controller for muting/unmuting system audio output using Core Audio.
public final class SystemAudioMuteController: Sendable {
    public static let shared = SystemAudioMuteController()

    private init() {}

    struct OutputMuteSession {
        let deviceID: AudioObjectID
        let wasMuted: Bool?
        let volumeState: OutputVolumeState?
        let canMute: Bool
        var appliedStrategy: OutputMuteStrategy?
    }

    enum OutputMuteStrategy: String {
        case muteProperty
        case volumeProperty
    }

    struct OutputScalarPropertyState: Equatable {
        let selector: AudioObjectPropertySelector
        let element: AudioObjectPropertyElement
        let value: Float
    }

    struct OutputVolumeState: Equatable {
        let properties: [OutputScalarPropertyState]
        let strategyDescription: String
    }

    /// Set the mute status of the default system audio output device.
    /// - Parameter muted: True to mute, false to unmute.
    public func setMuted(_ muted: Bool) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr else {
            throw AudioError.coreAudioError(status)
        }

        address.mSelector = kAudioDevicePropertyMute
        address.mScope = kAudioDevicePropertyScopeOutput
        address.mElement = kAudioObjectPropertyElementMain

        var muteValue: UInt32 = muted ? 1 : 0
        let muteSize = UInt32(MemoryLayout<UInt32>.size)

        let muteStatus = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            muteSize,
            &muteValue
        )

        if muteStatus != noErr {
            AppLogger.warning(
                "Failed to set system mute status",
                category: .recordingManager,
                extra: ["status": muteStatus, "muted": muted]
            )
            throw AudioError.coreAudioError(muteStatus)
        }

        AppLogger.debug(
            "System mute status changed",
            category: .recordingManager,
            extra: ["muted": muted]
        )
    }

    /// Get the current mute status of the default system audio output device.
    public func isMuted() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr else { return false }

        address.mSelector = kAudioDevicePropertyMute
        address.mScope = kAudioDevicePropertyScopeOutput
        address.mElement = kAudioObjectPropertyElementMain

        var muteValue: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)

        let muteStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &muteSize,
            &muteValue
        )

        return muteStatus == noErr && muteValue != 0
    }

    func prepareOutputMuteSession() -> OutputMuteSession? {
        guard let deviceID = getDefaultOutputDeviceID() else { return nil }

        let muteState = getOutputMuteState(for: deviceID)
        let volumeState = getOutputVolumeState(for: deviceID)
        let canMute = isMuteSettable(for: deviceID) && muteState != nil
        let canSetVolume = volumeState != nil

        guard canMute || canSetVolume else {
            AppLogger.warning(
                "System output mute skipped due to missing restore state",
                category: .recordingManager,
                extra: ["canMute": canMute, "canSetVolume": canSetVolume, "deviceID": deviceID]
            )
            return nil
        }

        if let volumeState {
            AppLogger.debug(
                "Prepared restorable output volume state",
                category: .recordingManager,
                extra: [
                    "deviceID": deviceID,
                    "strategy": volumeState.strategyDescription,
                    "propertyCount": volumeState.properties.count
                ]
            )
        }

        return OutputMuteSession(
            deviceID: deviceID,
            wasMuted: muteState,
            volumeState: volumeState,
            canMute: canMute,
            appliedStrategy: nil
        )
    }

    func applyDucking(to session: inout OutputMuteSession, levelPercent: Int) throws {
        let clampedLevel = max(0, min(100, levelPercent))

        if clampedLevel >= 100 {
            session.appliedStrategy = nil
            return
        }

        if clampedLevel == 0 {
            try applyFullMute(to: &session)
            return
        }

        guard let volumeState = session.volumeState else {
            throw AudioError.coreAudioError(OSStatus(paramErr))
        }

        let duckedVolumeState = Self.makeDuckedOutputVolumeState(
            from: volumeState,
            levelPercent: clampedLevel
        )
        try setOutputVolume(for: session.deviceID, using: duckedVolumeState)
        session.appliedStrategy = .volumeProperty
    }

    func applyMute(to session: inout OutputMuteSession) throws {
        try applyDucking(to: &session, levelPercent: 0)
    }

    private func applyFullMute(to session: inout OutputMuteSession) throws {
        var lastError: Error?

        if session.canMute {
            do {
                try setOutputMuted(true, for: session.deviceID)
                session.appliedStrategy = .muteProperty
                return
            } catch {
                lastError = error
            }
        }

        if let volumeState = session.volumeState {
            do {
                try setOutputVolumeMuted(for: session.deviceID, using: volumeState)
                session.appliedStrategy = .volumeProperty
                return
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }

        throw AudioError.coreAudioError(OSStatus(paramErr))
    }

    func restoreOutputState(from session: OutputMuteSession) {
        guard let strategy = session.appliedStrategy else { return }

        switch strategy {
        case .muteProperty:
            guard let wasMuted = session.wasMuted else { return }
            try? setOutputMuted(wasMuted, for: session.deviceID)
        case .volumeProperty:
            guard let volumeState = session.volumeState else { return }
            try? restoreOutputVolume(for: session.deviceID, using: volumeState)
        }
    }

    private func getDefaultOutputDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr else { return nil }
        return deviceID
    }

    private func isMuteSettable(for deviceID: AudioObjectID) -> Bool {
        isPropertySettable(
            deviceID,
            selector: kAudioDevicePropertyMute,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )
    }

    private func isPropertySettable(
        _ deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var isSettable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        return status == noErr && isSettable.boolValue
    }

    private func getOutputMuteState(for deviceID: AudioObjectID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var muteValue: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muteValue)
        guard status == noErr else { return nil }
        return muteValue != 0
    }

    private func setOutputMuted(_ muted: Bool, for deviceID: AudioObjectID) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            throw AudioError.coreAudioError(kAudioHardwareBadObjectError)
        }

        var muteValue: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &muteValue)
        guard status == noErr else { throw AudioError.coreAudioError(status) }
    }

    private func getOutputVolumeState(for deviceID: AudioObjectID) -> OutputVolumeState? {
        let virtualMainVolume = getOutputScalarPropertyState(
            for: deviceID,
            selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            element: kAudioObjectPropertyElementMain
        )?.value

        let channelVolumes = getOutputChannelVolumeStates(for: deviceID)
        return Self.makeOutputVolumeState(
            virtualMainVolume: virtualMainVolume,
            channelVolumes: channelVolumes
        )
    }

    static func makeOutputVolumeState(
        virtualMainVolume: Float?,
        channelVolumes: [OutputScalarPropertyState]
    ) -> OutputVolumeState? {
        if let virtualMainVolume {
            return OutputVolumeState(
                properties: [
                    OutputScalarPropertyState(
                        selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                        element: kAudioObjectPropertyElementMain,
                        value: virtualMainVolume
                    )
                ],
                strategyDescription: "virtualMainVolume"
            )
        }

        guard !channelVolumes.isEmpty else { return nil }
        return OutputVolumeState(
            properties: channelVolumes,
            strategyDescription: "channelVolumeScalar"
        )
    }

    static func makeDuckedOutputVolumeState(
        from volumeState: OutputVolumeState,
        levelPercent: Int
    ) -> OutputVolumeState {
        let clampedLevel = max(0, min(100, levelPercent))
        let scalar = Float(clampedLevel) / 100.0
        let duckedProperties = volumeState.properties.map { property in
            OutputScalarPropertyState(
                selector: property.selector,
                element: property.element,
                value: max(0.0, min(1.0, property.value * scalar))
            )
        }

        return OutputVolumeState(
            properties: duckedProperties,
            strategyDescription: volumeState.strategyDescription
        )
    }

    private func getOutputChannelVolumeStates(for deviceID: AudioObjectID) -> [OutputScalarPropertyState] {
        guard let channelCount = getOutputChannelCount(for: deviceID), channelCount > 0 else { return [] }

        return (1 ... channelCount).compactMap { channel in
            getOutputScalarPropertyState(
                for: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                element: AudioObjectPropertyElement(channel)
            )
        }
    }

    private func getOutputChannelCount(for deviceID: AudioObjectID) -> Int? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize > 0 else { return nil }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        let dataStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            bufferListPointer
        )
        guard dataStatus == noErr else { return nil }

        let audioBufferList = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer<AudioBufferList>(bufferListPointer.assumingMemoryBound(to: AudioBufferList.self))
        )
        return audioBufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func getOutputScalarPropertyState(
        for deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement
    ) -> OutputScalarPropertyState? {
        guard isPropertySettable(
            deviceID,
            selector: selector,
            scope: kAudioDevicePropertyScopeOutput,
            element: element
        ) else {
            return nil
        }

        guard let volume = getOutputScalarProperty(
            for: deviceID,
            selector: selector,
            element: element
        ) else {
            return nil
        }

        return OutputScalarPropertyState(selector: selector, element: element, value: volume)
    }

    private func getOutputScalarProperty(
        for deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement
    ) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var volume: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        guard status == noErr else { return nil }
        return volume
    }

    private func setOutputVolumeMuted(for deviceID: AudioObjectID, using volumeState: OutputVolumeState) throws {
        for property in volumeState.properties {
            try setOutputScalarProperty(
                0.0,
                for: deviceID,
                selector: property.selector,
                element: property.element
            )
        }
    }

    private func setOutputVolume(for deviceID: AudioObjectID, using volumeState: OutputVolumeState) throws {
        for property in volumeState.properties {
            try setOutputScalarProperty(
                property.value,
                for: deviceID,
                selector: property.selector,
                element: property.element
            )
        }
    }

    private func restoreOutputVolume(for deviceID: AudioObjectID, using volumeState: OutputVolumeState) throws {
        try setOutputVolume(for: deviceID, using: volumeState)
    }

    private func setOutputScalarProperty(
        _ volume: Float,
        for deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement
    ) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            throw AudioError.coreAudioError(kAudioHardwareBadObjectError)
        }

        var scalar = max(0.0, min(1.0, volume))
        let size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &scalar)
        guard status == noErr else { throw AudioError.coreAudioError(status) }
    }
}

/// Custom audio errors
public enum AudioError: Error {
    case coreAudioError(OSStatus)
}
