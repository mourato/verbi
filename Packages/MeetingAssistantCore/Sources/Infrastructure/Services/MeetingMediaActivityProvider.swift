import AVFoundation
import Foundation

public struct MeetingMediaActivity: Equatable, Sendable {
    public let microphoneInUseByAnotherApplication: Bool
    public let cameraInUseByAnotherApplication: Bool

    public init(
        microphoneInUseByAnotherApplication: Bool = false,
        cameraInUseByAnotherApplication: Bool = false
    ) {
        self.microphoneInUseByAnotherApplication = microphoneInUseByAnotherApplication
        self.cameraInUseByAnotherApplication = cameraInUseByAnotherApplication
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
    public init() {}

    public func currentActivity() -> MeetingMediaActivity {
        MeetingMediaActivity(
            microphoneInUseByAnotherApplication: isAnyDeviceInUse(
                for: .audio,
                deviceTypes: [.microphone, .external]
            ),
            cameraInUseByAnotherApplication: isAnyDeviceInUse(
                for: .video,
                deviceTypes: [.builtInWideAngleCamera, .external]
            )
        )
    }

    private func isAnyDeviceInUse(
        for mediaType: AVMediaType,
        deviceTypes: [AVCaptureDevice.DeviceType]
    ) -> Bool {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: mediaType,
            position: .unspecified
        ).devices

        return devices.contains(where: \.isInUseByAnotherApplication)
    }
}
