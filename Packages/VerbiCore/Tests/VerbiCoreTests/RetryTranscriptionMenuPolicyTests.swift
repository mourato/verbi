@testable import VerbiCore
@testable import VerbiCoreUI
import XCTest

@MainActor
final class RetryTranscriptionMenuPolicyTests: XCTestCase {
    private var readyLocalModels: Set<LocalTranscriptionModel> = []
    private var keychain: TestTranscriptionKeychainProvider!
    private var viewModel: TranscriptionLibraryViewModel!

    override func setUp() async throws {
        try await super.setUp()
        keychain = TestTranscriptionKeychainProvider()
        readyLocalModels = []
        viewModel = TranscriptionLibraryViewModel(
            storage: MockStorageService(),
            meetingRepository: MockMeetingRepository(),
            meetingQAService: MockMeetingQAService(),
            keychain: keychain,
            isLocalModelReady: { [weak self] model in
                self?.readyLocalModels.contains(model) == true
            },
            savePanelProvider: { NSSavePanel() }
        )
    }

    override func tearDown() async throws {
        viewModel = nil
        keychain = nil
        readyLocalModels = []
        try await super.tearDown()
    }

    /// Persisted Groq capture whose key was removed, with one ready local
    /// model: the single eligible option must stay reachable in the menu.
    func testPersistedGroqWithoutKeyStillExposesTheOnlyReadyLocalModel() {
        readyLocalModels = [.parakeetTdt06BV3]
        keychain.readyProviders = []
        let metadata = makeMetadata(capturePurpose: .dictation)

        let options = viewModel.availableRetryTranscriptionOptions(for: metadata)

        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options.first?.selection.provider, .local)
        XCTAssertTrue(RetryTranscriptionMenuPolicy.showsModelOptions(options))
        XCTAssertTrue(RetryTranscriptionMenuPolicy.isRetryEnabled(options: options, hasAudio: true))
    }

    func testNoEligibleOptionDisablesRetry() {
        readyLocalModels = []
        keychain.readyProviders = []
        let metadata = makeMetadata(capturePurpose: .dictation)

        let options = viewModel.availableRetryTranscriptionOptions(for: metadata)

        XCTAssertTrue(options.isEmpty)
        XCTAssertFalse(RetryTranscriptionMenuPolicy.showsModelOptions(options))
        XCTAssertFalse(RetryTranscriptionMenuPolicy.isRetryEnabled(options: options, hasAudio: true))
    }

    func testRetryRequiresAudioEvenWithEligibleOptions() {
        readyLocalModels = [.parakeetTdt06BV3]
        let options = viewModel.availableRetryTranscriptionOptions(
            for: makeMetadata(capturePurpose: .meeting)
        )

        XCTAssertFalse(options.isEmpty)
        XCTAssertFalse(RetryTranscriptionMenuPolicy.isRetryEnabled(options: options, hasAudio: false))
    }

    private func makeMetadata(capturePurpose: CapturePurpose) -> TranscriptionMetadata {
        let id = UUID()
        return TranscriptionMetadata(
            id: id,
            meetingId: id,
            appName: "Prisma",
            appRawValue: CaptureOrigin.unknown.rawValue,
            capturePurpose: capturePurpose,
            appBundleIdentifier: nil,
            startTime: Date(),
            createdAt: Date(),
            previewText: "Dictation text",
            wordCount: 2,
            language: "en",
            isPostProcessed: false,
            duration: 10,
            audioFilePath: nil,
            inputSource: "Microphone"
        )
    }
}
