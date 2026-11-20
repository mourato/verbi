import SwiftUI
import VerbiCoreAI
import VerbiCoreAudio
import VerbiCoreCommon
import VerbiCoreData
import VerbiCoreDomain
import VerbiCoreInfrastructure

@MainActor
public protocol Presenter {
    associatedtype ViewType: View

    func present() -> ViewType
}

@MainActor
public protocol Coordinator: AnyObject {
    var parentCoordinator: Coordinator? { get set }

    var childCoordinators: [Coordinator] { get set }

    func start() -> AnyView

    func navigate(to route: AppRoute)

    func goBack()

    func dismiss()
}

@MainActor
public protocol NavigableViewModel: ObservableObject {
    associatedtype CoordinatorType: Coordinator

    var coordinator: CoordinatorType? { get set }

    func navigate(to route: AppRoute)
    func goBack()
    func dismiss()
}

@MainActor
public protocol CoordinatableView: View {
    associatedtype CoordinatorType: Coordinator

    var coordinator: CoordinatorType { get }
}

public enum AppRoute {
    case settings(SettingsRoute)
    case transcriptionDetails(CaptureArtifact)
    case permissionSetup

    public enum SettingsRoute {
        case general
        case audio
        case transcription
        case shortcuts
        case postProcessing
    }
}
