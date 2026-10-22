import Combine
import Foundation
import VerbiCoreAI
import VerbiCoreAudio
import VerbiCoreCommon
import VerbiCoreData
import VerbiCoreDomain
import VerbiCoreInfrastructure

/// Protocol defining the public interface of the recording orchestration service.
@MainActor
public protocol RecordingServiceProtocol: AnyObject {
    // Properties
    var meetingState: CaptureState { get }
    var isRecording: Bool { get }
    var isTranscribing: Bool { get }
    var currentMeeting: CaptureSession? { get }
    var currentCapturePurpose: CapturePurpose? { get }
    var isMeetingMicrophoneEnabled: Bool { get }
    var transcriptionStatus: TranscriptionStatus { get }
    var permissionStatus: PermissionStatusManager { get }

    // Publishers
    var meetingStatePublisher: AnyPublisher<CaptureState, Never> { get }
    var isRecordingPublisher: AnyPublisher<Bool, Never> { get }
    var isTranscribingPublisher: AnyPublisher<Bool, Never> { get }
    var currentMeetingPublisher: AnyPublisher<CaptureSession?, Never> { get }

    // Actions
    func startCapture(purpose: CapturePurpose) async
    func startCapture(purpose: CapturePurpose, requestedAt: Date, triggerLabel: String) async
    func startRecording(source: RecordingSource) async
    func stopRecording() async
    func toggleMeetingMicrophone() async
    func setMeetingMicrophoneEnabled(_ isEnabled: Bool) async
    func transcribeExternalAudio(from audioURL: URL, capturePurpose: CapturePurpose) async
    func checkPermission() async
    func checkPermission(for source: RecordingSource) async
    func requestPermission() async
    func requestPermission(for source: RecordingSource) async
    func openMicrophoneSettings()
    func openPermissionSettings()
    func requestAccessibilityPermission()
    func openAccessibilitySettings()
}

public extension RecordingServiceProtocol {
    func transcribeExternalAudio(from audioURL: URL) async {
        await transcribeExternalAudio(from: audioURL, capturePurpose: .dictation)
    }
}
