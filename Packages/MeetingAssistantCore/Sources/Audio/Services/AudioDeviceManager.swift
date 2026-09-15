import AVFoundation
import Combine
import CoreAudio
import Foundation
import MeetingAssistantCoreCommon

private let audioDeviceManagerMonitoredPropertySelectors: [AudioObjectPropertySelector] = [
    kAudioHardwarePropertyDefaultInputDevice,
    kAudioHardwarePropertyDevices
]

/// Model representing an audio input device.
public struct AudioInputDevice: Identifiable, Codable, Equatable, Sendable {
    public let id: String // Unique device UID
    public let name: String // User-friendly name
    public let isDefault: Bool // Whether it's the system default input
    public var isAvailable: Bool // Whether it's currently connected

    public init(id: String, name: String, isDefault: Bool = false, isAvailable: Bool = true) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.isAvailable = isAvailable
    }
}

/// Service responsible for enumerating and observing audio input devices.
@MainActor
public final class AudioDeviceManager: ObservableObject {
    @Published public private(set) var availableInputDevices: [AudioInputDevice] = []
    private let notificationCenter: NotificationCenter
    private nonisolated(unsafe) var notificationObservers: [NSObjectProtocol] = []
    private nonisolated(unsafe) var audioPropertyListener: AudioObjectPropertyListenerBlock?

