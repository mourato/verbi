import CoreGraphics
import CoreText
import Foundation
import Synchronization
@testable import VerbiCoreInfrastructure
import XCTest

@MainActor
final class WindowTextRecognizerTests: XCTestCase {
    func testRecognitionRunsOffMainThread() async throws {
        let recognizer = WindowTextRecognizer { _ in
            Thread.isMainThread ? "blocked UI executor" : "background result"
        }

        let result = try await recognizer.recognize(image())

        XCTAssertEqual(result, "background result")
    }

    func testCancelledRecognitionKeepsSlotUntilVisionFinishesAndDiscardsResult() async throws {
        let started = expectation(description: "Recognition started")
        let release = DispatchSemaphore(value: 0)
        let calls = Mutex(0)
        let recognizer = WindowTextRecognizer { _ in
            let call = calls.withLock { count in
                count += 1
                return count
            }
            if call == 1 {
                started.fulfill()
                guard release.wait(timeout: .now() + 10) == .success else { return "worker timed out" }
            }
            return "recognized text"
        }
        let image = try image()
        let first = Task { await recognizer.recognize(image) }
        defer { release.signal() }
        await fulfillment(of: [started], timeout: 5)

        let overlapping = await recognizer.recognize(image)
        XCTAssertNil(overlapping)
        first.cancel()
        let whileCancelledWorkerRuns = await recognizer.recognize(image)
        XCTAssertNil(whileCancelledWorkerRuns)
        XCTAssertEqual(calls.withLock { $0 }, 1)

        release.signal()
        let cancelledResult = await first.value
        XCTAssertNil(cancelledResult)

        let nextResult = await recognizer.recognize(image)
        XCTAssertEqual(nextResult, "recognized text")
        XCTAssertEqual(calls.withLock { $0 }, 2)
    }

    func testAlreadyCancelledCaptureDoesNotStartRecognition() async throws {
        let calls = Mutex(0)
        let recognizer = WindowTextRecognizer { _ in
            calls.withLock { $0 += 1 }
            return "unexpected text"
        }
        let image = try image()
        let capture = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await recognizer.recognize(image)
        }

        let result = await capture.value

        XCTAssertNil(result)
        XCTAssertEqual(calls.withLock { $0 }, 0)
    }

    func testRecognizesSyntheticWindowTextWithVision() async throws {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 800,
            height: 140,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 140))
        let text = NSAttributedString(string: "HELLO VERBI", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 64, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ])
        context.textPosition = CGPoint(x: 30, y: 40)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        let image = try XCTUnwrap(context.makeImage())

        let result = await WindowTextRecognizer().recognize(image)

        XCTAssertEqual(result, "HELLO VERBI")
    }

    private func image() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }
}
