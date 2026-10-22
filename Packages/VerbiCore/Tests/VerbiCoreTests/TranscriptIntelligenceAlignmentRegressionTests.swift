import Foundation
@testable import VerbiCore
@testable import VerbiCoreDomain
import XCTest

@MainActor
final class TranscriptAlignmentRegressionTests: XCTestCase {
    func testASRConfidencePropagatesToEntityQualityProfile() async throws {
        let speechRecognitionClient = VerbiCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()

        speechRecognitionClient.healthCheckHandler = { () async throws -> Bool in true }
        speechRecognitionClient.transcribeHandler = { _, _ in
            DomainTranscriptionResponse(
                text: "Team agreed on shipping Friday.",
                language: "en",
                durationSeconds: 1,
                model: "test-model",
                processedAt: "now",
                confidenceScore: 0.91,
            )
        }

        storageRepository.saveTranscriptionHandler = { _ in }

        let useCase = TranscribeAudioUseCase(
            speechRecognitionClient: speechRecognitionClient,
            transcriptionStorageRepository: storageRepository,
        )

        let transcription = try await useCase.execute(
            audioURL: URL(fileURLWithPath: "/tmp/test.wav"),
            meeting: CaptureSessionEntity(app: .googleMeet),
        )

        XCTAssertEqual(transcription.qualityProfile?.overallConfidence ?? -1, 0.91, accuracy: 0.001)
        XCTAssertEqual(transcription.qualityProfile?.containsUncertainty, false)
    }

    func testNormalizationIsIdempotent() {
        let preprocessor = TranscriptIntelligencePreprocessor()
        let original = " Hello\t\tteam \r\n\r\n this   is a test.  "

        let first = preprocessor.preprocess(
            transcriptionText: original,
            segments: [],
            asrConfidenceScore: 0.9,
        )
        let second = preprocessor.preprocess(
            transcriptionText: first.normalizedTextForIntelligence,
            segments: [],
            asrConfidenceScore: 0.9,
        )

        XCTAssertEqual(first.normalizedTextForIntelligence, second.normalizedTextForIntelligence)
    }

    func testNormalizationPreservesVerbatimFidelity() {
        let preprocessor = TranscriptIntelligencePreprocessor()
        let original = "OpenAI shipped it yesterday, and the design review moved to Monday."

        let profile = preprocessor.preprocess(
            transcriptionText: original,
            segments: [],
            asrConfidenceScore: 0.88,
        )

        let overlap = tokenOverlap(lhs: original, rhs: profile.normalizedTextForIntelligence)
        XCTAssertGreaterThanOrEqual(overlap, 0.97)
    }

    func testUncertaintyMarkersGeneratedForLowConfidenceAndLexicalSignals() {
        let preprocessor = TranscriptIntelligencePreprocessor()
        let segments = [
            DomainTranscriptionSegment(
                speaker: "A",
                text: "We should [inaudible] proceed ???",
                startTime: 2,
                endTime: 5,
            ),
        ]

        let profile = preprocessor.preprocess(
            transcriptionText: "We should [inaudible] proceed ???",
            segments: segments,
            asrConfidenceScore: 0.60,
        )

        let reasons = Set(profile.markers.map(\.reason))
        XCTAssertTrue(profile.containsUncertainty)
        XCTAssertTrue(reasons.contains(.veryLowASRConfidence))
        XCTAssertTrue(reasons.contains(.lexicalUncertainty))
    }

