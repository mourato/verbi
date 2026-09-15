import Foundation

public struct CursorTextContext: Sendable, Equatable {
    public enum Support: Sendable, Equatable {
        case supported
        case unsupported
        case permissionDenied
    }

    public let previousCharacter: Character?
    public let nextCharacter: Character?
    public let isEmptyDocument: Bool
    public let support: Support

    public init(
        previousCharacter: Character?,
        nextCharacter: Character?,
        isEmptyDocument: Bool,
        support: Support
    ) {
        self.previousCharacter = previousCharacter
        self.nextCharacter = nextCharacter
        self.isEmptyDocument = isEmptyDocument
        self.support = support
    }
}
