import Foundation

public enum DictationStyleRoute: Hashable, Sendable {
    case editor(styleID: UUID?)
    case promptEditor(styleID: UUID?)
    case assistant
    case integrations
}

public enum DictationStyleFocusTarget: Hashable, Sendable {
    case addButton
    case style(UUID)
    case assistant
    case integrations

    public static func forStyleID(_ styleID: UUID?) -> Self {
        guard let styleID else { return .addButton }
        return .style(styleID)
    }
}

/// Escape behavior for the Modes side panel while a route is presented.
public enum DictationStyleEscapeBehavior: Equatable, Sendable {
    case dismissPanel
    case returnToEditor(styleID: UUID?)
}

public extension DictationStyleRoute {
    /// Focus target restored after the panel is fully dismissed for this route.
    var dismissFocusTarget: DictationStyleFocusTarget {
        switch self {
        case let .editor(styleID), let .promptEditor(styleID):
            .forStyleID(styleID)
        case .assistant:
            .assistant
        case .integrations:
            .integrations
        }
    }

    /// Escape while this route is current: nested prompt returns to the editor first.
    var escapeBehavior: DictationStyleEscapeBehavior {
        switch self {
        case let .promptEditor(styleID):
            .returnToEditor(styleID: styleID)
        case .editor, .assistant, .integrations:
            .dismissPanel
        }
    }
}
