import CoreAudio
import Foundation
import MeetingAssistantCoreInfrastructure

@MainActor
public protocol MicrophoneDeviceResolving: AnyObject {
    var availableInputDevices: [AudioInputDevice] { get }
    func getAudioDeviceID(for uid: String) -> AudioObjectID?
    func isUsableInputDeviceID(_ id: AudioObjectID) -> Bool
    func getDeviceName(for id: AudioObjectID) -> String?
    func getDefaultInputDeviceID() -> AudioObjectID?
}

extension AudioDeviceManager: MicrophoneDeviceResolving {}

@MainActor
public final class MicrophoneInputSelectionResolver {
    private let deviceManager: any MicrophoneDeviceResolving
    private let powerSourceProvider: any PowerSourceStateProviding

    public init(
        deviceManager: any MicrophoneDeviceResolving,
        powerSourceProvider: any PowerSourceStateProviding = PowerSourceStateProvider()
    ) {
        self.deviceManager = deviceManager
        self.powerSourceProvider = powerSourceProvider
    }

    public func preferredCustomMicrophoneUID(
        settings: AppSettingsStore = .shared
    ) -> String? {
        guard !settings.useSystemDefaultInput else { return nil }

        switch powerSourceProvider.currentPowerSourceState() {
        case .charging:
            return sanitizedUID(settings.microphoneWhenChargingUID)
        case .battery:
            return sanitizedUID(settings.microphoneOnBatteryUID)
        }
    }

    public func resolveCustomMicrophoneDeviceID(
        settings: AppSettingsStore = .shared
    ) -> AudioObjectID? {
        guard let preferredUID = preferredCustomMicrophoneUID(settings: settings),
              let deviceID = deviceManager.getAudioDeviceID(for: preferredUID),
              deviceManager.isUsableInputDeviceID(deviceID)
        else {
            return nil
        }

        return deviceID
    }

    public func resolvePreferredMicrophoneDeviceName(
        settings: AppSettingsStore = .shared
    ) -> String? {
        if settings.useSystemDefaultInput {
            return resolveSystemDefaultMicrophoneDeviceName()
        }

        if let customDeviceID = resolveCustomMicrophoneDeviceID(settings: settings),
           let customName = deviceManager.getDeviceName(for: customDeviceID)
        {
            return customName
        }

        return resolveSystemDefaultMicrophoneDeviceName()
    }

    public func resolveSystemDefaultMicrophoneDeviceName() -> String? {
        if let defaultDeviceID = deviceManager.getDefaultInputDeviceID(),
           let deviceName = deviceManager.getDeviceName(for: defaultDeviceID)
        {
            return deviceName
        }

        if let defaultDevice = deviceManager.availableInputDevices.first(where: \.isDefault) {
            return defaultDevice.name
        }

        return nil
    }

    public func currentPowerSourceState() -> PowerSourceState {
        powerSourceProvider.currentPowerSourceState()
    }

    private func sanitizedUID(_ uid: String?) -> String? {
        guard let uid else { return nil }
        let trimmedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedUID.isEmpty ? nil : trimmedUID
    }
}
