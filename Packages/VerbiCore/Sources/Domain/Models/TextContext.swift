import Foundation

public struct TextContextSnapshot: Sendable, Equatable {
    public let text: String
    public let source: ContextSource
    public let capturedAt: Date
    public let appContext: ActiveAppContext?

    public init(
        text: String,
        source: ContextSource,
        capturedAt: Date = Date(),
        appContext: ActiveAppContext?
    ) {
        self.text = text
        self.source = source
        self.capturedAt = capturedAt
        self.appContext = appContext
    }
}

public enum ContextSource: String, Sendable, Equatable {
    case accessibility
    case selectedText
    case visibleOnly
    case unknown
}

public struct ActiveAppContext: Sendable, Equatable {
    public let bundleIdentifier: String
    public let name: String?
    public let processIdentifier: Int

    public init(bundleIdentifier: String, name: String?, processIdentifier: Int) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.processIdentifier = processIdentifier
    }
}

public enum ContextAcquisitionError: Error, Sendable, Equatable {
    case permissionDenied
    case noActiveApp
    case noFocusedElement
    case accessibilityUnsupported
    case excludedApp
    case providerFailed(String)
}

public struct TextContextPolicy: Sendable, Equatable {
    public let maxCharacters: Int
    public let preferredLineWindow: ClosedRange<Int>

    public init(maxCharacters: Int, preferredLineWindow: ClosedRange<Int>) {
        self.maxCharacters = maxCharacters
        self.preferredLineWindow = preferredLineWindow
    }

    public static let `default` = TextContextPolicy(
        maxCharacters: 15000,
        preferredLineWindow: 200 ... 400
    )
}
