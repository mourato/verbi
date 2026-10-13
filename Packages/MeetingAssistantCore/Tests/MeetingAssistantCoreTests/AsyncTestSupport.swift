import XCTest

@MainActor
extension XCTestCase {
    func waitUntil(
        timeout: Duration = .seconds(1),
        pollInterval: Duration = .milliseconds(5),
        message: String = "Timed out waiting for condition.",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool,
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while !condition() {
            guard clock.now < deadline else {
                XCTFail(message, file: file, line: line)
                return
            }
            await Task.yield()
            // test-hygiene: allow sleep bounded poll interval inside deadline-guarded waitUntil; timeout fails the test
            try? await Task.sleep(for: pollInterval)
        }
    }
}
