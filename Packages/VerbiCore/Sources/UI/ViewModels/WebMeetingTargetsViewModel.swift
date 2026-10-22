import Combine
import Foundation
import VerbiCoreInfrastructure

@MainActor
public final class WebMeetingTargetsViewModel: ObservableObject {
    @Published var settings: AppSettingsStore
    @Published public var showEditor = false
    @Published public var editingTarget: WebMeetingTarget?
    @Published public var showDeleteConfirmation = false
    @Published public var targetToDelete: WebMeetingTarget?

    private var cancellables = Set<AnyCancellable>()

    public init(settings: AppSettingsStore = .shared) {
        self.settings = settings

        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public var targets: [WebMeetingTarget] {
        settings.webMeetingTargets
    }

    public func addTarget() {
        editingTarget = nil
        showEditor = true
    }

    public func editTarget(_ target: WebMeetingTarget) {
        editingTarget = target
        showEditor = true
    }

    public func handleSave(_ target: WebMeetingTarget) {
        var updated = settings.webMeetingTargets
        if let index = updated.firstIndex(where: { $0.id == target.id }) {
            updated[index] = target
        } else {
            updated.append(target)
        }
        settings.webMeetingTargets = updated
        editingTarget = nil
        showEditor = false
    }

    public func confirmDelete(_ target: WebMeetingTarget) {
        targetToDelete = target
        showDeleteConfirmation = true
    }

    public func executeDelete() {
        guard let target = targetToDelete else {
            showDeleteConfirmation = false
            return
        }

        settings.webMeetingTargets.removeAll { $0.id == target.id }
        targetToDelete = nil
        showDeleteConfirmation = false
    }
}
