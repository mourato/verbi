import Foundation
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreDomain
import XCTest

final class TranscribeAudioPostProcessingTests: XCTestCase {
    func testExecuteWithPrompt_UsesPromptOverloadAndStoresProcessedText() async throws {
        let speechRecognitionClient = MeetingAssistantCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()
        let postProcessingRepository = MeetingAssistantCoreDomain.MacroMockPostProcessingRepository()

        speechRecognitionClient.healthCheckHandler = { () async throws -> Bool in true }

        let response = DomainTranscriptionResponse(
            text: "Raw transcript",
            language: "en",
            durationSeconds: 1.0,
            model: "test-model",
            processedAt: "now",
        )
        speechRecognitionClient.transcribeHandler = { _, _ in response }

        let prompt = DomainPostProcessingPrompt(title: "Summarize", content: "Summarize this")
        let requestConfiguration = DomainPostProcessingConfiguration(
            providerID: "anthropic",
            baseURL: "https://frozen.example/v1",
            modelID: "claude-frozen",
            readinessIssue: nil,
        )
        let requestSystemPrompt = "Frozen system prompt"
        var receivedPrompt: DomainPostProcessingPrompt?
        postProcessingRepository.processTranscriptionStructured_5Handler = { _, request in
            receivedPrompt = request.prompt
            XCTAssertEqual(request.mode, .meeting)
            XCTAssertTrue(request.useStructuredPipeline)
            XCTAssertEqual(request.configuration, requestConfiguration)
            XCTAssertEqual(request.systemPromptOverride, requestSystemPrompt)
            return DomainPostProcessingResult(
                processedText: "Processed transcript",
                canonicalSummary: CanonicalSummary(
                    title: "Processed transcript",
                    summary: "Processed transcript",
                    trustFlags: .init(
                        isGroundedInTranscript: true,
                        containsSpeculation: false,
                        isHumanReviewed: false,
                        confidenceScore: 0.9,
                    ),
                ),
                outputState: .structured,
            )
        }

        storageRepository.saveTranscriptionHandler = { _ in }

        let useCase = TranscribeAudioUseCase(
            speechRecognitionClient: speechRecognitionClient,
            transcriptionStorageRepository: storageRepository,
            postProcessingRepository: postProcessingRepository,
        )

        let meeting = MeetingEntity(app: .googleMeet)
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")

        let transcription = try await useCase.execute(
            audioURL: audioURL,
            meeting: meeting,
            applyPostProcessing: true,
            postProcessingPrompt: prompt,
            postProcessingSelection: DomainPostProcessingSelection(
                providerID: "anthropic",
                modelID: "claude-frozen",
                registrationID: nil,
            ),
            postProcessingConfiguration: requestConfiguration,
            postProcessingSystemPrompt: requestSystemPrompt,
        )

        XCTAssertEqual(transcription.text, "Processed transcript")
        XCTAssertEqual(transcription.canonicalSummary?.summary, "Processed transcript")
        XCTAssertNotNil(transcription.qualityProfile)
        XCTAssertEqual(postProcessingRepository.processTranscriptionCalls.count, 0)
        XCTAssertEqual(postProcessingRepository.processTranscription_2Calls.count, 0)
        XCTAssertEqual(postProcessingRepository.processTranscriptionStructured_5Calls.count, 1)
        XCTAssertEqual(receivedPrompt?.id, prompt.id)
    }

