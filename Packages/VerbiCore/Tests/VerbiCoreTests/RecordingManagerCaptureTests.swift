import AppKit
import AVFoundation
import Combine
import CryptoKit
@testable import VerbiCore
@testable import VerbiCoreCommon
@testable import VerbiCoreDomain
@testable import VerbiCoreInfrastructure
@testable import VerbiCoreUI
import XCTest

@MainActor
final class RecordingManagerCaptureTests: XCTestCase {
    private var manager: RecordingManager?
    private var mockMic: MockAudioRecorder?
    private var mockSystem: MockSystemAudioCapture?
    private var mockStorage: MockStorageService?
    private var readyRetryProviders: Set<TranscriptionProvider> = []

    override func setUp() async throws {
        try await super.setUp()
        try AppSettingsTestIsolationLock.acquire()
        AppSettingsStore.shared.resetToDefaults()
        let mic = MockAudioRecorder()
        let system = MockSystemAudioCapture()
        let storage = MockStorageService()
        mockMic = mic
        mockSystem = system
        mockStorage = storage
        manager = RecordingManager(
            dictationRecorder: mic,
            meetingRecorder: mic,
            systemRecorder: system,
            transcriptionClient: MockTranscriptionClient(),
            postProcessingService: MockPostProcessingService(),
            storage: storage,
            activeAppContextProvider: MockActiveAppContextProvider(),
            captureContextResolver: MockCaptureContextResolver(),
            apiKeyExists: { _ in true },
            transcriptionAPIKeyExists: { [weak self] provider in
                self?.readyRetryProviders.contains(provider) == true
            },
            isLocalRetryModelReady: { _ in true }
        )
    }

    override func tearDown() async throws {
        await manager?.reset()
        manager = nil
        mockMic = nil
        mockSystem = nil
        mockStorage = nil
        readyRetryProviders = []
        await RecordingExclusivityCoordinator.shared.endRecording()
        await RecordingExclusivityCoordinator.shared.endAssistant()
        AppSettingsStore.shared.resetToDefaults()
        AppSettingsTestIsolationLock.release()
        try await super.tearDown()
    }

