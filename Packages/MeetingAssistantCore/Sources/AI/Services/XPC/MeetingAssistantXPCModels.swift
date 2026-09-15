import Foundation

/// Centralized data structures for XPC communication.
public enum MeetingAssistantXPCModels {
    /// Settings passed from the app to the XPC service.
    public struct AppSettings: Codable, Sendable {
        public var diarization: Bool
        public var minSpeakers: Int
        public var maxSpeakers: Int
        public var numSpeakers: Int
        public var providerID: String?
        public var modelID: String?
        public var inputLanguageCode: String?
        public var executionMode: String?

        public init(
            diarization: Bool,
            minSpeakers: Int,
            maxSpeakers: Int,
            numSpeakers: Int,
            providerID: String? = nil,
            modelID: String? = nil,
            inputLanguageCode: String? = nil,
            executionMode: String? = nil
        ) {
            self.diarization = diarization
            self.minSpeakers = minSpeakers
            self.maxSpeakers = maxSpeakers
            self.numSpeakers = numSpeakers
            self.providerID = providerID
            self.modelID = modelID
            self.inputLanguageCode = inputLanguageCode
            self.executionMode = executionMode
        }

        public var hasExplicitTranscriptionRequest: Bool {
            providerID != nil || modelID != nil || inputLanguageCode != nil || executionMode != nil
        }
    }

    /// Service status information returned by the XPC service.
    public struct ServiceStatus: Codable, Sendable {
        public let status: String
        public let modelState: String
        public let modelLoaded: Bool
        public let device: String
        public let modelName: String
        public let uptimeSeconds: Double

        public init(status: String, modelState: String, modelLoaded: Bool, device: String, modelName: String, uptimeSeconds: Double) {
            self.status = status
            self.modelState = modelState
            self.modelLoaded = modelLoaded
            self.device = device
            self.modelName = modelName
            self.uptimeSeconds = uptimeSeconds
        }
    }
}
