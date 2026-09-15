public enum ActivityPendingSheet: Hashable, Sendable {
    case performance
}

public struct ActivitySettingsNavigationState: Equatable {
    public var pendingSheet: ActivityPendingSheet?

    public init(
        pendingSheet: ActivityPendingSheet? = nil
    ) {
        self.pendingSheet = pendingSheet
    }
}
