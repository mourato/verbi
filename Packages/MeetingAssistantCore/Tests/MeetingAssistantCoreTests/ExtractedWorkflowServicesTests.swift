import Combine
import Foundation
@testable import MeetingAssistantCoreDomain
@testable import MeetingAssistantCoreInfrastructure
@testable import MeetingAssistantCoreUI
import XCTest

@MainActor
final class ExtractedWorkflowServicesTests: XCTestCase {
    private var settings: AppSettingsStore!
    private var originalContextAwarenessEnabled = false
    private var originalIncludeAccessibilityText = false
    private var originalIncludeClipboard = false
    private var originalIncludeWindowOCR = false
    private var originalRedactSensitiveData = false
    private var originalExcludedBundleIDs: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        try AppSettingsTestIsolationLock.acquire()
        settings = .shared
        originalContextAwarenessEnabled = settings.contextAwarenessEnabled
        originalIncludeAccessibilityText = settings.contextAwarenessIncludeAccessibilityText
        originalIncludeClipboard = settings.contextAwarenessIncludeClipboard
        originalIncludeWindowOCR = settings.contextAwarenessIncludeWindowOCR
        originalRedactSensitiveData = settings.contextAwarenessRedactSensitiveData
        originalExcludedBundleIDs = settings.contextAwarenessExcludedBundleIDs
    }

    override func tearDown() async throws {
        settings.contextAwarenessEnabled = originalContextAwarenessEnabled
        settings.contextAwarenessIncludeAccessibilityText = originalIncludeAccessibilityText
        settings.contextAwarenessIncludeClipboard = originalIncludeClipboard
        settings.contextAwarenessIncludeWindowOCR = originalIncludeWindowOCR
        settings.contextAwarenessRedactSensitiveData = originalRedactSensitiveData
        settings.contextAwarenessExcludedBundleIDs = originalExcludedBundleIDs
        settings = nil
        AppSettingsTestIsolationLock.release()
        try await super.tearDown()
    }

    func testMeetingCalendarIntegrationService_AppliesBestMatchingEventTitle() async {
        let event = MeetingCalendarEventSnapshot(
            eventIdentifier: "event-1",
            title: " Design Review ",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3_600),
            attendees: ["Alice", "Bob"],
        )
        let calendarService = MockCalendarEventServiceForExtraction()
        calendarService.eventsToReturn = [event]
        let service = MeetingCalendarIntegrationService(
            calendarEventService: calendarService,
            ignoredEventIdentifiers: { [] },
        )

        let result = await service.applyAutomaticCalendarEventIfAvailable(
            to: CaptureSession(app: .zoom, capturePurpose: .meeting),
        )

        XCTAssertEqual(result.linkedCalendarEvent?.eventIdentifier, event.eventIdentifier)
        XCTAssertEqual(result.title, "Design Review")
    }

    func testAssistantContextCaptureService_GlobalDisabledStillUsesIndividualContextSources() async {
        settings.contextAwarenessEnabled = false
        settings.contextAwarenessIncludeAccessibilityText = true
        settings.contextAwarenessIncludeClipboard = false
        settings.contextAwarenessIncludeWindowOCR = false
        settings.contextAwarenessRedactSensitiveData = false
        settings.contextAwarenessExcludedBundleIDs = []

        let contextService = MockContextAwarenessService()
        contextService.snapshot = ContextAwarenessSnapshot(
            activeAppName: "Safari",
            activeWindowTitle: nil,
            activeAccessibilityText: "Visible text",
            clipboardText: nil,
            activeWindowOCRText: nil,
        )
        contextService.context = "CONTEXT_METADATA\n- Focused UI text (Accessibility):\nVisible text"
        let service = AssistantContextCaptureService(
            contextAwarenessService: contextService,
            textContextProvider: MockTextContextProvider(text: nil),
            textContextGuardrails: TextContextGuardrails(),
            textContextPolicy: .default,
            isAccessibilityTrusted: { true },
            requestAccessibilityPermission: {},
        )

        let result = await service.capturePostProcessingContext(
            for: CaptureSession(app: .googleMeet, capturePurpose: .meeting),
            settings: settings,
            activeTabURL: "https://example.com",
            calendarContext: nil,
            isDictationMode: false,
        )

        XCTAssertEqual(contextService.lastOptions?.includeAccessibilityText, true)
        XCTAssertTrue(result.context?.contains("Visible text") == true)
        XCTAssertEqual(
            result.items.map(\.source),
            [
                TranscriptionContextItem.Source.activeApp,
                .accessibilityText,
                .activeTabURL,
            ],
        )
    }

    func testAssistantContextCaptureService_NoSelectedGlobalSourcesSkipsContextCapture() async {
        settings.contextAwarenessEnabled = true
        settings.contextAwarenessIncludeAccessibilityText = false
        settings.contextAwarenessIncludeClipboard = false
        settings.contextAwarenessIncludeWindowOCR = false
        settings.contextAwarenessRedactSensitiveData = true
        settings.contextAwarenessExcludedBundleIDs = []

        let contextService = MockContextAwarenessService()
        contextService.snapshot = ContextAwarenessSnapshot(
            activeAppName: "Safari",
            activeWindowTitle: "Draft",
            activeAccessibilityText: "Visible text",
            clipboardText: "Clipboard",
            activeWindowOCRText: "OCR",
        )
        contextService.context = "CONTEXT_METADATA\n- Active app: Safari"
        let service = AssistantContextCaptureService(
            contextAwarenessService: contextService,
            textContextProvider: MockTextContextProvider(text: "Focused draft"),
            textContextGuardrails: TextContextGuardrails(),
            textContextPolicy: .default,
            isAccessibilityTrusted: { true },
            requestAccessibilityPermission: {},
        )

        let result = await service.capturePostProcessingContext(
            for: CaptureSession(app: .unknown, capturePurpose: .dictation),
            settings: settings,
            activeTabURL: nil,
            calendarContext: nil,
            isDictationMode: true,
        )

        XCTAssertNil(result.context)
        XCTAssertEqual(result.items, [])
        XCTAssertNil(contextService.lastOptions)
    }

    func testAssistantContextCaptureService_AppendsFocusedTextForDictationFallback() async {
        settings.contextAwarenessEnabled = true
        settings.contextAwarenessIncludeAccessibilityText = true
        settings.contextAwarenessIncludeClipboard = false
        settings.contextAwarenessIncludeWindowOCR = false
        settings.contextAwarenessRedactSensitiveData = false
        settings.contextAwarenessExcludedBundleIDs = []

        let contextService = MockContextAwarenessService()
        contextService.snapshot = ContextAwarenessSnapshot(
            activeAppName: "Safari",
            activeWindowTitle: "Draft",
            activeAccessibilityText: nil,
            clipboardText: nil,
            activeWindowOCRText: nil,
        )
        contextService.context = "CONTEXT_METADATA\n- Active app: Safari"

        let service = AssistantContextCaptureService(
            contextAwarenessService: contextService,
            textContextProvider: MockTextContextProvider(text: "Focused draft"),
            textContextGuardrails: TextContextGuardrails(),
            textContextPolicy: .default,
            isAccessibilityTrusted: { true },
            requestAccessibilityPermission: {},
        )

        let result = await service.capturePostProcessingContext(
            for: CaptureSession(app: .unknown, capturePurpose: .dictation),
            settings: settings,
            activeTabURL: nil,
            calendarContext: nil,
            isDictationMode: true,
        )

        XCTAssertTrue(
            result.items.contains(where: {
                $0.source == TranscriptionContextItem.Source.focusedText && $0.text == "Focused draft"
            }),
        )
        XCTAssertTrue(result.context?.contains("Focused draft") == true)
    }

    func testAssistantContextCaptureService_CapturesSelectedTextAtDictationStartOnlyWhenEnabled() async {
        let contextService = MockContextAwarenessService()
        let service = AssistantContextCaptureService(
            contextAwarenessService: contextService,
            textContextProvider: MockTextContextProvider(text: nil, selectedText: "Selected reference"),
            textContextGuardrails: TextContextGuardrails(),
            textContextPolicy: .default,
            isAccessibilityTrusted: { true },
            requestAccessibilityPermission: {},
        )

        let disabled = await service.captureSelectedTextAtDictationStart(
            contextSourcePolicy: DictationContextSourcePolicy(
                includeClipboard: false,
                includeWindowOCR: false,
                includeAccessibilityText: false,
                redactSensitiveData: false,
            ),
        )
        XCTAssertNil(disabled.item)

        let enabled = await service.captureSelectedTextAtDictationStart(
            contextSourcePolicy: DictationContextSourcePolicy(
                includeClipboard: false,
                includeWindowOCR: false,
                includeAccessibilityText: false,
                includeSelectedTextAtStart: true,
                redactSensitiveData: false,
            ),
        )
        XCTAssertEqual(enabled.item?.source, .selectedTextAtStart)
        XCTAssertEqual(enabled.item?.text, "Selected reference")
        XCTAssertTrue(enabled.context?.contains("<SELECTED_TEXT_AT_START>") == true)
    }

    func testAssistantContextCaptureService_SourcePolicyWithNoSourcesSkipsContextCapture() async {
        settings.contextAwarenessEnabled = true
        settings.contextAwarenessIncludeAccessibilityText = true
        settings.contextAwarenessIncludeClipboard = true
        settings.contextAwarenessIncludeWindowOCR = true
        settings.contextAwarenessRedactSensitiveData = true
        settings.contextAwarenessExcludedBundleIDs = []

        let contextService = MockContextAwarenessService()
        contextService.snapshot = ContextAwarenessSnapshot(
            activeAppName: "Safari",
            activeWindowTitle: "Draft",
            activeAccessibilityText: "Visible text",
            clipboardText: "Clipboard",
            activeWindowOCRText: "OCR",
        )
        contextService.context = "CONTEXT_METADATA\n- Active app: Safari"
        let service = AssistantContextCaptureService(
            contextAwarenessService: contextService,
            textContextProvider: MockTextContextProvider(text: "Focused draft"),
            textContextGuardrails: TextContextGuardrails(),
            textContextPolicy: .default,
            isAccessibilityTrusted: { true },
            requestAccessibilityPermission: {},
        )

        let result = await service.capturePostProcessingContext(
            for: CaptureSession(app: .unknown, capturePurpose: .dictation),
            settings: settings,
            activeTabURL: nil,
            calendarContext: nil,
            isDictationMode: true,
            contextSourcePolicy: DictationContextSourcePolicy(
                includeClipboard: false,
                includeWindowOCR: false,
                includeAccessibilityText: false,
                redactSensitiveData: true,
            ),
        )

        XCTAssertNil(result.context)
        XCTAssertEqual(result.items, [])
        XCTAssertNil(contextService.lastOptions)
    }

    func testAssistantContextCaptureService_SourcePolicyControlsCapturedSources() async {
        settings.contextAwarenessEnabled = true
        settings.contextAwarenessIncludeAccessibilityText = true
        settings.contextAwarenessIncludeClipboard = true
        settings.contextAwarenessIncludeWindowOCR = true
        settings.contextAwarenessRedactSensitiveData = true
        settings.contextAwarenessExcludedBundleIDs = []

        let contextService = MockContextAwarenessService()
        let service = AssistantContextCaptureService(
            contextAwarenessService: contextService,
            textContextProvider: MockTextContextProvider(text: nil),
            textContextGuardrails: TextContextGuardrails(),
            textContextPolicy: .default,
            isAccessibilityTrusted: { true },
            requestAccessibilityPermission: {},
        )

        _ = await service.capturePostProcessingContext(
            for: CaptureSession(app: .unknown, capturePurpose: .dictation),
            settings: settings,
            activeTabURL: nil,
            calendarContext: nil,
            isDictationMode: true,
            contextSourcePolicy: DictationContextSourcePolicy(
                includeClipboard: true,
                includeWindowOCR: false,
                includeAccessibilityText: false,
                redactSensitiveData: false,
            ),
        )

        XCTAssertEqual(contextService.lastOptions?.includeClipboard, true)
        XCTAssertEqual(contextService.lastOptions?.includeWindowOCR, false)
        XCTAssertEqual(contextService.lastOptions?.includeAccessibilityText, false)
        XCTAssertEqual(contextService.lastOptions?.redactSensitiveData, false)
    }
}