    func testExecuteWithLongMeetingInput_AttemptsStructuredPostProcessingAndStoresProviderFailure() async throws {
        let speechRecognitionClient = MeetingAssistantCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()
        let postProcessingRepository = MeetingAssistantCoreDomain.MacroMockPostProcessingRepository()
        let longTranscript = String(repeating: "Long meeting segment. ", count: 5_500)
        let providerError = PostProcessingError.apiError("context window exceeded")

        speechRecognitionClient.healthCheckHandler = { () async throws -> Bool in true }
        speechRecognitionClient.transcribeHandler = { _, _ in
            DomainTranscriptionResponse(
                text: longTranscript,
                language: "en",
                durationSeconds: 1.0,
                model: "test-model",
                processedAt: "now",
            )
        }

        var receivedInput: String?
        postProcessingRepository.processTranscriptionStructured_5Handler = { input, _ in
            receivedInput = input
            throw providerError
        }
        var persistedTranscription: TranscriptionEntity?
        var savedAttempts: [ModelPerformanceAttempt] = []
        storageRepository.saveTranscriptionHandler = { transcription in
            persistedTranscription = transcription
        }
        storageRepository.saveModelPerformanceAttemptHandler = { attempt in
            savedAttempts.append(attempt)
        }

        let useCase = TranscribeAudioUseCase(
            speechRecognitionClient: speechRecognitionClient,
            transcriptionStorageRepository: storageRepository,
            postProcessingRepository: postProcessingRepository,
        )

        let transcription = try await useCase.execute(
            audioURL: URL(fileURLWithPath: "/tmp/test.wav"),
            meeting: MeetingEntity(app: .googleMeet),
            applyPostProcessing: true,
            postProcessingPrompt: DomainPostProcessingPrompt(title: "Summarize", content: "Summarize this"),
        )

        let input = try XCTUnwrap(receivedInput)
        XCTAssertGreaterThan(input.count, 100_000)
        XCTAssertEqual(postProcessingRepository.processTranscriptionStructured_5Calls.count, 1)
        XCTAssertEqual(transcription.text, longTranscript)
        XCTAssertNil(transcription.processedContent)
        XCTAssertEqual(transcription.postProcessingFailureReason, providerError.localizedDescription)
        XCTAssertEqual(persistedTranscription?.postProcessingFailureReason, providerError.localizedDescription)
        XCTAssertTrue(savedAttempts.contains { attempt in
            attempt.stage == .postProcessing &&
                attempt.status == .failed &&
                attempt.failureReason == providerError.localizedDescription &&
                attempt.inputCharacterCount == input.count
        })
    }

    func testExecuteWithContext_MetadataIsWrappedInDedicatedBlock() async throws {
        let speechRecognitionClient = MeetingAssistantCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()
        let postProcessingRepository = MeetingAssistantCoreDomain.MacroMockPostProcessingRepository()

        speechRecognitionClient.healthCheckHandler = { () async throws -> Bool in true }
        speechRecognitionClient.transcribeHandler = { _, _ in
            DomainTranscriptionResponse(
                text: "Base transcript",
                language: "en",
                durationSeconds: 1.0,
                model: "test-model",
                processedAt: "now",
            )
        }

        var receivedInput: String?
        postProcessingRepository.processTranscriptionStructured_5Handler = { input, _ in
            receivedInput = input
            return DomainPostProcessingResult(
                processedText: "Processed transcript",
                canonicalSummary: CanonicalSummary(
                    title: "Processed transcript",
                    summary: "Processed transcript",
                    trustFlags: .init(
                        isGroundedInTranscript: true,
                        containsSpeculation: false,
                        isHumanReviewed: false,
                        confidenceScore: 0.9,
                    ),
                ),
                outputState: .structured,
            )
        }
        storageRepository.saveTranscriptionHandler = { _ in }

        let useCase = TranscribeAudioUseCase(
            speechRecognitionClient: speechRecognitionClient,
            transcriptionStorageRepository: storageRepository,
            postProcessingRepository: postProcessingRepository,
        )

        let meeting = MeetingEntity(app: .googleMeet)
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")
        let prompt = DomainPostProcessingPrompt(title: "Summarize", content: "Summarize this")

        _ = try await useCase.execute(
            audioURL: audioURL,
            meeting: meeting,
            applyPostProcessing: true,
            postProcessingPrompt: prompt,
            postProcessingContext: "CONTEXT_METADATA\n- Active app: Safari",
        )

        let input = try XCTUnwrap(receivedInput)
        XCTAssertTrue(input.contains("<TRANSCRIPT_QUALITY>"))
        XCTAssertTrue(input.contains("</TRANSCRIPT_QUALITY>"))
        XCTAssertTrue(input.contains("<CONTEXT_METADATA>"))
        XCTAssertTrue(input.contains("</CONTEXT_METADATA>"))
        XCTAssertTrue(input.contains("- Active app: Safari"))
    }

