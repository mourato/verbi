import Foundation

public protocol CursorTextContextProvider: Sendable {
    @MainActor func fetchCursorTextContext() -> CursorTextContext
}
