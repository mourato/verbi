import Combine
import Foundation
import SwiftUI
import VerbiCoreAI
import VerbiCoreAudio
import VerbiCoreCommon
import VerbiCoreData
import VerbiCoreDomain
import VerbiCoreInfrastructure

@MainActor
public class RecordingViewModel: ObservableObject {
    private let recordingManager: any RecordingServiceProtocol
    private let modelManager: any AIModelService
    private var cancellables = Set<AnyCancellable>()

    @Published public var isRecording: Bool = false
    @Published public var isTranscribing: Bool = false
    @Published public var meetingState: CaptureState = .idle
    @Published public var arePermissionsGranted: Bool = false
    @Published public var currentMeeting: CaptureSession?
    @Published public var isModelLoaded: Bool = false
    @Published public var selectedSource: RecordingSource = .microphone
    @Published public var displayDuration: String = "00:00"
    private var timer: AnyCancellable?

    public let transcriptionViewModel: TranscriptionViewModel
    public let permissionViewModel: PermissionViewModel

    public var statusText: String? {
        if isRecording {
            "status.recording".localized
        } else if isTranscribing {
            "status.transcribing".localized
        } else {
            nil
        }
    }

    public var recordButtonTitle: String {
        if isRecording {
            return "menubar.stop_recording".localized
        }

        return isModelLoaded
            ? "menubar.start_recording".localized
            : "settings.transcriptions.loading".localized
    }

    public var recordButtonIcon: String {
        if isRecording {
            return "stop.fill"
        }
        return isModelLoaded ? "record.circle" : "hourglass"
    }

    public var canStartRecording: Bool {
        isModelLoaded
    }

    public init(
        recordingManager: some RecordingServiceProtocol,
        modelManager: some AIModelService = FluidAIModelManager.shared
    ) {
        self.recordingManager = recordingManager
        self.modelManager = modelManager

        transcriptionViewModel = TranscriptionViewModel(status: recordingManager.transcriptionStatus)

        permissionViewModel = PermissionViewModel(
            manager: recordingManager.permissionStatus,
            requestMicrophone: { await recordingManager.requestPermission(for: .microphone) },
            requestScreen: { await recordingManager.requestPermission(for: .system) },
            openMicrophoneSettings: { recordingManager.openMicrophoneSettings() },
            openScreenSettings: { recordingManager.openPermissionSettings() },
            requestAccessibility: { recordingManager.requestAccessibilityPermission() },
            openAccessibilitySettings: { recordingManager.openAccessibilitySettings() }
        )

        setupBindings()
    }

    public func startRecording(source: RecordingSource? = nil) async {
        let sourceToUse = source ?? .microphone
        selectedSource = sourceToUse
        let purpose: CapturePurpose = sourceToUse == .microphone ? .dictation : .meeting
        await recordingManager.startCapture(purpose: purpose)
    }

    public func stopRecording() async {
        await recordingManager.stopRecording()
    }

    public func checkPermission() async {
        await recordingManager.checkPermission(for: selectedSource)
    }

    public func requestPermission() async {
        await recordingManager.requestPermission(for: selectedSource)
    }

    public func openMicrophoneSettings() {
        recordingManager.openMicrophoneSettings()
    }

    public func openPermissionSettings() {
        recordingManager.openPermissionSettings()
    }

    public func transcribeFile(at url: URL, capturePurpose: CapturePurpose = .dictation) async {
        await recordingManager.transcribeExternalAudio(from: url, capturePurpose: capturePurpose)
    }

    private func setupBindings() {
        recordingManager.isRecordingPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)

        recordingManager.isTranscribingPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$isTranscribing)

        recordingManager.meetingStatePublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$meetingState)

        recordingManager.currentMeetingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] meeting in
                self?.currentMeeting = meeting
                if meeting != nil {
                    self?.startTimer()
                } else {
                    self?.stopTimer()
                }
            }
            .store(in: &cancellables)

        modelManager.modelStatePublisher
            .receive(on: DispatchQueue.main)
            .map { $0 == VerbiCoreDomain.ModelState.loaded }
            .assign(to: &$isModelLoaded)

        permissionViewModel.$microphoneState
            .combineLatest(permissionViewModel.$screenState, $selectedSource)
            .map { mic, screen, source in
                source.requiredPermissionsGranted(
                    microphone: mic,
                    screenRecording: screen
                )
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$arePermissionsGranted)
    }

    private func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateDisplayDuration()
            }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        displayDuration = "00:00"
    }

    private func updateDisplayDuration() {
        guard let meeting = currentMeeting else { return }
        let duration = Int(meeting.duration)
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let seconds = duration % 60

        if hours > 0 {
            displayDuration = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            displayDuration = String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
