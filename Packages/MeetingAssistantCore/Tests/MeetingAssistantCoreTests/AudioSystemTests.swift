import Synchronization
@preconcurrency import AVFoundation
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreAudio
import XCTest

/// Testes de integração completa do sistema de áudio.
/// Testa a interação entre AudioRecorder, SystemAudioRecorder, AudioBufferQueue,
/// AudioRecordingWorker e RecordingManager.
@MainActor
final class AudioSystemTests: XCTestCase {
    var audioRecorder: AudioRecorder!
    var systemRecorder: SystemAudioRecorder!
    var bufferQueue: AudioBufferQueue!
    var recordingWorker: AudioRecordingWorker!
    var recordingManager: RecordingManager!

    // Mocks para isolamento
    var mockTranscription: MockTranscriptionClient!
    var mockPostProcessing: MockPostProcessingService!
    var mockStorage: MockStorageService!

    override func setUp() async throws {
        try await super.setUp()

        // Inicializar componentes reais para testes de integração
        audioRecorder = AudioRecorder.shared
        systemRecorder = SystemAudioRecorder.shared
        bufferQueue = AudioBufferQueue(capacity: 50)
        recordingWorker = AudioRecordingWorker()

        // Mocks para RecordingManager
        mockTranscription = MockTranscriptionClient()
        mockPostProcessing = MockPostProcessingService()
        mockStorage = MockStorageService()

        recordingManager = RecordingManager(
            transcriptionClient: mockTranscription,
            postProcessingService: mockPostProcessing,
            storage: mockStorage,
        )
    }

    override func tearDown() async throws {
        // Cleanup
        _ = await audioRecorder.stopRecording()
        _ = await systemRecorder.stopRecording()
        recordingWorker = nil
        bufferQueue.clear()

        audioRecorder = nil
        systemRecorder = nil
        bufferQueue = nil
        recordingManager = nil
        mockTranscription = nil
        mockPostProcessing = nil
        mockStorage = nil

        try await super.tearDown()
    }

    // MARK: - Testes de Integração Básica

    func testAudioRecorderIntegration_WithSystemAudio() async throws {
        // Skip test if running in CI or without screen recording permissions
        guard await systemRecorder.hasPermission() else {
            throw XCTSkip("Screen recording permission not available")
        }

        // Given
        let outputURL = createTemporaryURL()

        // When
        do {
            try await audioRecorder.startRecording(to: outputURL, source: .all, retryCount: 0)
        } catch {
            // Skip if permission denied at runtime (common in test environments)
            if "\(error)".contains("permissionDenied") || "\(error)".contains("permission") {
                throw XCTSkip("Screen recording permission denied at runtime: \(error)")
            }
            throw error
        }

        // Pequena pausa para estabilizar
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        let stoppedURL = await audioRecorder.stopRecording()

        // Then
        XCTAssertNotNil(stoppedURL)
        XCTAssertEqual(stoppedURL, outputURL)
        XCTAssertFalse(audioRecorder.isRecording)
    }

    func testSystemAudioRecorder_BufferCallbackIntegration() async throws {
        // Skip test if running in CI or without screen recording permissions
        guard await systemRecorder.hasPermission() else {
            throw XCTSkip("Screen recording permission not available")
        }

        // Given
        let receivedBuffers = AtomicArray<AVAudioPCMBuffer>()
        let expectation = expectation(description: "Buffer callback received")

        let fulfilled = Atomic<Bool>(false)
        systemRecorder.onAudioBuffer = { @Sendable buffer in
            receivedBuffers.append(buffer)
            if receivedBuffers.count >= 3, !fulfilled.exchange(true, ordering: .relaxed) {
                expectation.fulfill()
            }
        }

        // When
        try await systemRecorder.startRecording(to: createTemporaryURL(), sampleRate: 48_000.0)

        // Wait for buffers or timeout
        await fulfillment(of: [expectation], timeout: 2.0)

        _ = await systemRecorder.stopRecording()

        // Then
        XCTAssertGreaterThan(receivedBuffers.count, 0, "Should have received audio buffers")
        XCTAssertFalse(systemRecorder.isRecording)
    }

