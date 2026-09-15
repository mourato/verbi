import AppKit
import MeetingAssistantCoreDomain

@MainActor
public final class NSWorkspaceActiveAppContextProvider: ActiveAppContextProvider {
    public init() {}

    public func fetchActiveAppContext() throws -> ActiveAppContext? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = app.bundleIdentifier
        else {
            return nil
        }

        return ActiveAppContext(
            bundleIdentifier: bundleIdentifier,
            name: app.localizedName,
            processIdentifier: Int(app.processIdentifier)
        )
    }
}