    public init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        refreshDevices()
        installNotificationObservers()
        installCoreAudioPropertyListener()
    }

    deinit {
        notificationObservers.forEach(notificationCenter.removeObserver)
        Self.removeCoreAudioPropertyListener(audioPropertyListener)
    }

    private func installNotificationObservers() {
        notificationObservers.append(notificationCenter.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
            }
        })

        notificationObservers.append(notificationCenter.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
            }
        })
    }

    private func installCoreAudioPropertyListener() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
            }
        }

        audioPropertyListener = listener

        for selector in audioDeviceManagerMonitoredPropertySelectors {
            var address = Self.propertyAddress(for: selector)
            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                .main,
                listener
            )

            guard status != noErr else { continue }

            AppLogger.warning(
                "Failed to install CoreAudio property listener",
                category: .health,
                extra: ["selector": selector, "status": status]
            )
        }
    }

    private nonisolated static func removeCoreAudioPropertyListener(
        _ audioPropertyListener: AudioObjectPropertyListenerBlock?
    ) {
        guard let audioPropertyListener else { return }

        for selector in audioDeviceManagerMonitoredPropertySelectors {
            var address = Self.propertyAddress(for: selector)
            let status = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                .main,
                audioPropertyListener
            )

            guard status != noErr else { continue }

            AppLogger.warning(
                "Failed to remove CoreAudio property listener",
                category: .health,
                extra: ["selector": selector, "status": status]
            )
        }
    }

    nonisolated static func propertyAddress(for selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    nonisolated static func monitoredPropertySelectorsForTesting() -> [AudioObjectPropertySelector] {
        audioDeviceManagerMonitoredPropertySelectors
    }

    /// Explicitly refresh the list of available devices.
    /// Performs discovery on a background thread to avoid blocking the UI.
    public func refreshDevices() {
        let task = Task.detached(priority: .userInitiated) {
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone, .external],
                mediaType: .audio,
                position: .unspecified
            )

            let defaultInput = AVCaptureDevice.default(for: .audio)

            return discoverySession.devices.map { device in
                AudioInputDevice(
                    id: device.uniqueID,
                    name: device.localizedName,
                    isDefault: device.uniqueID == defaultInput?.uniqueID,
                    isAvailable: true
                )
            }
        }

        Task { @MainActor [weak self] in
            let devices = await task.value
            self?.updateDevices(devices)
        }
    }

    @MainActor
    private func updateDevices(_ devices: [AudioInputDevice]) {
        guard availableInputDevices != devices else { return }

        availableInputDevices = devices

        AppLogger.debug(
            "Refreshed audio input devices",
            category: .health,
            extra: ["count": availableInputDevices.count]
        )
    }

    /// Check if a specific device (by UID) is currently available.
    public func isDeviceAvailable(_ uid: String) -> Bool {
        availableInputDevices.contains { $0.id == uid }
    }

    /// Retrieve the Core Audio device ID for a given unique UID.
    public nonisolated func getAudioDeviceID(for uid: String) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var propsize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propsize)

        let nDevices = Int(propsize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: nDevices)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propsize, &deviceIDs)

        for deviceID in deviceIDs {
            guard deviceID != AudioObjectID(kAudioObjectUnknown) else { continue }

            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var uidString: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let status = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &uidSize, &uidString)

            if status == noErr,
               let deviceUID = uidString?.takeRetainedValue(),
               (deviceUID as String) == uid,
               isUsableInputDeviceID(deviceID)
            {
                return deviceID
            }
        }

        return nil
    }

    /// Retrieve the Core Audio device ID for the system default input device.
    public nonisolated func getDefaultInputDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)

        guard status == noErr else { return nil }
        guard isUsableInputDeviceID(deviceID) else {
            AppLogger.warning(
                "System default input device is unavailable or invalid",
                category: .recordingManager,
                extra: ["deviceID": deviceID]
            )
            return nil
        }
        return deviceID
    }

    /// Returns the system default input device ID without usability validation.
    /// Used as an absolute last-resort fallback when `getDefaultInputDeviceID()` rejects the device.
    public nonisolated func getDefaultInputDeviceIDRaw() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )

        guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return deviceID
    }

    /// Retrieve the Core Audio device ID for the system default output device.
    public nonisolated func getDefaultOutputDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )

        guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return deviceID
    }

    /// Returns whether this Core Audio device can be used as an input source.
    public nonisolated func isUsableInputDeviceID(_ id: AudioObjectID) -> Bool {
        guard id != AudioObjectID(kAudioObjectUnknown) else { return false }
        guard let channelCount = getInputChannelCount(for: id), channelCount > 0 else { return false }
        return true
    }

    /// Returns the nominal sample rate configured on a Core Audio device.
    public nonisolated func getDeviceNominalSampleRate(for id: AudioObjectID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var sampleRate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &sampleRate)
        guard status == noErr, sampleRate > 0 else { return nil }
        return sampleRate
    }

    public nonisolated func getDeviceName(for id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name)
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    public nonisolated func getDeviceUID(for id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    public nonisolated func getInputChannelCount(for id: AudioObjectID) -> Int? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize > 0 else { return nil }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(
            capacity: Int(dataSize) / MemoryLayout<AudioBufferList>.size
        )
        defer { bufferListPointer.deallocate() }

        let dataStatus = AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, bufferListPointer)
        guard dataStatus == noErr else { return nil }

        let audioBufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return audioBufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    public nonisolated func getInputVolume(for id: AudioObjectID) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var volume: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &volume)
        guard status == noErr else { return nil }
        return volume
    }

    public nonisolated func getInputMute(for id: AudioObjectID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var mute: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &mute)
        guard status == noErr else { return nil }
        return mute != 0
    }

    /// Attempts to set the system default input device volume to maximum (1.0).
    /// Returns true when at least one input volume property is successfully updated.
    public nonisolated func setDefaultInputVolumeToMaximum() -> Bool {
        guard let deviceID = getDefaultInputDeviceID() else { return false }
        return setInputVolume(for: deviceID, to: 1.0)
    }

    /// Attempts to set input volume for the provided device.
    /// Returns true when at least one volume property is successfully updated.
    public nonisolated func setInputVolume(for id: AudioObjectID, to scalar: Float) -> Bool {
        let volume = max(0.0, min(1.0, scalar))
        var didSetAny = false

        // Try "master" element first.
        if setInputVolumeScalar(for: id, element: kAudioObjectPropertyElementMain, volume: volume) {
            didSetAny = true
        }

        // If the device exposes per-channel controls, set each channel too.
        if let channelCount = getInputChannelCount(for: id), channelCount > 0 {
            for channel in 1 ... channelCount
                where setInputVolumeScalar(for: id, element: UInt32(channel), volume: volume)
            {
                didSetAny = true
            }
        }

        return didSetAny
    }

    private nonisolated func setInputVolumeScalar(
        for id: AudioObjectID,
        element: UInt32,
        volume: Float
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )

        guard AudioObjectHasProperty(id, &address) else { return false }

        var settable = DarwinBoolean(false)
        let settableStatus = AudioObjectIsPropertySettable(id, &address, &settable)
        guard settableStatus == noErr, settable.boolValue else { return false }

        var mutableVolume = volume
        let size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectSetPropertyData(id, &address, 0, nil, size, &mutableVolume)
        return status == noErr
    }

    // MARK: - System Default Input Device Override

    /// Returns the current system default input device ID (raw, no usability check).
    /// Used to capture the original default before temporarily overriding it.
    public nonisolated func getSystemDefaultInputDeviceID() -> AudioObjectID? {
        getDefaultInputDeviceIDRaw()
    }

    /// Temporarily sets the system default input device.
    ///
    /// This is used to steer `AVAudioEngine` toward a specific microphone **without**
    /// using `kAudioOutputUnitProperty_CurrentDevice` on the AUHAL, which changes
    /// the I/O unit's device for both input AND output, forcing macOS to create an
    /// aggregate device. Aggregate devices are fragile — especially with Bluetooth
    /// headphones in SCO (call) mode — and cause cascading IO context failures.
    ///
    /// The system default is changed only briefly during engine setup and restored
    /// immediately after the engine starts.
    ///
    /// - Returns: `true` if the system default was successfully changed.
    @discardableResult
    public nonisolated func setSystemDefaultInputDevice(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceIDToSet = deviceID
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &deviceIDToSet
        )

        return status == noErr
    }
}
