import AVFoundation
import Foundation
import MeetingAssistantCoreDomain

public struct MeetingMediaActivity: Equatable, Sendable {
    public let microphoneInUseByAnotherApplication: Bool
    public let cameraInUseByAnotherApplication: Bool
    public let signals: MeetingDetectionSignals

    public init(
        microphoneInUseByAnotherApplication: Bool = false,
        cameraInUseByAnotherApplication: Bool = false,
        signals: MeetingDetectionSignals = MeetingDetectionSignals()
    ) {
        self.microphoneInUseByAnotherApplication = microphoneInUseByAnotherApplication
        self.cameraInUseByAnotherApplication = cameraInUseByAnotherApplication
        self.signals = signals
    }

    public var isActive: Bool {
        microphoneInUseByAnotherApplication || cameraInUseByAnotherApplication
    }
}

@MainActor
public protocol MeetingMediaActivityProviding: Sendable {
    func currentActivity() -> MeetingMediaActivity
}

@MainActor
public struct SystemMeetingMediaActivityProvider: MeetingMediaActivityProviding {
    public typealias DeviceInUseChecker = @Sendable (AVMediaType) -> Bool

    public let audioProcessProvider: any MeetingAudioProcessProviding
    private let deviceInUseChecker: DeviceInUseChecker?

    public init(
        audioProcessProvider: any MeetingAudioProcessProviding = CoreAudioMeetingProcessProvider.shared,
        deviceInUseChecker: DeviceInUseChecker? = nil
    ) {
        self.audioProcessProvider = audioProcessProvider
        self.deviceInUseChecker = deviceInUseChecker
    }

    public func currentActivity() -> MeetingMediaActivity {
        let runningProcesses = audioProcessProvider.runningInputProcesses()
        let microphoneInUse = !runningProcesses.isEmpty || isAnyDeviceInUse(
            for: .audio,
            deviceTypes: [.microphone, .external]
        )
        let cameraInUse = isAnyDeviceInUse(
            for: .video,
            deviceTypes: [.builtInWideAngleCamera, .external]
        )

        let activeCallBundleIDs = runningProcesses.compactMap(\.bundleIdentifier)

        // Select owner: prefer a known meeting app or first with a bundle ID
        let resolvedProcess = runningProcesses.first { proc in
            guard let bid = proc.bundleIdentifier else { return false }
            return MeetingApp.allCases.contains { $0.bundleIdentifiers.contains(bid) }
        } ?? runningProcesses.first { $0.bundleIdentifier != nil }

        let attribution: MeetingDetectionSignals.Attribution
        let ownerBundleID: String?
        let ownerDisplayName: String?

        if let resolvedProcess, let bid = resolvedProcess.bundleIdentifier {
            attribution = .resolved
            ownerBundleID = bid
            ownerDisplayName = resolvedProcess.displayName
        } else if microphoneInUse {
            attribution = .unattributed
            ownerBundleID = nil
            ownerDisplayName = nil
        } else {
            attribution = .unavailable
            ownerBundleID = nil
            ownerDisplayName = nil
        }

        let signals = MeetingDetectionSignals(
            microphoneOwnerBundleIdentifier: ownerBundleID,
            microphoneOwnerDisplayName: ownerDisplayName,
            attribution: attribution,
            activeCallBundleIdentifiers: activeCallBundleIDs
        )

        return MeetingMediaActivity(
            microphoneInUseByAnotherApplication: microphoneInUse,
            cameraInUseByAnotherApplication: cameraInUse,
            signals: signals
        )
    }

    private func isAnyDeviceInUse(
        for mediaType: AVMediaType,
        deviceTypes: [AVCaptureDevice.DeviceType]
    ) -> Bool {
        if let deviceInUseChecker {
            return deviceInUseChecker(mediaType)
        }

        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: mediaType,
            position: .unspecified
        ).devices

        return devices.contains(where: \.isInUseByAnotherApplication)
    }
}
