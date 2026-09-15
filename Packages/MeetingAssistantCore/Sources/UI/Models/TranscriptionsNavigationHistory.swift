import Foundation

public enum TranscriptionsPageRoute: Hashable, Equatable {
    case list
    case conversation(UUID)
}

public struct TranscriptionsNavigationHistory: Equatable {
    private(set) var routes: [TranscriptionsPageRoute]
    private(set) var index: Int

    public init(initialRoute: TranscriptionsPageRoute = .list) {
        routes = [initialRoute]
        index = 0
    }

    public var currentRoute: TranscriptionsPageRoute {
        guard routes.indices.contains(index) else {
            return .list
        }
        return routes[index]
    }

    public var canGoBack: Bool {
        index > 0
    }

    public var canGoForward: Bool {
        index < routes.count - 1
    }

    public mutating func push(_ route: TranscriptionsPageRoute) {
        guard route != currentRoute else { return }

        if canGoForward {
            routes.removeSubrange((index + 1) ..< routes.count)
        }

        routes.append(route)
        index = routes.count - 1
    }

    @discardableResult
    public mutating func goBack() -> TranscriptionsPageRoute? {
        guard canGoBack else { return nil }
        index -= 1
        return currentRoute
    }

    @discardableResult
    public mutating func goForward() -> TranscriptionsPageRoute? {
        guard canGoForward else { return nil }
        index += 1
        return currentRoute
    }

    public mutating func sanitize(validConversationIDs: Set<UUID>) {
        var sanitizedRoutes: [TranscriptionsPageRoute] = []
        var sanitizedIndex = index

        for (position, route) in routes.enumerated() {
            let isValid: Bool = switch route {
            case .list:
                true
            case let .conversation(id):
                validConversationIDs.contains(id)
            }

            if isValid {
                sanitizedRoutes.append(route)
                continue
            }

            if position <= sanitizedIndex {
                sanitizedIndex -= 1
            }
        }

        if sanitizedRoutes.isEmpty {
            sanitizedRoutes = [.list]
            sanitizedIndex = 0
        }

        sanitizedIndex = min(max(sanitizedIndex, 0), sanitizedRoutes.count - 1)
        routes = sanitizedRoutes
        index = sanitizedIndex
    }
}
