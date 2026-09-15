import Combine
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

@MainActor
public class TranscriptionViewModel: ObservableObject {
    // MARK: - Dependencies

    private let status: TranscriptionStatus
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Published Properties for UI (Computed Proxies)

    public var statusMessage: String {
        status.statusMessage
    }

    public var progressPercentage: Double {
        status.progressPercentage
    }

    public var currentStatus: TranscriptionStatus.State {
        status.currentStatus
    }

    public var estimatedTimeRemaining: TimeInterval? {
        status.estimatedTimeRemaining
    }

    public var isProcessing: Bool {
        status.isProcessing
    }

    public var hasBlockingError: Bool {
        status.hasBlockingError
    }

    public var phase: TranscriptionPhase {
        status.phase
    }

    public var serviceState: ServiceState {
        status.serviceState
    }

    public var modelState: ModelState {
        status.modelState
    }

    public var lastError: TranscriptionStatusError? {
        status.lastError
    }

    public var device: String {
        status.device
    }

    // MARK: - Computed Properties

    public var isReady: Bool {
        serviceState == .connected && modelState == .loaded && phase == .idle
    }

    // MARK: - Initialization

    public init(status: TranscriptionStatus) {
        self.status = status
        setupBindings()
    }

    // MARK: - Private Methods

    private func setupBindings() {
        // Forward all changes from the model to the view model
        status.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
