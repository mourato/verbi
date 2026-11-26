import Combine
import Foundation
import SwiftUI
import VerbiCoreAI
import VerbiCoreAudio
import VerbiCoreCommon
import VerbiCoreData
import VerbiCoreDomain
import VerbiCoreInfrastructure

@MainActor
public class TranscriptionViewModel: ObservableObject {
    public let status: TranscriptionStatus
    private var cancellables = Set<AnyCancellable>()

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

    public var isReady: Bool {
        serviceState == .connected && modelState == .loaded && phase == .idle
    }

    public init(status: TranscriptionStatus) {
        self.status = status
        setupBindings()
    }

    private func setupBindings() {
        status.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
