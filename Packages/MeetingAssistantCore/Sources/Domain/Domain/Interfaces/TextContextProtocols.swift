import Foundation

#if DEBUG
    import MeetingAssistantCoreMocking
#endif

#if DEBUG
    @GenerateMock
#endif
public protocol TextContextProvider: Sendable {
    func fetchTextContext() async throws -> TextContextSnapshot
    func fetchSelectedTextContext() async throws -> TextContextSnapshot?
}

public extension TextContextProvider {
    func fetchSelectedTextContext() throws -> TextContextSnapshot? {
        nil
    }
}

#if DEBUG
    @GenerateMock
#endif
public protocol ActiveAppContextProvider: Sendable {
    func fetchActiveAppContext() async throws -> ActiveAppContext?
}
