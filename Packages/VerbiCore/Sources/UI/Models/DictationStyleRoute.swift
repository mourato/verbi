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

public enum DictationStyleEscapeBehavior: Equatable, Sendable {
    case dismissPanel
    case returnToEditor(styleID: UUID?)
}

public extension DictationStyleRoute {
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

    var escapeBehavior: DictationStyleEscapeBehavior {
        switch self {
        case let .promptEditor(styleID):
            .returnToEditor(styleID: styleID)
        case .editor, .assistant, .integrations:
            .dismissPanel
        }
    }
}
