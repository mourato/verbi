import Combine
@testable import MeetingAssistantCore
import XCTest

@MainActor
final class TranscriptionViewModelTests: XCTestCase {
    var status: TranscriptionStatus?
    var viewModel: TranscriptionViewModel?
    var cancellables: Set<AnyCancellable>?

    override func setUp() async throws {
        status = TranscriptionStatus()
        viewModel = TranscriptionViewModel(status: status!)
        cancellables = []
    }

    override func tearDown() async throws {
        status = nil
        viewModel = nil
        cancellables = nil
    }

    func testInitialState() throws {
        let viewModel = try XCTUnwrap(viewModel)

        XCTAssertEqual(viewModel.statusMessage, "transcription.status.unknown".localized)
        XCTAssertEqual(viewModel.progressPercentage, 0.0)
        XCTAssertFalse(viewModel.isProcessing)
    }

    func testStateUpdates() throws {
        // Given
        let viewModel = try XCTUnwrap(viewModel)
        let status = try XCTUnwrap(status)
        var cancellables = try XCTUnwrap(cancellables)

        let expectation = XCTestExpectation(description: "ViewModel updates on status change")

        viewModel.objectWillChange
            .sink { expectation.fulfill() }
            .store(in: &cancellables)

        // When
        status.updateServiceState(.connected)
        status.updateModelState(.loaded, device: "mps")
        status.resetToIdle()

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(viewModel.serviceState, .connected)
        XCTAssertEqual(viewModel.modelState, .loaded)
        XCTAssertTrue(viewModel.isReady)
        XCTAssertEqual(viewModel.statusMessage, "transcription.status.ready".localized)
    }

    func testProcessingState() throws {
        // Given
        let viewModel = try XCTUnwrap(viewModel)
        let status = try XCTUnwrap(status)

        status.updateServiceState(.connected)
        status.updateModelState(.loaded)

        // When
        status.beginTranscription(audioDuration: 60)
        status.updateProgress(phase: .processing, percentage: 50.0)

        // Then
        XCTAssertTrue(viewModel.isProcessing)
        XCTAssertEqual(viewModel.progressPercentage, 50.0)
        XCTAssertTrue(viewModel.statusMessage.contains("50%"))
    }

    func testErrorState() throws {
        // Given
        let viewModel = try XCTUnwrap(viewModel)
        let status = try XCTUnwrap(status)

        // When
        status.recordError(.serviceUnavailable)

        // Then
        XCTAssertTrue(viewModel.hasBlockingError)
        XCTAssertEqual(viewModel.lastError, .serviceUnavailable)
        // Service unavailable sets state to .disconnected.
        XCTAssertEqual(viewModel.statusMessage, "transcription.status.disconnected".localized)
    }
}
