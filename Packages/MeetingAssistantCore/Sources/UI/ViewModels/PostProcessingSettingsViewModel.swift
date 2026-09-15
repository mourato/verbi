import Combine
import Foundation
import MeetingAssistantCoreInfrastructure

@MainActor
public class PostProcessingSettingsViewModel: ObservableObject {
    @Published var settings: AppSettingsStore
    private var cancellables = Set<AnyCancellable>()

    public init(settings: AppSettingsStore = .shared) {
        self.settings = settings

        // Forward settings changes to this ViewModel's observers to ensure UI refreshes
        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
