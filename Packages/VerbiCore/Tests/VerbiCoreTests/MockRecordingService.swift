import Combine
import Foundation
@testable import VerbiCore

@MainActor
class MockRecordingService: RecordingServiceProtocol {
    // Properties
    var meetingState: CaptureState = .idle
    var isRecording: Bool = false
    var isTranscribing: Bool = false
    var currentMeeting: CaptureSession?
    var currentCapturePurpose: CapturePurpose?
    var isMeetingMicrophoneEnabled: Bool = false
    var transcriptionStatus = TranscriptionStatus()
    var permissionStatus = PermissionStatusManager()

    // Publishers
    var meetingStateSubject = PassthroughSubject<CaptureState, Never>()
    var isRecordingSubject = PassthroughSubject<Bool, Never>()
    var isTranscribingSubject = PassthroughSubject<Bool, Never>()
    var currentMeetingSubject = PassthroughSubject<CaptureSession?, Never>()

    var meetingStatePublisher: AnyPublisher<CaptureState, Never> {
        meetingStateSubject.eraseToAnyPublisher()
    }

    var isRecordingPublisher: AnyPublisher<Bool, Never> {
        isRecordingSubject.eraseToAnyPublisher()
    }

    var isTranscribingPublisher: AnyPublisher<Bool, Never> {
        isTranscribingSubject.eraseToAnyPublisher()
    }

    var currentMeetingPublisher: AnyPublisher<CaptureSession?, Never> {
        currentMeetingSubject.eraseToAnyPublisher()
    }

    // Track calls
    var startRecordingCalled = false
    var startCaptureCalled = false
    var stopRecordingCalled = false
    var checkPermissionCalled = false
    var requestPermissionCalled = false
    var requestPermissionSource: RecordingSource?
    var checkPermissionSource: RecordingSource?
    var openMicrophoneSettingsCalled = false
    var openPermissionSettingsCalled = false
    var requestAccessibilityPermissionCalled = false
    var openAccessibilitySettingsCalled = false
    var transcribeExternalAudioCalled = false
    var lastCapturePurpose: CapturePurpose?

    func startRecording(source: RecordingSource) async {
        startRecordingCalled = true
        currentCapturePurpose = source == .microphone ? .dictation : .meeting
        lastCapturePurpose = currentCapturePurpose
        isMeetingMicrophoneEnabled = currentCapturePurpose == .meeting
        isRecording = true
        isRecordingSubject.send(true)
        meetingState = .recording
        meetingStateSubject.send(.recording)
    }

    func startCapture(purpose: CapturePurpose) async {
        await startCapture(purpose: purpose, requestedAt: Date(), triggerLabel: "test")
    }

    func startCapture(purpose: CapturePurpose, requestedAt: Date, triggerLabel: String) async {
        _ = requestedAt
        _ = triggerLabel
        startCaptureCalled = true
        lastCapturePurpose = purpose
        currentCapturePurpose = purpose
        isMeetingMicrophoneEnabled = purpose == .meeting
        isRecording = true
        isRecordingSubject.send(true)
        meetingState = .recording
        meetingStateSubject.send(.recording)
    }

    func stopRecording() async {
        stopRecordingCalled = true
        isRecording = false
        currentCapturePurpose = nil
        isMeetingMicrophoneEnabled = false
        isRecordingSubject.send(false)
    }

    func toggleMeetingMicrophone() async {
        guard currentCapturePurpose == .meeting else { return }
        isMeetingMicrophoneEnabled.toggle()
    }

    func setMeetingMicrophoneEnabled(_ isEnabled: Bool) async {
        guard currentCapturePurpose == .meeting else { return }
        isMeetingMicrophoneEnabled = isEnabled
    }

    func checkPermission() async {
        checkPermissionCalled = true
    }

    func checkPermission(for source: RecordingSource) async {
        checkPermissionCalled = true
        checkPermissionSource = source
    }

    func requestPermission() async {
        requestPermissionCalled = true
    }

    func requestPermission(for source: RecordingSource) async {
        requestPermissionCalled = true
        requestPermissionSource = source
    }

    func openMicrophoneSettings() {
        openMicrophoneSettingsCalled = true
    }

    func openPermissionSettings() {
        openPermissionSettingsCalled = true
    }

    func requestAccessibilityPermission() {
        requestAccessibilityPermissionCalled = true
    }

    func openAccessibilitySettings() {
        openAccessibilitySettingsCalled = true
    }

    func transcribeExternalAudio(from audioURL: URL, capturePurpose: CapturePurpose) async {
        transcribeExternalAudioCalled = true
        lastCapturePurpose = capturePurpose
    }

    /// Test helper
    func simulateState(recording: Bool, transcribing: Bool) {
        isRecording = recording
        isTranscribing = transcribing
        isRecordingSubject.send(recording)
        isTranscribingSubject.send(transcribing)
    }
}
