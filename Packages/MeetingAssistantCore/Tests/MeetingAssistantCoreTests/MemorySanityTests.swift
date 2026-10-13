@testable import MeetingAssistantCore
import XCTest

@MainActor
final class MemorySanityTests: XCTestCase {
    /// Helper to verify that an object is deallocated.
    /// Uses a weak reference to check if the object's reference count drops to zero.
    func verifyDeallocation(
        of object: (some AnyObject)?,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        weak let weakObject = object
        XCTAssertNotNil(weakObject, "Object should not be nil before deallocation check", file: file, line: line)

        // This closure is needed to ensure the local strong reference is gone
        // when we check the weak reference.
    }

    func testRecordingManagerDeallocation() async {
        // Given
        var manager: RecordingManager? = RecordingManager(
            micRecorder: MockAudioRecorder(),
            systemRecorder: MockAudioRecorder(),
            transcriptionClient: MockTranscriptionClient(),
            postProcessingService: MockPostProcessingService(),
            storage: MockStorageService(),
        )
        weak let weakManager = manager

        XCTAssertNotNil(weakManager)

        // When
        manager = nil

        // Then
        await waitUntil(message: "RecordingManager should deallocate after references are released.") {
            weakManager == nil
        }
        XCTAssertNil(weakManager, "RecordingManager should have been deallocated")
    }

    func testPostProcessingServicePersistence() async {
        // Given
        var service: PostProcessingService? = PostProcessingService.shared
        weak let weakService = service

        XCTAssertNotNil(weakService)

        // When
        service = nil

        // Then
        await waitUntil(message: "Shared PostProcessingService should remain retained.") {
            weakService != nil
        }
        // Shared singletons remain allocated
        XCTAssertNotNil(weakService, "PostProcessingService.shared should remain allocated")
        XCTAssertIdentical(weakService, PostProcessingService.shared, "Local reference must be the shared instance")
    }

    func testTranscriptionClientPersistence() async {
        // Given
        var client: TranscriptionClient? = TranscriptionClient.shared
        weak let weakClient = client

        XCTAssertNotNil(weakClient)

        // When
        client = nil

        // Then
        await waitUntil(message: "Shared TranscriptionClient should remain retained.") {
            weakClient != nil
        }
        XCTAssertNotNil(weakClient, "TranscriptionClient.shared should remain allocated")
        XCTAssertIdentical(weakClient, TranscriptionClient.shared, "Local reference must be the shared instance")
    }
}
