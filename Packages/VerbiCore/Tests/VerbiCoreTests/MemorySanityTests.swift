@testable import VerbiCore
import XCTest

@MainActor
final class MemorySanityTests: XCTestCase {
    func verifyDeallocation(
        of object: (some AnyObject)?,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        weak let weakObject = object
        XCTAssertNotNil(weakObject, "Object should not be nil before deallocation check", file: file, line: line)

    }

    func testRecordingManagerDeallocation() async {
        var manager: RecordingManager? = RecordingManager(
            micRecorder: MockAudioRecorder(),
            systemRecorder: MockAudioRecorder(),
            transcriptionClient: MockTranscriptionClient(),
            postProcessingService: MockPostProcessingService(),
            storage: MockStorageService(),
        )
        weak let weakManager = manager

        XCTAssertNotNil(weakManager)

        manager = nil

        await waitUntil(message: "RecordingManager should deallocate after references are released.") {
            weakManager == nil
        }
        XCTAssertNil(weakManager, "RecordingManager should have been deallocated")
    }

    func testPostProcessingServicePersistence() async {
        var service: PostProcessingService? = PostProcessingService.shared
        weak let weakService = service

        XCTAssertNotNil(weakService)

        service = nil

        await waitUntil(message: "Shared PostProcessingService should remain retained.") {
            weakService != nil
        }
        XCTAssertNotNil(weakService, "PostProcessingService.shared should remain allocated")
        XCTAssertIdentical(weakService, PostProcessingService.shared, "Local reference must be the shared instance")
    }

    func testTranscriptionClientPersistence() async {
        var client: TranscriptionClient? = TranscriptionClient.shared
        weak let weakClient = client

        XCTAssertNotNil(weakClient)

        client = nil

        await waitUntil(message: "Shared TranscriptionClient should remain retained.") {
            weakClient != nil
        }
        XCTAssertNotNil(weakClient, "TranscriptionClient.shared should remain allocated")
        XCTAssertIdentical(weakClient, TranscriptionClient.shared, "Local reference must be the shared instance")
    }
}