@MainActor
private final class MockCalendarEventServiceForExtraction: CalendarEventServiceProtocol, @unchecked Sendable {
    var eventsToReturn: [MeetingCalendarEventSnapshot] = []

    var eventStoreChanges: AnyPublisher<Void, Never> {
        Empty(completeImmediately: false).eraseToAnyPublisher()
    }

    func authorizationState() -> PermissionState {
        .granted
    }

    func requestAccess() async -> PermissionState {
        .granted
    }

    func openSystemSettings() {}

    func refreshSources() {}

    func fetchUpcomingEvents(
        limit _: Int,
        now _: Date,
        window _: TimeInterval,
        ignoredEventIdentifiers _: Set<String>,
    ) throws -> [MeetingCalendarEventSnapshot] {
        eventsToReturn
    }

    func bestMatchingEvent(
        at _: Date,
        in events: [MeetingCalendarEventSnapshot],
    ) -> MeetingCalendarEventSnapshot? {
        events.first
    }
}

@MainActor
private final class MockContextAwarenessService: ContextAwarenessServiceProtocol, @unchecked Sendable {
    var snapshot = ContextAwarenessSnapshot(
        activeAppName: nil,
        activeWindowTitle: nil,
        activeAccessibilityText: nil,
        clipboardText: nil,
        activeWindowOCRText: nil,
    )
    var context: String?
    var lastOptions: ContextAwarenessCaptureOptions?

    func captureSnapshot(options: ContextAwarenessCaptureOptions) async -> ContextAwarenessSnapshot {
        lastOptions = options
        return snapshot
    }

    func makePostProcessingContext(from _: ContextAwarenessSnapshot) -> String? {
        context
    }
}

private struct MockTextContextProvider: TextContextProvider {
    let text: String?
    let selectedText: String?

    init(text: String?, selectedText: String? = nil) {
        self.text = text
        self.selectedText = selectedText
    }

    func fetchTextContext() async throws -> TextContextSnapshot {
        TextContextSnapshot(
            text: text ?? "",
            source: .accessibility,
            appContext: ActiveAppContext(bundleIdentifier: "com.apple.Safari", name: "Safari", processIdentifier: 1),
        )
    }

    func fetchSelectedTextContext() async throws -> TextContextSnapshot? {
        guard let selectedText else { return nil }
        return TextContextSnapshot(
            text: selectedText,
            source: .selectedText,
            appContext: ActiveAppContext(bundleIdentifier: "com.apple.Safari", name: "Safari", processIdentifier: 1),
        )
    }
}
