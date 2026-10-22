import Foundation

public struct SettingsSubpageNavigationState<Route: Hashable & Equatable>: Equatable {
    public var currentRoute: Route?
    public var forwardRoute: Route?

    public init(
        currentRoute: Route? = nil,
        forwardRoute: Route? = nil
    ) {
        self.currentRoute = currentRoute
        self.forwardRoute = forwardRoute
    }

    public var canGoBack: Bool {
        currentRoute != nil
    }

    public var canGoForward: Bool {
        forwardRoute != nil
    }

    public mutating func open(_ route: Route) {
        guard currentRoute != route else { return }
        currentRoute = route
        forwardRoute = nil
    }

    @discardableResult
    public mutating func goBack() -> Route? {
        guard let currentRoute else { return nil }
        forwardRoute = currentRoute
        self.currentRoute = nil
        return self.currentRoute
    }

    @discardableResult
    public mutating func goForward() -> Route? {
        guard let forwardRoute else { return nil }
        currentRoute = forwardRoute
        self.forwardRoute = nil
        return currentRoute
    }
}
