import Foundation
@testable import VerbiCore
@testable import VerbiCoreDomain
import XCTest

private final class UseCaseCallbackRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var phasesStorage: [TranscriptionPhase] = []
    private var progressStorage: [Double] = []

    func record(phase: TranscriptionPhase) {
        lock.lock()
        phasesStorage.append(phase)
        lock.unlock()
    }

    func record(progress: Double) {
        lock.lock()
        progressStorage.append(progress)
        lock.unlock()
    }

    func snapshot() -> (phases: [TranscriptionPhase], progress: [Double]) {
        lock.lock()
        defer { lock.unlock() }
        return (phasesStorage, progressStorage)
    }
}

final class TranscribeAudioUseCaseMacroMockingTests: XCTestCase {
    func testExecuteSuccess_SavesTranscription() async throws {
        let speechRecognitionClient = VerbiCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()

        speechRecognitionClient.healthCheckHandler = { () async throws -> Bool in true }

        let response = DomainTranscriptionResponse(
            text: "Hello world",
            language: "en",
            durationSeconds: 1.0,
            model: "test-model",
            processedAt: "now",
        )

        speechRecognitionClient.transcribeHandler = { _, _ in response }

        var saved: [CaptureArtifactEntity] = []
        storageRepository.saveTranscriptionHandler = { transcription in
            saved.append(transcription)
        }

        let useCase = TranscribeAudioUseCase(
            speechRecognitionClient: speechRecognitionClient,
            transcriptionStorageRepository: storageRepository,
            postProcessingRepository: nil,
        )

        let meeting = CaptureSessionEntity(app: .googleMeet)
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")

        let transcription = try await useCase.execute(audioURL: audioURL, meeting: meeting)

        XCTAssertEqual(transcription.text, "Hello world")
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(speechRecognitionClient.healthCheckCallCount, 0)
        XCTAssertEqual(speechRecognitionClient.transcribeCalls.count, 1)
    }

    func testFinalizePreparedResponse_PersistsExecutionProvenance() async throws {
        let speechRecognitionClient = VerbiCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()
        var savedAttempts: [ModelPerformanceAttempt] = []
        storageRepository.saveTranscriptionHandler = { _ in }
        storageRepository.saveModelPerformanceAttemptHandler = { attempt in
            savedAttempts.append(attempt)
        }

        let useCase = TranscribeAudioUseCase(
            speechRecognitionClient: speechRecognitionClient,
            transcriptionStorageRepository: storageRepository,
            postProcessingRepository: nil,
        )
        let transcriptionIdentity = ModelPerformanceModelIdentity(
            providerID: "local",
            providerDisplayName: "Local",
            modelID: "model-a",
            modelDisplayName: "Model A",
            runtimeKind: .local,
        )
        let requestConfiguration = DomainTranscriptionRequestConfiguration(
            providerID: "local",
            modelID: "model-a",
            inputLanguageCode: "pt",
        )
        let vocabularyTerms = [VocabularyTerm(term: "Prisma", definition: "App name")]
        let replacementRules = [VocabularyReplacementRule(find: "prizma", replace: "Prisma")]

        let transcription = try await useCase.finalizePreparedResponse(
            response: DomainTranscriptionResponse(
                text: "Hello world",
                language: "en",
                durationSeconds: 1,
                model: "model-a",
                processedAt: "now",
            ),
            transcriptionID: UUID(),
            meeting: CaptureSessionEntity(app: .unknown, capturePurpose: .dictation),
            transcriptionIdentity: transcriptionIdentity,
            vocabularyReplacementRules: replacementRules,
            vocabularyTerms: vocabularyTerms,
            transcriptionConfiguration: requestConfiguration,
            transcriptionDuration: 1,
        )

        XCTAssertEqual(transcription.executionProvenance?.transcriptionRequest?.providerID, "local")
        XCTAssertEqual(transcription.executionProvenance?.transcriptionRequest?.modelID, "model-a")
        XCTAssertEqual(
            transcription.executionProvenance?.vocabularySnapshot,
            VocabularySnapshot(terms: vocabularyTerms, replacementRules: replacementRules),
        )
        XCTAssertEqual(transcription.executionProvenance?.transcriptionModelIdentity, transcriptionIdentity)
        XCTAssertEqual(savedAttempts.count, 1)
        XCTAssertEqual(savedAttempts.first?.executionProvenance, transcription.executionProvenance)
    }

