@testable import MeetingAssistantCore
import XCTest

@MainActor
final class TranscriptionLibraryViewModelLoadTests: XCTestCase {
    func testLoadIfNeededExecutesOnlyOnceUntilForced() async {
        let storage = MockStorageService()
        let mockId = UUID()
        storage.mockTranscriptions = [
            CaptureArtifact(
                id: mockId,
                meeting: CaptureSession(id: mockId, app: .microsoftTeams, startTime: Date(), endTime: Date().addingTimeInterval(60)),
                segments: [],
                text: "Test Text",
                rawText: "Test Text",
            ),
        ]

        let viewModel = TranscriptionLibraryViewModel(
            storage: storage,
            meetingRepository: MockMeetingRepository(),
            meetingQAService: MockMeetingQAService(),
            keychain: TestTranscriptionKeychainProvider(),
        )

        await viewModel.loadIfNeeded()
        XCTAssertEqual(storage.loadMetadataCallCount, 1)
        XCTAssertEqual(viewModel.transcriptions.count, 1)

        // Second call to loadIfNeeded should skip reloading
        await viewModel.loadIfNeeded()
        XCTAssertEqual(storage.loadMetadataCallCount, 1)

        // Explicit loadTranscriptions should reload
        await viewModel.loadTranscriptions()
        XCTAssertEqual(storage.loadMetadataCallCount, 2)
    }
}
