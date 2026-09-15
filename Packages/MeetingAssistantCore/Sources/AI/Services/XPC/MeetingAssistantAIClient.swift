import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import OSLog

private let meetingAssistantAIClientLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "AIClient")

private final class ContinuationGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }
}

private func makeXPCProxyErrorHandler(
    context: String,
    gate: ContinuationGate<some Sendable>
) -> @Sendable (Error) -> Void {
    { error in
        meetingAssistantAIClientLogger.error(
            "XPC Proxy Error (\(context, privacy: .public)): \(error.localizedDescription, privacy: .public)"
        )
        gate.resume(throwing: error)
    }
}

/// Client for communicating with the MeetingAssistant AI XPC Service.
@MainActor
public class MeetingAssistantAIClient {
    public static let shared = MeetingAssistantAIClient()

    private var connection: NSXPCConnection?

    private init() {
        // Connection is setup lazily upon first use
    }

    private func setupConnection() {
        guard FeatureFlags.useXPCService else {
            meetingAssistantAIClientLogger.warning("Attempted to setup XPC connection but useXPCService is false")
            return
        }

        // Use anonymous XPC connection - launchd will find the embedded service
        let conn = NSXPCConnection(serviceName: MeetingAssistantXPCConstants.serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: MeetingAssistantXPCProtocol.self)

        conn.interruptionHandler = {
            meetingAssistantAIClientLogger.error("XPC Connection Interrupted")
        }

        conn.invalidationHandler = { [weak self] in
            meetingAssistantAIClientLogger.error("XPC Connection Invalidated")
            Task { @MainActor in
                self?.connection = nil
            }
        }

        conn.resume()
        connection = conn
        meetingAssistantAIClientLogger.info("XPC Connection setup with service name: \(MeetingAssistantXPCConstants.serviceName)")
    }

    /// Transcribes an audio file using the XPC Service.
    // Explicit XPC payload keeps speaker controls at this existing wire edge.
    // swiftlint:disable function_parameter_count
    public func transcribe(
        audioURL: URL,
        diarizationEnabledOverride: Bool? = nil
    ) async throws -> TranscriptionResponse {
        let store = AppSettingsStore.shared
        let mode: TranscriptionExecutionMode = .meeting
        return try await transcribe(
            audioURL: audioURL,
            diarizationEnabledOverride: diarizationEnabledOverride,
            executionMode: mode,
            selection: store.resolvedTranscriptionSelection(for: mode),
            inputLanguageCode: store.resolvedTranscriptionInputLanguageCode(for: mode),
            vocabularyHints: nil,
            minSpeakers: store.minSpeakers ?? 1,
            maxSpeakers: store.maxSpeakers ?? 10,
            numSpeakers: store.numSpeakers ?? 0
        )
    }

    public func transcribe(
        audioURL: URL,
        diarizationEnabledOverride: Bool?,
        executionMode: TranscriptionExecutionMode,
        selection: TranscriptionProviderSelection,
        inputLanguageCode: String?,
        vocabularyHints _: VocabularyProviderHints?,
        minSpeakers: Int = 1,
        maxSpeakers: Int = 10,
        numSpeakers: Int = 0
    ) async throws -> TranscriptionResponse {
        guard FeatureFlags.useXPCService else {
            throw TranscriptionError.serviceUnavailable
        }

        guard let connection else {
            setupConnection()

            // Re-check after setup attempt
            if connection == nil {
                throw TranscriptionError.serviceUnavailable
            }

            return try await transcribe(
                audioURL: audioURL,
                diarizationEnabledOverride: diarizationEnabledOverride,
                executionMode: executionMode,
                selection: selection,
                inputLanguageCode: inputLanguageCode,
                vocabularyHints: nil,
                minSpeakers: minSpeakers,
                maxSpeakers: maxSpeakers,
                numSpeakers: numSpeakers
            )
        }

        let settings = MeetingAssistantXPCModels.AppSettings(
            diarization: diarizationEnabledOverride ?? false,
            minSpeakers: minSpeakers,
            maxSpeakers: maxSpeakers,
            numSpeakers: numSpeakers,
            providerID: selection.provider.rawValue,
            modelID: selection.selectedModel,
            inputLanguageCode: inputLanguageCode,
            executionMode: executionMode.rawValue
        )
        let settingsData = try JSONEncoder().encode(settings)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<TranscriptionResponse, Error>) in
            let gate = ContinuationGate(continuation)

