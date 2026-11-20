import Foundation
import VerbiCoreAudio
import VerbiCoreCommon
import VerbiCoreDomain

/// Parallel ordered transcription of closed VAD speech windows for remote
/// incremental dictation.
///
/// Windows closed by `RealtimeVoiceActivityWindowAssembler` are transcribed
/// concurrently as pauses close them. Results are joined by window position
/// (sequence number), never by arrival order. Windows seen before the session
/// reaches `dispatchThresholdSeconds` of speech are buffered, so short
/// dictations dispatch zero window requests and fall back to one full-file
/// request at stop via `RemoteShortDictationSingleRequestError`.
actor IncrementalRemoteWindowBatcher {
    struct CompletedWindow: Sendable {
        let sequence: Int
        let response: TranscriptionResponse
        let startTime: Double
        let endTime: Double
    }

    private struct BufferedWindow: Sendable {
        let sequence: Int
        let samples: [Float]
        let startTime: Double
        let endTime: Double
    }

    private let dispatchThresholdSeconds: Double
    private var receivedSpeechSeconds = 0.0
    private var nextSequence = 0
    private var buffered: [BufferedWindow] = []
    private var tasks: [Int: Task<TranscriptionResponse, Error>] = [:]
    private var windowTimes: [Int: (start: Double, end: Double)] = [:]

    init(
        dispatchThresholdSeconds: Double = RemoteIncrementalDictationPolicy.shortDictationSingleRequestSeconds
    ) {
        self.dispatchThresholdSeconds = dispatchThresholdSeconds
    }

    var didDispatchAny: Bool {
        !tasks.isEmpty
    }

    var dispatchedWindowCount: Int {
        tasks.count
    }

    /// Ingests one closed window. Dispatches buffered and current windows
    /// once accumulated speech reaches the threshold.
    func ingest(
        samples: [Float],
        startTime: Double,
        endTime: Double,
        transcribe: @Sendable @escaping ([Float]) async throws -> TranscriptionResponse
    ) {
        let sequence = nextSequence
        nextSequence += 1
        receivedSpeechSeconds += max(0, endTime - startTime)
        let window = BufferedWindow(
            sequence: sequence,
            samples: samples,
            startTime: startTime,
            endTime: endTime
        )

        guard receivedSpeechSeconds >= dispatchThresholdSeconds else {
            buffered.append(window)
            return
        }

        for pending in buffered {
            dispatch(pending, transcribe: transcribe)
        }
        buffered.removeAll(keepingCapacity: true)
        dispatch(window, transcribe: transcribe)
    }

    /// Awaits dispatched windows in sequence order. Throws
    /// `RemoteShortDictationSingleRequestError` when nothing was dispatched.
    func drainOrdered() async throws -> [CompletedWindow] {
        guard !tasks.isEmpty else {
            throw RemoteShortDictationSingleRequestError()
        }
        var completed: [CompletedWindow] = []
        completed.reserveCapacity(tasks.count)
        for sequence in tasks.keys.sorted() {
            guard let task = tasks[sequence], let times = windowTimes[sequence] else { continue }
            do {
                let response = try await task.value
                completed.append(CompletedWindow(
                    sequence: sequence,
                    response: response,
                    startTime: times.start,
                    endTime: times.end
                ))
            } catch {
                cancelAll()
                throw error
            }
        }
        tasks.removeAll()
        windowTimes.removeAll()
        return completed
    }

    func cancelAll() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
        windowTimes.removeAll()
        buffered.removeAll()
    }

    private func dispatch(
        _ window: BufferedWindow,
        transcribe: @Sendable @escaping ([Float]) async throws -> TranscriptionResponse
    ) {
        windowTimes[window.sequence] = (window.startTime, window.endTime)
        tasks[window.sequence] = Task(priority: .userInitiated) {
            try await transcribe(window.samples)
        }
    }
}