    func testPostProcessingInputContainsQualityBlockAndCorrectOrder() async throws {
        let speechRecognitionClient = VerbiCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()
        let postProcessingRepository = VerbiCoreDomain.MacroMockPostProcessingRepository()

        speechRecognitionClient.healthCheckHandler = { () async throws -> Bool in true }
        speechRecognitionClient.transcribeHandler = { _, _ in
            DomainTranscriptionResponse(
                text: "open ay eye shipped it",
                language: "en",
                durationSeconds: 1,
                model: "test-model",
                processedAt: "now",
                confidenceScore: 0.89,
            )
        }

        var capturedInput: String?
        postProcessingRepository.processTranscriptionStructured_5Handler = { input, _ in
            capturedInput = input
            return DomainPostProcessingResult(
                processedText: "ok",
                canonicalSummary: CanonicalSummary(title: "ok", summary: "ok"),
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
            meeting: CaptureSessionEntity(app: .googleMeet),
            vocabularyReplacementRules: [.init(find: "open ay eye", replace: "OpenAI")],
            applyPostProcessing: true,
            postProcessingPrompt: .init(title: "Prompt", content: "Prompt"),
            postProcessingContext: "Active app: Safari",
        )

        let input = try XCTUnwrap(capturedInput)
        let transcriptIndex = input.range(of: "OpenAI shipped it")?.lowerBound
        let qualityIndex = input.range(of: "<TRANSCRIPT_QUALITY>")?.lowerBound
        let contextIndex = input.range(of: "<CONTEXT_METADATA>")?.lowerBound

        XCTAssertNotNil(transcriptIndex)
        XCTAssertNotNil(qualityIndex)
        XCTAssertNotNil(contextIndex)
        XCTAssertLessThan(try XCTUnwrap(transcriptIndex), try XCTUnwrap(qualityIndex))
        XCTAssertLessThan(try XCTUnwrap(qualityIndex), try XCTUnwrap(contextIndex))
    }

    func testSummaryTrustFlagsAreRecalibratedByTranscriptQuality() async throws {
        let speechRecognitionClient = VerbiCoreDomain.MacroMockSpeechRecognitionClient()
        let storageRepository = makeMacroMockTranscriptionStorageRepository()
        let postProcessingRepository = VerbiCoreDomain.MacroMockPostProcessingRepository()

        speechRecognitionClient.healthCheckHandler = { () async throws -> Bool in true }
        speechRecognitionClient.transcribeHandler = { _, _ in
            DomainTranscriptionResponse(
                text: "unclear decision ???",
                language: "en",
                durationSeconds: 1,
                model: "test-model",
                processedAt: "now",
                confidenceScore: 0.55,
            )
        }
        postProcessingRepository.processTranscriptionStructured_5Handler = { _, _ in
            DomainPostProcessingResult(
                processedText: "summary",
                canonicalSummary: CanonicalSummary(
                    title: "summary",
                    summary: "summary",
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

        let transcription = try await useCase.execute(
            audioURL: URL(fileURLWithPath: "/tmp/test.wav"),
            meeting: CaptureSessionEntity(app: .googleMeet),
            applyPostProcessing: true,
            postProcessingPrompt: .init(title: "Prompt", content: "Prompt"),
        )

        XCTAssertEqual(
            transcription.canonicalSummary?.trustFlags.confidenceScore ?? -1,
            transcription.qualityProfile?.overallConfidence ?? -2,
            accuracy: 0.001,
        )
        XCTAssertEqual(transcription.canonicalSummary?.trustFlags.containsSpeculation, true)
    }

    func testQualityProfileRoundTripInCoreData() async throws {
        let stack = CoreDataStack(name: "TranscriptQualityRoundTrip", inMemory: true)
        let meetingRepo = CoreDataMeetingRepository(stack: stack)
        let transcriptionRepo = CoreDataTranscriptionStorageRepository(stack: stack)

        let meeting = CaptureSessionEntity(app: .googleMeet)
        try await meetingRepo.saveMeeting(meeting)

        let qualityProfile = TranscriptionQualityProfile(
            normalizedTextForIntelligence: "Normalized transcript",
            overallConfidence: 0.77,
            containsUncertainty: true,
            markers: [
                .init(
                    snippet: "[inaudible]",
                    startTime: 2,
                    endTime: 4,
                    reason: .lexicalUncertainty,
                ),
            ],
        )

        var config = CaptureArtifactEntity.Configuration(
            text: "Display transcript",
            rawText: "Raw transcript",
        )
        config.qualityProfile = qualityProfile
        let transcription = CaptureArtifactEntity(meeting: meeting, config: config)

        try await transcriptionRepo.saveTranscription(transcription)
        let fetched = try await transcriptionRepo.fetchTranscription(by: transcription.id)

        XCTAssertEqual(fetched?.qualityProfile?.normalizedTextForIntelligence, "Normalized transcript")
        XCTAssertEqual(fetched?.qualityProfile?.overallConfidence ?? -1, 0.77, accuracy: 0.001)
        XCTAssertEqual(fetched?.qualityProfile?.containsUncertainty, true)
        XCTAssertEqual(fetched?.qualityProfile?.markers.count, 1)
    }

    func testMetadataReflectsTranscriptQualitySignals() async throws {
        let stack = CoreDataStack(name: "TranscriptQualityMetadata", inMemory: true)
        let meetingRepo = CoreDataMeetingRepository(stack: stack)
        let transcriptionRepo = CoreDataTranscriptionStorageRepository(stack: stack)

        let meeting = CaptureSessionEntity(app: .googleMeet)
        try await meetingRepo.saveMeeting(meeting)

        var config = CaptureArtifactEntity.Configuration(text: "T", rawText: "T")
        config.qualityProfile = TranscriptionQualityProfile(
            normalizedTextForIntelligence: "T",
            overallConfidence: 0.64,
            containsUncertainty: true,
            markers: [.init(snippet: "???", reason: .lexicalUncertainty)],
        )
        let transcription = CaptureArtifactEntity(meeting: meeting, config: config)
        try await transcriptionRepo.saveTranscription(transcription)

        let metadata = try await transcriptionRepo.fetchAllMetadata()
        XCTAssertEqual(metadata.count, 1)
        XCTAssertEqual(metadata.first?.transcriptConfidenceScore ?? -1, 0.64, accuracy: 0.001)
        XCTAssertEqual(metadata.first?.transcriptContainsUncertainty, true)
    }

    func testRetryPathPersistsQualityProfileAndRecalibratedSummaryWhenAvailable() async throws {
        let mic = MockAudioRecorder()
        let system = MockAudioRecorder()
        let transcriptionClient = MockTranscriptionClient()
        let postProcessing = MockPostProcessingService()
        let storage = MockStorageService()

        transcriptionClient.mockText = "unclear decision ???"
        transcriptionClient.mockConfidenceScore = 0.58
        transcriptionClient.mockSegments = [
            .init(speaker: "Speaker 1", text: "unclear decision ???", startTime: 0, endTime: 3),
        ]

        let manager = RecordingManager(
            micRecorder: mic,
            systemRecorder: system,
            transcriptionClient: transcriptionClient,
            postProcessingService: postProcessing,
            storage: storage,
        )

        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("retry-transcription-quality-\(UUID().uuidString).wav")
        FileManager.default.createFile(atPath: audioURL.path, contents: Data([0x00]))
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let meeting = CaptureSession(
            app: .googleMeet,
            startTime: Date(),
            endTime: Date().addingTimeInterval(10),
            audioFilePath: audioURL.path,
        )
        let transcription = CaptureArtifact(
            meeting: meeting,
            text: "old text",
            rawText: "old raw",
            language: "en",
            modelName: "old-model",
        )

        await manager.retryTranscription(for: transcription)

        let saved = try XCTUnwrap(storage.savedTranscriptions.last)
        let qualityProfile = try XCTUnwrap(saved.qualityProfile)
        XCTAssertEqual(qualityProfile.containsUncertainty, true)
        XCTAssertEqual(saved.rawText, "unclear decision ???")

        if let canonicalSummary = saved.canonicalSummary {
            XCTAssertLessThanOrEqual(canonicalSummary.trustFlags.confidenceScore, qualityProfile.overallConfidence)
        }
    }

    private func tokenOverlap(lhs: String, rhs: String) -> Double {
        let leftTokens = normalizedTokens(from: lhs)
        let rightTokens = normalizedTokens(from: rhs)
        guard !leftTokens.isEmpty else { return 1.0 }

        var rightCounts: [String: Int] = [:]
        for token in rightTokens {
            rightCounts[token, default: 0] += 1
        }

        var matched = 0
        for token in leftTokens {
            let count = rightCounts[token, default: 0]
            if count > 0 {
                matched += 1
                rightCounts[token] = count - 1
            }
        }

        return Double(matched) / Double(leftTokens.count)
    }

    private func normalizedTokens(from text: String) -> [String] {
        text
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }
}