            let proxy = connection.remoteObjectProxyWithErrorHandler(
                makeXPCProxyErrorHandler(context: "Transcribe", gate: gate)
            ) as? MeetingAssistantXPCProtocol

            guard let service = proxy else {
                gate.resume(throwing: TranscriptionError.serviceUnavailable)
                return
            }

            service.transcribe(audioURL: audioURL, settingsData: settingsData) { data, error in
                if let error {
                    gate.resume(throwing: error)
                    return
                }

                guard let data else {
                    gate.resume(throwing: TranscriptionError.invalidResponse)
                    return
                }

                do {
                    let response = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
                    gate.resume(returning: response)
                } catch {
                    gate.resume(throwing: error)
                }
            }
        }
    }

    // swiftlint:enable function_parameter_count

    /// Fetches the status of the AI service with timeout.
    public func fetchServiceStatus(timeout: TimeInterval = 5.0) async throws -> MeetingAssistantXPCModels.ServiceStatus {
        meetingAssistantAIClientLogger.info("Fetching service status...")

        guard FeatureFlags.useXPCService else {
            throw TranscriptionError.serviceUnavailable
        }

        guard let connection else {
            meetingAssistantAIClientLogger.info("No existing connection, setting up...")
            setupConnection()

            // Re-check after setup attempt
            if connection == nil {
                throw TranscriptionError.serviceUnavailable
            }

            // Small delay to allow connection to establish
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            return try await fetchServiceStatus(timeout: timeout)
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MeetingAssistantXPCModels.ServiceStatus, Error>) in
            let gate = ContinuationGate(continuation)

            // Set up timeout
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                gate.resume(throwing: TranscriptionError.serviceUnavailable)
            }

            let proxy = connection.remoteObjectProxyWithErrorHandler(
                makeXPCProxyErrorHandler(context: "Status", gate: gate)
            ) as? MeetingAssistantXPCProtocol

            guard let service = proxy else {
                timeoutTask.cancel()
                gate.resume(throwing: TranscriptionError.serviceUnavailable)
                return
            }

            meetingAssistantAIClientLogger.info("Sending fetchServiceStatus request...")

            service.fetchServiceStatus { data, error in
                timeoutTask.cancel()

                if let error {
                    meetingAssistantAIClientLogger.error("Service status fetch failed: \(error.localizedDescription)")
                    gate.resume(throwing: error)
                    return
                }

                guard let data else {
                    gate.resume(throwing: TranscriptionError.invalidResponse)
                    return
                }

                do {
                    let status = try JSONDecoder().decode(MeetingAssistantXPCModels.ServiceStatus.self, from: data)
                    meetingAssistantAIClientLogger.info("Service status received: \(status.status)")
                    gate.resume(returning: status)
                } catch {
                    gate.resume(throwing: error)
                }
            }
        }
    }

    /// Warms up the models in the XPC service.
    public func warmupModel() async throws {
        guard FeatureFlags.useXPCService else {
            throw TranscriptionError.serviceUnavailable
        }

        guard let connection else {
            setupConnection()

            // Re-check after setup attempt
            if connection == nil {
                throw TranscriptionError.serviceUnavailable
            }

            return try await warmupModel()
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ContinuationGate(continuation)

            let proxy = connection.remoteObjectProxyWithErrorHandler(
                makeXPCProxyErrorHandler(context: "Warmup", gate: gate)
            ) as? MeetingAssistantXPCProtocol

            guard let service = proxy else {
                gate.resume(throwing: TranscriptionError.serviceUnavailable)
                return
            }

            service.warmupModel { error in
                if let error {
                    gate.resume(throwing: error)
                } else {
                    gate.resume(returning: ())
                }
            }
        }
    }
}