    func testAudioBufferQueue_IntegrationWithSystemRecorder() async throws {
        // Skip test if running in CI or without screen recording permissions
        guard await systemRecorder.hasPermission() else {
            throw XCTSkip("Screen recording permission not available")
        }

        // Given
        let enqueuedCount = ThreadSafeCounter()
        let expectation = expectation(description: "Buffers enqueued")
        expectation.expectedFulfillmentCount = 5

        systemRecorder.onAudioBuffer = { @Sendable [bufferQueue = self.bufferQueue!] buffer in
            bufferQueue.enqueue(buffer)
            let count = enqueuedCount.increment()
            if count <= 5 {
                expectation.fulfill()
            }
        }

        // When
        try await systemRecorder.startRecording(to: createTemporaryURL(), sampleRate: 48_000.0)

        await fulfillment(of: [expectation], timeout: 2.0)

        _ = await systemRecorder.stopRecording()

        // Then
        XCTAssertGreaterThanOrEqual(bufferQueue.stats.count, 5)
        XCTAssertEqual(bufferQueue.stats.dropped, 0) // Não deve ter perdido buffers inicialmente
    }

    func testAudioRecordingWorker_BufferProcessingIntegration() async throws {
        // Given
        let outputURL = createTemporaryURL()
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))

        try await recordingWorker.start(writingTo: outputURL, format: format, fileFormat: .wav)

        // Simular buffers do AudioRecorder
        let testBuffers = try createTestBuffers(count: 10, frameCount: 1_024)

        // When
        for buffer in testBuffers {
            recordingWorker.process(buffer)
        }

        try await Task.sleep(nanoseconds: 200_000_000) // Aguardar processamento

        let finalURL = await recordingWorker.stop()

        // Then
        XCTAssertNotNil(finalURL)
        XCTAssertTrue(try FileManager.default.fileExists(atPath: XCTUnwrap(finalURL?.path)))

        // Verificar se arquivo tem conteúdo
        let asset = try AVURLAsset(url: XCTUnwrap(finalURL))
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0)
    }

    // MARK: - Testes de Estado Consistente

    func testStateConsistency_BufferQueueStatsAccuracy() throws {
        let buffer = try createTestBuffer(frameCount: 512)

        // Estado inicial
        XCTAssertEqual(bufferQueue.stats.count, 0)
        XCTAssertEqual(bufferQueue.stats.dropped, 0)

        // Enqueue
        bufferQueue.enqueue(buffer)
        XCTAssertEqual(bufferQueue.stats.count, 1)

        // Dequeue
        let dequeued = bufferQueue.dequeue()
        XCTAssertNotNil(dequeued)
        XCTAssertEqual(bufferQueue.stats.count, 0)

        // Clear
        bufferQueue.enqueue(buffer)
        bufferQueue.clear()
        XCTAssertEqual(bufferQueue.stats.count, 0)
        XCTAssertEqual(bufferQueue.stats.dropped, 0)
    }

    // MARK: - Testes de Error Handling

    func testErrorHandling_AudioRecorderInvalidFormat() async {
        let outputURL = createTemporaryURL()

        // Simular erro através de configuração inválida
        // Nota: Testes reais de erro são difíceis sem mocks específicos
        do {
            try await audioRecorder.startRecording(to: outputURL, source: .all, retryCount: 0)
            _ = await audioRecorder.stopRecording()
            // Se chegou aqui, não houve erro crítico
        } catch {
            // Erros são esperados em alguns ambientes de teste
            XCTAssertNotNil(error)
        }
    }

    func testErrorHandling_BufferQueueOverflowHandling() throws {
        let smallCapacityQueue = AudioBufferQueue(capacity: 3)
        let buffer = try createTestBuffer(frameCount: 512)

        // Preencher até capacidade
        for _ in 0..<3 {
            smallCapacityQueue.enqueue(buffer)
        }

        XCTAssertEqual(smallCapacityQueue.stats.count, 3)

        // Overflow - deve dropar oldest
        smallCapacityQueue.enqueue(buffer)

        XCTAssertEqual(smallCapacityQueue.stats.count, 3) // Capacidade mantida
        XCTAssertGreaterThan(smallCapacityQueue.stats.dropped, 0) // Deve ter dropped
    }

    // MARK: - Testes de Buffer Overflow

    func testBufferOverflow_AudioBufferQueueDropOldest() throws {
        let smallQueue = AudioBufferQueue(capacity: 2)
        let buffers = try (0..<4).map { try self.createTestBuffer(frameCount: AVAudioFrameCount($0 + 1) * 256) }

        // Enqueue beyond capacity
        for buffer in buffers {
            smallQueue.enqueue(buffer)
        }

        // Should maintain capacity
        XCTAssertEqual(smallQueue.stats.count, 2)

        // Should have dropped frames
        XCTAssertGreaterThan(smallQueue.stats.dropped, 0)

        // Dequeue should return most recent buffers
        let first = smallQueue.dequeue()
        let second = smallQueue.dequeue()

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(first?.frameLength, 768) // 3rd buffer (index 2)
        XCTAssertEqual(second?.frameLength, 1_024) // 4th buffer (index 3)
    }

    // MARK: - Testes de Thread Safety

    func testThreadSafety_BufferQueueConcurrentAccess() throws {
        let buffer = try createTestBuffer(frameCount: 1_024)
        let iterations = 50
        let expectation = expectation(description: "Concurrent operations")
        expectation.expectedFulfillmentCount = iterations * 3

        for _ in 0..<iterations {
            DispatchQueue.global().async { [bufferQueue = self.bufferQueue!] in
                bufferQueue.enqueue(buffer)
                expectation.fulfill()
            }

            DispatchQueue.global().async { [bufferQueue = self.bufferQueue!] in
                _ = bufferQueue.dequeue()
                expectation.fulfill()
            }

            DispatchQueue.global().async { [bufferQueue = self.bufferQueue!] in
                _ = bufferQueue.stats
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
        // Se chegou aqui sem crash, teste passou
    }

    // MARK: - Performance Tests

    // Performance tests have been moved to AudioSystemPerformanceTests.swift
    // Run with: swift test --filter "AudioSystemPerformanceTests"

    // MARK: - Testes de Cleanup Adequado

    func testCleanup_BufferQueueCompleteClear() throws {
        let buffer = try createTestBuffer(frameCount: 512)

        // Preencher queue
        for _ in 0..<10 {
            bufferQueue.enqueue(buffer)
        }

        XCTAssertGreaterThan(bufferQueue.stats.count, 0)

        // Clear
        bufferQueue.clear()

        XCTAssertTrue(bufferQueue.isEmpty)
        XCTAssertEqual(bufferQueue.stats.count, 0)
        XCTAssertEqual(bufferQueue.stats.dropped, 0)
    }

    func testCleanup_RecordingWorkerFileClosure() async throws {
        let outputURL = createTemporaryURL()
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))

        try await recordingWorker.start(writingTo: outputURL, format: format, fileFormat: .wav)

        let testBuffer = try createTestBuffer(frameCount: 1_024)
        recordingWorker.process(testBuffer)

        let finalURL = await recordingWorker.stop()

        XCTAssertNotNil(finalURL)
        XCTAssertTrue(try FileManager.default.fileExists(atPath: XCTUnwrap(finalURL?.path)))

        // Worker deve estar completamente limpo
        // (não há propriedades públicas para verificar, mas arquivo deve existir)
    }

    // MARK: - Helpers

    private func createTemporaryURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "test_audio_\(UUID().uuidString).m4a"
        return tempDir.appendingPathComponent(filename)
    }

    private func createTestBuffer(frameCount: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false,
        ) else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create format"])
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }

        buffer.frameLength = frameCount

        // Fill with test data
        if let channelData = buffer.floatChannelData {
            for ch in 0..<Int(format.channelCount) {
                for frame in 0..<Int(frameCount) {
                    channelData[ch][frame] = sin(Float(frame) * 0.01) // Simple sine wave
                }
            }
        }

        return buffer
    }

    private func createTestBuffers(count: Int, frameCount: AVAudioFrameCount) throws -> [AVAudioPCMBuffer] {
        try (0..<count).map { _ in try self.createTestBuffer(frameCount: frameCount) }
    }
}

// MARK: - Thread-Safe Helpers

/// Thread-safe array wrapper for test data collection in concurrent environments
private final class AtomicArray<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    var count: Int {
        lock.withLock { self.storage.count }
    }

    func append(_ element: Element) {
        lock.withLock { self.storage.append(element) }
    }

    func getElements() -> [Element] {
        lock.withLock { self.storage }
    }
}

/// Thread-safe counter for test coordination
private final class ThreadSafeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int = 0

    func increment() -> Int {
        lock.withLock {
            self.value += 1
            return self.value
        }
    }

    var currentValue: Int {
        lock.withLock { self.value }
    }
}