    func testExecuteSuccess_PersistsModelPerformanceAttempts() async throws {
        let speechRecognitionClient = VerbiCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()
        let postProcessingRepository = VerbiCoreDomain.MacroMockPostProcessingRepository()

        speechRecognitionClient.transcribeHandler = { _, _ in
            DomainTranscriptionResponse(
                text: "Hello world",
                language: "en",
                durationSeconds: 30,
                model: "test-model",
                processedAt: "now",
            )
        }
        postProcessingRepository.processTranscriptionStructured_5Handler = { _, _ in
            DomainPostProcessingResult(
                processedText: "Processed",
                canonicalSummary: CanonicalSummary(title: "Processed", summary: "Processed"),
                outputState: .structured,
            )
        }

        var savedAttempts: [ModelPerformanceAttempt] = []
        storageRepository.saveTranscriptionHandler = { _ in }
        storageRepository.saveModelPerformanceAttemptHandler = { attempt in
            savedAttempts.append(attempt)
        }

        let useCase = TranscribeAudioUseCase(
            speechRecognitionClient: speechRecognitionClient,
            transcriptionStorageRepository: storageRepository,
            postProcessingRepository: postProcessingRepository,
        )

        _ = try await useCase.execute(
            audioURL: URL(fileURLWithPath: "/tmp/test.wav"),
            meeting: CaptureSessionEntity(app: .unknown, capturePurpose: .dictation),
            transcriptionIdentity: ModelPerformanceModelIdentity(
                providerID: "local",
                providerDisplayName: "Local",
                modelID: "test-model",
                modelDisplayName: "Test Model",
                runtimeKind: .local,
            ),
            applyPostProcessing: true,
            postProcessingPrompt: DomainPostProcessingPrompt(title: "Prompt", content: "Prompt"),
            postProcessingIdentity: ModelPerformanceModelIdentity(
                providerID: "openai",
                providerDisplayName: "OpenAI",
                modelID: "gpt-4.1-mini",
                modelDisplayName: "GPT-4.1 Mini",
                runtimeKind: .remote,
            ),
            kernelMode: .dictation,
            dictationStructuredPostProcessingEnabled: true,
        )

        XCTAssertEqual(savedAttempts.count, 2)
        XCTAssertEqual(savedAttempts.map(\.stage), [.transcription, .postProcessing])
        XCTAssertEqual(savedAttempts.map(\.status), [.succeeded, .succeeded])
    }

    func testExecute_EmitsPhaseAndProgressCallbacks() async throws {
        let speechRecognitionClient = VerbiCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()
        let postProcessingRepository = VerbiCoreDomain.MacroMockPostProcessingRepository()

        speechRecognitionClient.healthCheckHandler = { () async throws -> Bool in true }
        speechRecognitionClient.transcribeHandler = { _, onProgress in
            onProgress?(20)
            onProgress?(55)
            onProgress?(100)
            return DomainTranscriptionResponse(
                text: "Hello world",
                language: "en",
                durationSeconds: 1.0,
                model: "test-model",
                processedAt: "now",
            )
        }
        postProcessingRepository.processTranscriptionStructured_5Handler = { _, _ in
            DomainPostProcessingResult(
                processedText: "Processed",
                canonicalSummary: CanonicalSummary(title: "Processed", summary: "Processed"),
                outputState: .structured,
            )
        }
        storageRepository.saveTranscriptionHandler = { _ in }

        let useCase = TranscribeAudioUseCase(
            speechRecognitionClient: speechRecognitionClient,
            transcriptionStorageRepository: storageRepository,
            postProcessingRepository: postProcessingRepository,
        )

        let recorder = UseCaseCallbackRecorder()

        _ = try await useCase.execute(
            audioURL: URL(fileURLWithPath: "/tmp/test.wav"),
            meeting: CaptureSessionEntity(app: .googleMeet),
            applyPostProcessing: true,
            postProcessingPrompt: DomainPostProcessingPrompt(title: "Prompt", content: "Prompt"),
            onPhaseChange: { phase in
                recorder.record(phase: phase)
            },
            onTranscriptionProgress: { progress in
                recorder.record(progress: progress)
            },
        )

        let snapshot = recorder.snapshot()

        XCTAssertEqual(snapshot.phases, [.preparing, .processing, .postProcessing, .completed])
        XCTAssertEqual(snapshot.progress, [20, 55, 100])
    }
}