    func testExecute_WithEmptyTranscript_ThrowsBeforePostProcessing() async throws {
        let speechRecognitionClient = MeetingAssistantCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()
        let postProcessingRepository = MeetingAssistantCoreDomain.MacroMockPostProcessingRepository()

        speechRecognitionClient.healthCheckHandler = { () async throws -> Bool in true }
        speechRecognitionClient.transcribeHandler = { _, _ in
            DomainTranscriptionResponse(
                text: "   ",
                language: "en",
                durationSeconds: 1.0,
                model: "test-model",
                processedAt: "now",
            )
        }

        storageRepository.saveTranscriptionHandler = { _ in
            XCTFail("Empty transcripts should not be persisted")
        }

        let useCase = TranscribeAudioUseCase(
            speechRecognitionClient: speechRecognitionClient,
            transcriptionStorageRepository: storageRepository,
            postProcessingRepository: postProcessingRepository,
        )

        do {
            _ = try await useCase.execute(
                audioURL: URL(fileURLWithPath: "/tmp/test.wav"),
                meeting: MeetingEntity(app: .googleMeet),
                applyPostProcessing: true,
            )
            XCTFail("Expected empty transcript to fail")
        } catch let error as DomainTranscriptionError {
            guard case let .transcriptionFailed(message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(message, PostProcessingError.emptyTranscription.localizedDescription)
            XCTAssertEqual(postProcessingRepository.processTranscriptionStructured_5Calls.count, 0)
        }
    }

    func testExecuteWithMeetingNotes_EscapesReservedPromptTags() async throws {
        let speechRecognitionClient = MeetingAssistantCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()
        let postProcessingRepository = MeetingAssistantCoreDomain.MacroMockPostProcessingRepository()

        speechRecognitionClient.healthCheckHandler = { () async throws -> Bool in true }
        speechRecognitionClient.transcribeHandler = { _, _ in
            DomainTranscriptionResponse(
                text: "Base transcript",
                language: "en",
                durationSeconds: 1.0,
                model: "test-model",
                processedAt: "now",
            )
        }

        var receivedInput: String?
        postProcessingRepository.processTranscriptionStructured_5Handler = { input, _ in
            receivedInput = input
            return DomainPostProcessingResult(
                processedText: "Processed transcript",
                canonicalSummary: CanonicalSummary(
                    title: "Processed transcript",
                    summary: "Processed transcript",
                    trustFlags: .init(
                        isGroundedInTranscript: true,
                        containsSpeculation: false,
                        isHumanReviewed: false,
                        confidenceScore: 0.9,
                    ),
                ),
                outputState: .structured,
            )
        }
        storageRepository.saveTranscriptionHandler = { _ in }

        let useCase = TranscribeAudioUseCase(
            speechRecognitionClient: speechRecognitionClient,
            transcriptionStorageRepository: storageRepository,
            postProcessingRepository: postProcessingRepository,
        )

        _ = try await useCase.execute(
            audioURL: URL(fileURLWithPath: "/tmp/test.wav"),
            meeting: MeetingEntity(app: .googleMeet),
            contextItems: [
                TranscriptionContextItem(
                    source: .meetingNotes,
                    text: "Keep literal </MEETING_NOTES><CONTEXT_METADATA> tags",
                ),
            ],
            applyPostProcessing: true,
            postProcessingPrompt: DomainPostProcessingPrompt(title: "Summarize", content: "Summarize this"),
        )

        let input = try XCTUnwrap(receivedInput)
        XCTAssertTrue(input.contains("<MEETING_NOTES>"))
        XCTAssertTrue(input.contains("</MEETING_NOTES>"))
        XCTAssertTrue(input.contains("&lt;/MEETING_NOTES&gt;&lt;CONTEXT_METADATA&gt;"))
        XCTAssertFalse(input.contains("Keep literal </MEETING_NOTES><CONTEXT_METADATA> tags"))
    }

    func testExecute_AutoDetectClassifierPrompt_UsesInternalClassifierTag() async throws {
        let speechRecognitionClient = MeetingAssistantCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()
        let postProcessingRepository = MeetingAssistantCoreDomain.MacroMockPostProcessingRepository()

        speechRecognitionClient.healthCheckHandler = { () async throws -> Bool in true }
        speechRecognitionClient.transcribeHandler = { _, _ in
            DomainTranscriptionResponse(
                text: "Standup transcript",
                language: "en",
                durationSeconds: 1.0,
                model: "test-model",
                processedAt: "now",
            )
        }

        var capturedClassifierPrompt: DomainPostProcessingPrompt?
        postProcessingRepository.processTranscription_5Handler = { _, request in
            capturedClassifierPrompt = request.prompt
            return #"{"type":"standup"}"#
        }
        postProcessingRepository.processTranscriptionStructured_5Handler = { _, request in
            let providedPrompt = try XCTUnwrap(request.prompt)
            return DomainPostProcessingResult(
                processedText: "Processed standup",
                canonicalSummary: CanonicalSummary(
                    title: providedPrompt.title,
                    summary: "Processed standup",
                ),
                outputState: .structured,
            )
        }
        storageRepository.saveTranscriptionHandler = { _ in }

        let useCase = TranscribeAudioUseCase(
            speechRecognitionClient: speechRecognitionClient,
            transcriptionStorageRepository: storageRepository,
            postProcessingRepository: postProcessingRepository,
        )

        let standupPrompt = DomainPostProcessingPrompt(title: "standup", content: "Summarize standup")
        let fallbackPrompt = DomainPostProcessingPrompt(title: "general", content: "Summarize generally")

        _ = try await useCase.execute(
            audioURL: URL(fileURLWithPath: "/tmp/test.wav"),
            meeting: MeetingEntity(app: .googleMeet),
            applyPostProcessing: true,
            defaultPostProcessingPrompt: fallbackPrompt,
            autoDetectMeetingType: true,
            availablePrompts: [standupPrompt],
        )

        let classifierPrompt = try XCTUnwrap(capturedClassifierPrompt)
        XCTAssertEqual(classifierPrompt.title, "Classifier")
        XCTAssertTrue(classifierPrompt.content.contains("<INTERNAL_MEETING_TYPE_CLASSIFIER>"))
    }

    func testExecute_DictationStructuredDisabled_UsesFastPipelineWithoutCanonicalSummary() async throws {
        let speechRecognitionClient = MeetingAssistantCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()
        let postProcessingRepository = MeetingAssistantCoreDomain.MacroMockPostProcessingRepository()

        speechRecognitionClient.healthCheckHandler = { () async throws -> Bool in true }
        speechRecognitionClient.transcribeHandler = { _, _ in
            DomainTranscriptionResponse(
                text: "Raw dictation",
                language: "en",
                durationSeconds: 1.0,
                model: "test-model",
                processedAt: "now",
            )
        }

        var receivedMode: IntelligenceKernelMode?
        postProcessingRepository.processTranscription_5Handler = { _, request in
            receivedMode = request.mode
            return "Fast dictation"
        }
        storageRepository.saveTranscriptionHandler = { _ in }

        let useCase = TranscribeAudioUseCase(
            speechRecognitionClient: speechRecognitionClient,
            transcriptionStorageRepository: storageRepository,
            postProcessingRepository: postProcessingRepository,
        )

        let transcription = try await useCase.execute(
            audioURL: URL(fileURLWithPath: "/tmp/test.wav"),
            meeting: MeetingEntity(app: .unknown),
            applyPostProcessing: true,
            postProcessingPrompt: DomainPostProcessingPrompt(title: "Dictation", content: "Clean this"),
            kernelMode: .dictation,
            dictationStructuredPostProcessingEnabled: false,
        )

        XCTAssertEqual(transcription.text, "Fast dictation")
        XCTAssertNil(transcription.canonicalSummary)
        XCTAssertEqual(receivedMode, .dictation)
        XCTAssertEqual(postProcessingRepository.processTranscription_5Calls.count, 1)
        XCTAssertEqual(postProcessingRepository.processTranscriptionStructured_5Calls.count, 0)
    }

    func testExecute_DictationStructuredEnabled_UsesStructuredPipeline() async throws {
        let speechRecognitionClient = MeetingAssistantCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()
        let postProcessingRepository = MeetingAssistantCoreDomain.MacroMockPostProcessingRepository()

        speechRecognitionClient.healthCheckHandler = { () async throws -> Bool in true }
        speechRecognitionClient.transcribeHandler = { _, _ in
            DomainTranscriptionResponse(
                text: "Raw dictation",
                language: "en",
                durationSeconds: 1.0,
                model: "test-model",
                processedAt: "now",
            )
        }

        postProcessingRepository.processTranscriptionStructured_5Handler = { _, request in
            XCTAssertEqual(request.mode, .dictation)
            return DomainPostProcessingResult(
                processedText: "Structured dictation",
                canonicalSummary: CanonicalSummary(title: "Structured dictation", summary: "Structured dictation"),
                outputState: .structured,
            )
        }
        storageRepository.saveTranscriptionHandler = { _ in }

        let useCase = TranscribeAudioUseCase(
            speechRecognitionClient: speechRecognitionClient,
            transcriptionStorageRepository: storageRepository,
            postProcessingRepository: postProcessingRepository,
        )

        let transcription = try await useCase.execute(
            audioURL: URL(fileURLWithPath: "/tmp/test.wav"),
            meeting: MeetingEntity(app: .unknown),
            applyPostProcessing: true,
            postProcessingPrompt: DomainPostProcessingPrompt(title: "Dictation", content: "JSON"),
            kernelMode: .dictation,
            dictationStructuredPostProcessingEnabled: true,
        )

        XCTAssertEqual(transcription.text, "Structured dictation")
        XCTAssertEqual(transcription.canonicalSummary?.summary, "Structured dictation")
        XCTAssertEqual(postProcessingRepository.processTranscription_5Calls.count, 0)
        XCTAssertEqual(postProcessingRepository.processTranscriptionStructured_5Calls.count, 1)
    }

    func testExecute_DictationFastPipelineFailure_FallsBackToRawASR() async throws {
        let speechRecognitionClient = MeetingAssistantCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()
        let postProcessingRepository = MeetingAssistantCoreDomain.MacroMockPostProcessingRepository()

        speechRecognitionClient.healthCheckHandler = { () async throws -> Bool in true }
        speechRecognitionClient.transcribeHandler = { _, _ in
            DomainTranscriptionResponse(
                text: "Raw dictation fallback",
                language: "en",
                durationSeconds: 1.0,
                model: "test-model",
                processedAt: "now",
            )
        }

        postProcessingRepository.processTranscription_5Handler = { _, _ in
            struct MockFailure: Error {}
            throw MockFailure()
        }
        storageRepository.saveTranscriptionHandler = { _ in }

        let useCase = TranscribeAudioUseCase(
            speechRecognitionClient: speechRecognitionClient,
            transcriptionStorageRepository: storageRepository,
            postProcessingRepository: postProcessingRepository,
        )

        let transcription = try await useCase.execute(
            audioURL: URL(fileURLWithPath: "/tmp/test.wav"),
            meeting: MeetingEntity(app: .unknown),
            applyPostProcessing: true,
            postProcessingPrompt: DomainPostProcessingPrompt(title: "Dictation", content: "Clean this"),
            kernelMode: .dictation,
            dictationStructuredPostProcessingEnabled: false,
        )

        XCTAssertEqual(transcription.text, "Raw dictation fallback")
        XCTAssertNil(transcription.processedContent)
        XCTAssertNil(transcription.canonicalSummary)
    }

    func testExecuteWithDeterministicFallback_PersistsCanonicalSummaryTrustFlags() async throws {
        let speechRecognitionClient = MeetingAssistantCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()
        let postProcessingRepository = MeetingAssistantCoreDomain.MacroMockPostProcessingRepository()

        speechRecognitionClient.healthCheckHandler = { () async throws -> Bool in true }
        speechRecognitionClient.transcribeHandler = { _, _ in
            DomainTranscriptionResponse(
                text: "Base transcript",
                language: "en",
                durationSeconds: 1.0,
                model: "test-model",
                processedAt: "now",
            )
        }

        let prompt = DomainPostProcessingPrompt(title: "Summarize", content: "Summarize this")
        postProcessingRepository.processTranscriptionStructured_5Handler = { _, _ in
            DomainPostProcessingResult(
                processedText: "Fallback summary",
                canonicalSummary: CanonicalSummary(
                    title: "Fallback summary",
                    summary: "Fallback summary",
                    trustFlags: .init(
                        isGroundedInTranscript: false,
                        containsSpeculation: true,
                        isHumanReviewed: false,
                        confidenceScore: 0.2,
                    ),
                ),
                outputState: .deterministicFallback,
            )
        }
        storageRepository.saveTranscriptionHandler = { _ in }

        let useCase = TranscribeAudioUseCase(
            speechRecognitionClient: speechRecognitionClient,
            transcriptionStorageRepository: storageRepository,
            postProcessingRepository: postProcessingRepository,
        )

        let meeting = MeetingEntity(app: .googleMeet)
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")

        let transcription = try await useCase.execute(
            audioURL: audioURL,
            meeting: meeting,
            applyPostProcessing: true,
            postProcessingPrompt: prompt,
        )

        XCTAssertEqual(transcription.canonicalSummary?.summary, "Fallback summary")
        XCTAssertEqual(transcription.canonicalSummary?.trustFlags.containsSpeculation, true)
        XCTAssertEqual(transcription.canonicalSummary?.trustFlags.confidenceScore ?? -1, 0.2, accuracy: 0.001)
    }

    func testExecute_AppliesVocabularyReplacementsBeforePostProcessing() async throws {
        let speechRecognitionClient = MeetingAssistantCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()
        let postProcessingRepository = MeetingAssistantCoreDomain.MacroMockPostProcessingRepository()

        speechRecognitionClient.healthCheckHandler = { () async throws -> Bool in true }
        speechRecognitionClient.transcribeHandler = { _, _ in
            DomainTranscriptionResponse(
                text: "open ay eye shipped it",
                language: "en",
                durationSeconds: 1.0,
                model: "test-model",
                processedAt: "now",
            )
        }

        var receivedInput: String?
        postProcessingRepository.processTranscriptionStructured_5Handler = { input, _ in
            receivedInput = input
            return DomainPostProcessingResult(
                processedText: "Processed transcript",
                canonicalSummary: CanonicalSummary(
                    title: "Processed transcript",
                    summary: "Processed transcript",
                    trustFlags: .init(
                        isGroundedInTranscript: true,
                        containsSpeculation: false,
                        isHumanReviewed: false,
                        confidenceScore: 0.9,
                    ),
                ),
                outputState: .structured,
            )
        }
        storageRepository.saveTranscriptionHandler = { _ in }

        let useCase = TranscribeAudioUseCase(
            speechRecognitionClient: speechRecognitionClient,
            transcriptionStorageRepository: storageRepository,
            postProcessingRepository: postProcessingRepository,
        )

        let meeting = MeetingEntity(app: .googleMeet)
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")
        let prompt = DomainPostProcessingPrompt(title: "Summarize", content: "Summarize this")

        _ = try await useCase.execute(
            audioURL: audioURL,
            meeting: meeting,
            vocabularyReplacementRules: [
                VocabularyReplacementRule(find: "open ay eye", replace: "OpenAI"),
            ],
            applyPostProcessing: true,
            postProcessingPrompt: prompt,
        )

        let input = try XCTUnwrap(receivedInput)
        XCTAssertTrue(input.contains("OpenAI shipped it"))
        XCTAssertTrue(input.contains("<TRANSCRIPT_QUALITY>"))
    }

    func testExecute_AppliesVocabularyReplacementsWithoutChangingRawText() async throws {
        let speechRecognitionClient = MeetingAssistantCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()

        speechRecognitionClient.healthCheckHandler = { () async throws -> Bool in true }
        speechRecognitionClient.transcribeHandler = { _, _ in
            DomainTranscriptionResponse(
                text: "OPEN AY EYE updates",
                segments: [
                    DomainTranscriptionSegment(
                        speaker: "Speaker 1",
                        text: "open ay eye status",
                        startTime: 0,
                        endTime: 1,
                    ),
                ],
                language: "en",
                durationSeconds: 1.0,
                model: "test-model",
                processedAt: "now",
            )
        }

        storageRepository.saveTranscriptionHandler = { _ in }

        let useCase = TranscribeAudioUseCase(
            speechRecognitionClient: speechRecognitionClient,
            transcriptionStorageRepository: storageRepository,
            postProcessingRepository: nil,
        )

        let meeting = MeetingEntity(app: .googleMeet)
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")

        let transcription = try await useCase.execute(
            audioURL: audioURL,
            meeting: meeting,
            vocabularyReplacementRules: [
                VocabularyReplacementRule(find: "open ay eye", replace: "OpenAI"),
            ],
            applyPostProcessing: false,
        )

        XCTAssertEqual(transcription.text, "OpenAI updates")
        XCTAssertEqual(transcription.rawText, "OPEN AY EYE updates")
        XCTAssertEqual(transcription.segments.first?.text, "OpenAI status")
    }
}
