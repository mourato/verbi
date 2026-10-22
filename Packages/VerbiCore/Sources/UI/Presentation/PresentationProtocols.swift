import SwiftUI
import VerbiCoreAI
import VerbiCoreAudio
import VerbiCoreCommon
import VerbiCoreData
import VerbiCoreDomain
import VerbiCoreInfrastructure

// MARK: - Presentation Layer Protocols

/// Protocolo base para objetos que podem apresentar views
@MainActor
public protocol Presenter {
    associatedtype ViewType: View

    /// Retorna a view a ser apresentada
    func present() -> ViewType
}

/// Protocolo para objetos que coordenam navegação
@MainActor
public protocol Coordinator: AnyObject {
    /// Coordinator pai (opcional)
    var parentCoordinator: Coordinator? { get set }

    /// Coordinators filhos
    var childCoordinators: [Coordinator] { get set }

    /// Inicia o coordinator e retorna a view inicial
    func start() -> AnyView

    /// Navega para uma rota específica
    func navigate(to route: AppRoute)

    /// Volta para a tela anterior
    func goBack()

    /// Fecha o coordinator atual
    func dismiss()
}

/// Protocolo para view models que suportam navegação
@MainActor
public protocol NavigableViewModel: ObservableObject {
    associatedtype CoordinatorType: Coordinator

    /// Coordinator associado para navegação
    var coordinator: CoordinatorType? { get set }

    /// Ações de navegação disponíveis
    func navigate(to route: AppRoute)
    func goBack()
    func dismiss()
}

/// Protocolo para views que têm coordinators
@MainActor
public protocol CoordinatableView: View {
    associatedtype CoordinatorType: Coordinator

    /// Coordinator da view
    var coordinator: CoordinatorType { get }
}

// MARK: - Route Definitions

/// Rotas principais da aplicação
public enum AppRoute {
    case settings(SettingsRoute)
    case transcriptionDetails(CaptureArtifact)
    case permissionSetup

    /// Sub-rotas para configurações
    public enum SettingsRoute {
        case general
        case audio
        case transcription
        case shortcuts
        case postProcessing
    }
}

// MARK: - Type Aliases

// Type alias para facilitar uso do Coordinator base
