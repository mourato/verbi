import Combine
@testable import VerbiCore
import XCTest

@MainActor
final class RecordingViewModelTests: XCTestCase {
    var viewModel: RecordingViewModel!
    var mockService: MockRecordingService!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        mockService = MockRecordingService()
        viewModel = RecordingViewModel(recordingManager: mockService)
        cancellables = []
    }

    override func tearDown() async throws {
        viewModel = nil
        mockService = nil
        cancellables = nil
    }

    func testInitialState() {
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertFalse(viewModel.isTranscribing)
        XCTAssertNil(viewModel.statusText)
        XCTAssertFalse(viewModel.transcriptionViewModel.progressPercentage > 0)
    }

    func testStartRecording() async {
        await viewModel.startRecording()

        XCTAssertTrue(mockService.startCaptureCalled)
        XCTAssertEqual(mockService.lastCapturePurpose, .dictation)

        mockService.simulateState(recording: true, transcribing: false)

        await waitUntil(message: "Recording state should propagate to the view model.") {
            self.viewModel.isRecording && self.viewModel.statusText == "status.recording".localized
        }

        XCTAssertTrue(viewModel.isRecording)
        XCTAssertEqual(viewModel.statusText, "status.recording".localized)
    }

    func testStopRecording() async {
        mockService.simulateState(recording: true, transcribing: false)
        await waitUntil { self.viewModel.isRecording }

        await viewModel.stopRecording()

        XCTAssertTrue(mockService.stopRecordingCalled)

        mockService.simulateState(recording: false, transcribing: true)
        await waitUntil(message: "Transcribing state should propagate to the view model.") {
            !self.viewModel.isRecording && self.viewModel.isTranscribing
        }

        XCTAssertFalse(viewModel.isRecording)
        XCTAssertTrue(viewModel.isTranscribing)
        XCTAssertEqual(viewModel.statusText, "status.transcribing".localized)
    }

    func testPermissionRequest() async {
        await viewModel.requestPermission()
        XCTAssertTrue(mockService.requestPermissionCalled)
    }

    func testChildViewModelInitialization() {
        XCTAssertTrue(
            viewModel.transcriptionViewModel.status === mockService.transcriptionStatus,
        )
    }

    func testTranscribeFile_ForwardsExplicitCapturePurpose() async {
        await viewModel.transcribeFile(
            at: URL(fileURLWithPath: "/tmp/imported.wav"),
            capturePurpose: .meeting,
        )

        XCTAssertTrue(mockService.transcribeExternalAudioCalled)
        XCTAssertEqual(mockService.lastCapturePurpose, .meeting)
    }
}
