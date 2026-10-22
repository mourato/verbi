import Combine
@testable import VerbiCore

@MainActor
final class GeneralSettingsAudioDeviceTestDouble: GeneralSettingsAudioDeviceManaging {
    private let subject = CurrentValueSubject<[AudioInputDevice], Never>([])

    var availableInputDevices: [AudioInputDevice] {
        subject.value
    }

    var availableInputDevicesPublisher: AnyPublisher<[AudioInputDevice], Never> {
        subject.eraseToAnyPublisher()
    }

    func refreshDevices() {}
}