    func testInitialization() throws {
        let manager = try XCTUnwrap(manager)
        XCTAssertNotNil(manager)
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isTranscribing)
    }

    func testStorageServiceUsage() async throws {
        let manager = try XCTUnwrap(manager)
        let mockStorage = try XCTUnwrap(mockStorage)

        await manager.startRecording()
        XCTAssertTrue(mockStorage.createRecordingURLCalled)
    }

    func testCheckPermissions_WhenBothGranted() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockSystem = try XCTUnwrap(mockSystem)

        mockMic.permissionGranted = true
        mockSystem.permissionGranted = true

        await manager.checkPermission()

        XCTAssertTrue(manager.hasRequiredPermissions)
    }

    func testCheckPermissions_WhenOneDenied() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockSystem = try XCTUnwrap(mockSystem)

        mockMic.permissionGranted = true
        mockSystem.permissionGranted = false

        await manager.checkPermission(for: .all)

        XCTAssertFalse(manager.hasRequiredPermissions)
    }

    func testStartRecording_Success() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockSystem = try XCTUnwrap(mockSystem)

        mockMic.permissionGranted = true
        mockSystem.permissionGranted = true

        await manager.startRecording()

        XCTAssertTrue(manager.isRecording)
        XCTAssertTrue(mockMic.startRecordingCalled)
    }

    func testStartRecording_FailsIfAlreadyRecording() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)

        await manager.startRecording()

        mockMic.startRecordingCalled = false

        await manager.startRecording()

        XCTAssertFalse(mockMic.startRecordingCalled)
    }

    func testSharedRecorderState_DoesNotMarkRecordingWhenManagerHasNoOwnedCapture() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)

        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isStartingRecording)
        XCTAssertNil(manager.currentCapturePurpose)

        mockMic.isRecording = true
        await Task.yield()
        await waitUntil(message: "Shared recorder state should not mark the manager as recording.") {
            !manager.isRecording
        }

        XCTAssertFalse(manager.isRecording)
    }

    func testShouldApplyEnhancementsPostProcessing_ReturnsFalseWhenModelIsMissing() {
        let settings = AppSettingsStore.shared
        let originalPostProcessing = settings.postProcessingEnabled
        let originalSelection = settings.enhancementsAISelection

        defer {
            settings.postProcessingEnabled = originalPostProcessing
            settings.enhancementsAISelection = originalSelection
        }

        settings.postProcessingEnabled = true
        settings.enhancementsAISelection = EnhancementsAISelection(provider: .openai, selectedModel: " ")

        let shouldApply = RecordingManager.shouldApplyEnhancementsPostProcessing(
            settings: settings,
            kernelMode: .meeting,
            apiKeyExists: { _ in true },
        )

        XCTAssertFalse(shouldApply)
    }

    func testShouldApplyEnhancementsPostProcessing_ReturnsTrueWhenConfigurationIsReady() {
        let settings = AppSettingsStore.shared
        let originalPostProcessing = settings.postProcessingEnabled
        let originalSelection = settings.enhancementsAISelection

        defer {
            settings.postProcessingEnabled = originalPostProcessing
            settings.enhancementsAISelection = originalSelection
        }

        settings.postProcessingEnabled = true
        settings.enhancementsAISelection = EnhancementsAISelection(provider: .openai, selectedModel: "gpt-4o-mini")

        let shouldApply = RecordingManager.shouldApplyEnhancementsPostProcessing(
            settings: settings,
            kernelMode: .meeting,
            apiKeyExists: { _ in true },
        )

        XCTAssertTrue(shouldApply)
    }

    func testShouldApplyEnhancementsPostProcessing_AllowsDictationWhenConfigurationIsReady() {
        let settings = AppSettingsStore.shared
        let originalPostProcessing = settings.postProcessingEnabled
        let originalMeetingSelection = settings.enhancementsAISelection
        let originalDictationSelection = settings.enhancementsDictationAISelection

        defer {
            settings.postProcessingEnabled = originalPostProcessing
            settings.enhancementsAISelection = originalMeetingSelection
            settings.enhancementsDictationAISelection = originalDictationSelection
        }

        settings.postProcessingEnabled = true
        settings.enhancementsDictationAISelection = EnhancementsAISelection(
            provider: .openai,
            selectedModel: "gpt-4o-mini",
        )

        let shouldApply = RecordingManager.shouldApplyEnhancementsPostProcessing(
            settings: settings,
            kernelMode: .dictation,
            apiKeyExists: { _ in true },
        )

        XCTAssertTrue(shouldApply)
    }

    func testShouldApplyEnhancementsPostProcessing_DictationIgnoresMeetingGlobalToggle() {
        let settings = AppSettingsStore.shared
        let originalPostProcessing = settings.postProcessingEnabled
        let originalDictationSelection = settings.enhancementsDictationAISelection

        defer {
            settings.postProcessingEnabled = originalPostProcessing
            settings.enhancementsDictationAISelection = originalDictationSelection
        }

        settings.postProcessingEnabled = false
        settings.enhancementsDictationAISelection = EnhancementsAISelection(
            provider: .openai,
            selectedModel: "gpt-4o-mini",
        )

        let shouldApply = RecordingManager.shouldApplyEnhancementsPostProcessing(
            settings: settings,
            kernelMode: .dictation,
            apiKeyExists: { _ in true },
        )

        XCTAssertTrue(shouldApply)
    }

    func testPromptWithDictationRuleOverrides_EmbedsLanguageAndCustomInstructionsAsPriorityBlock() throws {
        let manager = try XCTUnwrap(manager)
        let settings = AppSettingsStore.shared
        let originalStyles = settings.dictationStyles

        defer {
            settings.dictationStyles = originalStyles
            manager.dictationStartBundleIdentifier = nil
        }

        settings.dictationStyles = [
            DictationStyle(
                name: "Engineering notes",
                iconSymbol: "chevron.left.forwardslash.chevron.right",
                promptInstructions: "Keep terminology concise and developer-focused.",
                forceMarkdownOutput: false,
                replaceBasePrompt: false,
                outputLanguage: .english,
                targets: [
                    .app(bundleIdentifier: "com.microsoft.VSCode")
                ]
            )
        ]
        manager.dictationStartBundleIdentifier = "com.microsoft.VSCode"

        let basePrompt = PostProcessingPrompt(
            title: "Dictation",
            promptText: "Base dictation prompt",
        )
        let resolvedPrompt = manager.promptWithDictationRuleOverrides(prompt: basePrompt, settings: settings)

        XCTAssertTrue(
            resolvedPrompt.promptText.contains("<\(AIPromptTemplates.siteOrAppPriorityTag)>"),
            "Expected site/app priority wrapper in prompt",
        )
        XCTAssertTrue(
            resolvedPrompt.promptText.contains("<OUTPUT_LANGUAGE>"),
            "Expected output language instruction to be included",
        )
        XCTAssertTrue(
            resolvedPrompt.promptText.contains("Translate the final output to English."),
            "Expected explicit translation requirement",
        )
        XCTAssertTrue(
            resolvedPrompt.promptText.contains("Keep terminology concise and developer-focused."),
            "Expected custom app instructions to be included",
        )
    }

    func testPromptWithDictationRuleOverrides_ReplacesBasePromptWhenStyleRequiresReplacement() throws {
        let manager = try XCTUnwrap(manager)
        let settings = AppSettingsStore.shared
        let originalStyles = settings.dictationStyles

        defer {
            settings.dictationStyles = originalStyles
            manager.dictationStartBundleIdentifier = nil
        }

        settings.dictationStyles = [
            DictationStyle(
                name: "Direct output",
                iconSymbol: "text.quote",
                promptInstructions: "Use a direct style prompt as the full instruction set.",
                forceMarkdownOutput: false,
                replaceBasePrompt: true,
                outputLanguage: .original,
                targets: [
                    .app(bundleIdentifier: "com.microsoft.VSCode")
                ]
            )
        ]
        manager.dictationStartBundleIdentifier = "com.microsoft.VSCode"

        let basePrompt = PostProcessingPrompt(
            title: "Dictation",
            promptText: "Base dictation prompt",
        )
        let resolvedPrompt = manager.promptWithDictationRuleOverrides(prompt: basePrompt, settings: settings)

        XCTAssertEqual(
            resolvedPrompt.promptText,
            "Use a direct style prompt as the full instruction set.",
            "Expected style prompt to replace the original base prompt",
        )
        XCTAssertFalse(
            resolvedPrompt.promptText.contains("Base dictation prompt"),
            "Expected original prompt content to be replaced",
        )
    }
}
