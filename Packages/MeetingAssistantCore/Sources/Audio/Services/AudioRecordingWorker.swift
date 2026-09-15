import Atomics
@preconcurrency import AVFoundation
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import os.lock

// MARK: - Audio Recording Worker

/// A thread-safe actor that handles Audio Processing and File Writing.
/// Extracted from AudioRecorder.swift to adhere to Single Responsibility Principle.
/// Uses Actor pattern for automatic thread safety isolation.
actor AudioRecordingWorker {
    private enum AdaptiveMeteringMode {
        case normal
        case reduced
    }

    private enum AdaptiveMeteringConstants {
        static let highWatermarkBufferCount = 70
        static let lowWatermarkBufferCount = 24
        static let reducedSnapshotStride = 3
        static let reducedBarCountCap = 12
    }

    private final class BufferSignalStorage: @unchecked Sendable {
        private let continuationLock = OSAllocatedUnfairLock<AsyncStream<Void>.Continuation?>(initialState: nil)

        func set(_ continuation: AsyncStream<Void>.Continuation?) {
            continuationLock.withLock { $0 = continuation }
        }

        func yield() {
            _ = continuationLock.withLock { $0?.yield(()) }
        }

        func finishAndClear() {
            continuationLock.withLock { continuation in
                continuation?.finish()
                continuation = nil
            }
        }
    }

    struct MeterSnapshot {
        let averagePowerDB: Float
        let peakPowerDB: Float
        let barPowerDBLevels: [Float]
        let deltaTime: TimeInterval
    }

    private struct FileWriteConfiguration {
        let settings: [String: Any]
        let commonFormat: AVAudioCommonFormat
        let interleaved: Bool
    }

    // MARK: - State

    private var audioFile: AVAudioFile?
    private var currentURL: URL?

    // Atomic state for validation and lifecycle
    private let _hasReceivedValidBuffer = ManagedAtomic<Bool>(false)
    private let _isStopping = ManagedAtomic<Bool>(false)
    var hasReceivedValidBuffer: Bool {
        _hasReceivedValidBuffer.load(ordering: .relaxed)
    }

    // Callbacks - marked as Sendable since they are set from MainActor
    private var onPowerUpdate: (@Sendable (Float, Float, [Float]) -> Void)?
    private var onError: (@Sendable (AudioRecorderError) -> Void)?
    private var onProcessedBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var meteringBarCount = 0
    private var adaptiveMeteringMode: AdaptiveMeteringMode = .normal
    private var pendingMeterSnapshotSkips = 0
    private let energyMeterKernel: any EnergyMeterKernel

    /// Non-isolated buffer queue for synchronous enqueue from tap
    private nonisolated let bufferQueue = AudioBufferQueue(capacity: 100)

    /// Processing task
    private var processingTask: Task<Void, Never>?
    private let bufferSignalStorage = BufferSignalStorage()

    init(energyMeterKernel: any EnergyMeterKernel = SwiftEnergyMeterKernel.shared) {
        self.energyMeterKernel = energyMeterKernel
    }

    // MARK: - Callback Setters

    nonisolated func setOnPowerUpdate(_ callback: (@Sendable (Float, Float, [Float]) -> Void)?) {
        Task { await self.setOnPowerUpdateIsolated(callback) }
    }

    nonisolated func setOnError(_ callback: (@Sendable (AudioRecorderError) -> Void)?) {
        Task { await self.setOnErrorIsolated(callback) }
    }

    nonisolated func setOnProcessedBuffer(_ callback: (@Sendable (AVAudioPCMBuffer) -> Void)?) {
        Task { await self.setOnProcessedBufferIsolated(callback) }
    }

    nonisolated func setMeteringBarCount(_ barCount: Int) {
        Task { await self.setMeteringBarCountIsolated(barCount) }
    }

    private func setOnPowerUpdateIsolated(_ callback: (@Sendable (Float, Float, [Float]) -> Void)?) {
        onPowerUpdate = callback
    }

    private func setOnErrorIsolated(_ callback: (@Sendable (AudioRecorderError) -> Void)?) {
        onError = callback
    }

    private func setOnProcessedBufferIsolated(_ callback: (@Sendable (AVAudioPCMBuffer) -> Void)?) {
        onProcessedBuffer = callback
    }

    private func setMeteringBarCountIsolated(_ barCount: Int) {
        meteringBarCount = max(0, barCount)
    }

    func prepareForGraphRecovery() {
        _hasReceivedValidBuffer.store(false, ordering: .relaxed)
        adaptiveMeteringMode = .normal
        pendingMeterSnapshotSkips = 0
    }

    // MARK: - Property Accessors

    nonisolated func getHasReceivedValidBuffer() async -> Bool {
        await getHasReceivedValidBufferIsolated()
    }

    private func getHasReceivedValidBufferIsolated() -> Bool {
        hasReceivedValidBuffer
    }

    // MARK: - Lifecycle

    func start(writingTo url: URL, format: AVAudioFormat, fileFormat: AppSettingsStore.AudioFormat) throws {
        resetStateForNewSession()
        try prepareOutputFileIfNeeded(at: url)
        audioFile = try createOutputAudioFile(url: url, format: format, fileFormat: fileFormat)
        currentURL = url

        let bufferSignalStream = AsyncStream<Void> { continuation in
            self.bufferSignalStorage.set(continuation)
        }

        processingTask = Task {
            await self.processBuffers(bufferSignalStream)
        }
    }

    private func resetStateForNewSession() {
        audioFile = nil
        _hasReceivedValidBuffer.store(false, ordering: .relaxed)
        _isStopping.store(false, ordering: .relaxed)
        processingTask?.cancel()
        processingTask = nil
        bufferSignalStorage.finishAndClear()
        bufferQueue.clear()
    }

    private func prepareOutputFileIfNeeded(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func createOutputAudioFile(
        url: URL,
        format: AVAudioFormat,
        fileFormat: AppSettingsStore.AudioFormat
    ) throws -> AVAudioFile {
        do {
            return try makeAudioFile(url: url, configuration: makeFileWriteConfiguration(for: fileFormat, format: format))
        } catch {
            print("Failed to initialize audio file with format \(fileFormat): \(error). Falling back to WAV.")
            return try makeAudioFile(url: url, configuration: makeFileWriteConfiguration(for: .wav, format: format))
        }
    }

    private func makeAudioFile(url: URL, configuration: FileWriteConfiguration) throws -> AVAudioFile {
        try AVAudioFile(
            forWriting: url,
            settings: configuration.settings,
            commonFormat: configuration.commonFormat,
            interleaved: configuration.interleaved
        )
    }

    private func makeFileWriteConfiguration(
        for targetFormat: AppSettingsStore.AudioFormat,
        format: AVAudioFormat
    ) -> FileWriteConfiguration {
        switch targetFormat {
        case .m4a:
            FileWriteConfiguration(
                settings: [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128_000
                ],
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        case .wav:
            FileWriteConfiguration(
                settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: 2,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ],
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        }
    }

    func stop() async -> URL? {
        // Mark as stopping but don't cancel yet - allow loop to drain queue
        _isStopping.store(true, ordering: .relaxed)
        bufferSignalStorage.yield()

        // Wait for task to finish processing remaining buffers
        await processingTask?.value
        processingTask = nil
        bufferSignalStorage.finishAndClear()

        // Clear queue after task completes
        bufferQueue.clear()

        // Close file safely
        let url = currentURL
        audioFile = nil
        currentURL = nil

        return url
    }

    // MARK: - Processing

    nonisolated func process(_ buffer: AVAudioPCMBuffer) {
        bufferQueue.enqueue(buffer)
        bufferSignalStorage.yield()
    }

    private func processBuffers(_ bufferSignalStream: AsyncStream<Void>) async {
        for await _ in bufferSignalStream {
            while let buffer = bufferQueue.dequeue() {
                processBufferInternal(buffer)
            }

            if _isStopping.load(ordering: .relaxed) || Task.isCancelled {
                break
            }
        }

        while let buffer = bufferQueue.dequeue() {
            processBufferInternal(buffer)
        }
    }

    private func processBufferInternal(_ buffer: AVAudioPCMBuffer) {
        updateAdaptiveMeteringMode()

        if shouldEmitMeterSnapshot(),
           let snapshot = energyMeterKernel.makeMeterSnapshot(
               from: buffer,
               barCount: effectiveMeteringBarCount
           )
        {
            onPowerUpdate?(
                snapshot.averagePowerDB,
                snapshot.peakPowerDB,
                snapshot.barPowerDBLevels
            )
        }

        // Lock removed; serialized by queue

        guard let audioFile else { return }
        guard buffer.frameLength > 0 else { return }

        onProcessedBuffer?(buffer)

        do {
            try audioFile.write(from: buffer)
            _hasReceivedValidBuffer.store(true, ordering: .relaxed)
        } catch {
            onError?(AudioRecorderError.fileWriteFailed(error))
        }
    }

    private var effectiveMeteringBarCount: Int {
        switch adaptiveMeteringMode {
        case .normal:
            meteringBarCount
        case .reduced:
            min(meteringBarCount, AdaptiveMeteringConstants.reducedBarCountCap)
        }
    }

    private func shouldEmitMeterSnapshot() -> Bool {
        let stride: Int = switch adaptiveMeteringMode {
        case .normal:
            1
        case .reduced:
            AdaptiveMeteringConstants.reducedSnapshotStride
        }

        guard stride > 1 else {
            pendingMeterSnapshotSkips = 0
            return true
        }

        if pendingMeterSnapshotSkips > 0 {
            pendingMeterSnapshotSkips -= 1
            return false
        }

        pendingMeterSnapshotSkips = stride - 1
        return true
    }

    private func updateAdaptiveMeteringMode() {
        let pendingBuffers = bufferQueue.stats.count

        switch adaptiveMeteringMode {
        case .normal:
            guard pendingBuffers >= AdaptiveMeteringConstants.highWatermarkBufferCount else { return }
            adaptiveMeteringMode = .reduced
            pendingMeterSnapshotSkips = 0
            AppLogger.warning(
                "Audio metering switched to reduced mode due to queue pressure",
                category: .performance,
                extra: ["pendingBuffers": pendingBuffers]
            )
        case .reduced:
            guard pendingBuffers <= AdaptiveMeteringConstants.lowWatermarkBufferCount else { return }
            adaptiveMeteringMode = .normal
            pendingMeterSnapshotSkips = 0
            AppLogger.info(
                "Audio metering restored to normal mode",
                category: .performance,
                extra: ["pendingBuffers": pendingBuffers]
            )
        }
    }

    nonisolated static func makeMeterSnapshot(
        from buffer: AVAudioPCMBuffer,
        barCount: Int
    ) -> MeterSnapshot? {
        SwiftEnergyMeterKernel.shared.makeMeterSnapshot(from: buffer, barCount: barCount)
    }
}
