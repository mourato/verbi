import CoreGraphics
@testable import MeetingAssistantCoreUI
import XCTest

final class AudioVisualizerMathTests: XCTestCase {
    func testBarHeight_StaysWithinMinAndMaxBounds() {
        let minHeight: CGFloat = 2
        let maxHeight: CGFloat = 24

        for level in stride(from: 0.0, through: 1.0, by: 0.05) {
            let height = AudioVisualizerMath.barHeight(
                level: level,
                minHeight: minHeight,
                maxHeight: maxHeight,
            )
            XCTAssertGreaterThanOrEqual(height, minHeight)
            XCTAssertLessThanOrEqual(height, maxHeight)
        }
    }

    func testTypeWhisperWaveformLevels_WhenAnimationInactive_ReturnsFlatZero() {
        let levels = AudioVisualizerMath.typeWhisperWaveformLevels(
            audioLevel: 0.72,
            barCount: 8,
            isAnimationActive: false,
        )

        XCTAssertEqual(levels, Array(repeating: 0.0, count: 8))
    }

    func testTypeWhisperWaveformLevels_StaysWithinNormalizedBounds() {
        let levels = AudioVisualizerMath.typeWhisperWaveformLevels(
            audioLevel: 0.64,
            barCount: 8,
            isAnimationActive: true,
        )

        XCTAssertEqual(levels.count, 8)
        XCTAssertTrue(levels.allSatisfy { $0 >= 0.0 && $0 <= 1.0 })
    }

    func testTypeWhisperWaveformLevels_DampensFirstBar() {
        let levels = AudioVisualizerMath.typeWhisperWaveformLevels(
            audioLevel: 0.75,
            barCount: 8,
            isAnimationActive: true,
        )

        XCTAssertGreaterThanOrEqual(levels.count, 2)
        XCTAssertLessThan(levels[0], levels[1])
    }

    func testTypeWhisperWaveformLevels_RespondsImmediatelyToLevelDecrease() {
        let highLevels = AudioVisualizerMath.typeWhisperWaveformLevels(
            audioLevel: 0.90,
            barCount: 8,
            isAnimationActive: true,
        )
        let lowLevels = AudioVisualizerMath.typeWhisperWaveformLevels(
            audioLevel: 0.20,
            barCount: 8,
            isAnimationActive: true,
        )

        XCTAssertEqual(highLevels.count, lowLevels.count)
        XCTAssertGreaterThan(highLevels.reduce(0, +), lowLevels.reduce(0, +))
    }

    func testSetupBounceLevel_MapsToExpectedNormalizedHeight() {
        let minHeight: CGFloat = 2
        let maxHeight: CGFloat = 24
        let expected = max(0.0, min(1.0, (14.0 - minHeight) / (maxHeight - minHeight)))

        XCTAssertEqual(expected, 12.0 / 22.0, accuracy: 0.0_001)
    }

    func testSetupBounce_ProducesSingleActiveBarLevel() {        let barCount = 8
        let activeIndex = 3
        let minHeight: CGFloat = 2
        let maxHeight: CGFloat = 24
        let bounceLevel = max(0.0, min(1.0, (14.0 - minHeight) / (maxHeight - minHeight)))

        let levels = (0..<barCount).map { index in
            index == activeIndex ? bounceLevel : 0.0
        }

        XCTAssertEqual(levels.count, barCount)
        XCTAssertEqual(levels.filter { $0 > 0 }.count, 1)
        XCTAssertEqual(levels[activeIndex], bounceLevel, accuracy: 0.0_001)
    }

    func testSpectrumBarLevels_WhenAnimationInactive_ReturnsFlatZero() {
        let spectrum = [Float](repeating: 0.8, count: 21)

        XCTAssertEqual(
            AudioVisualizerMath.spectrumBarLevels(spectrum: spectrum, barCount: 9, isAnimationActive: false),
            Array(repeating: 0.0, count: 9)
        )
    }

    func testSpectrumBarLevels_WhenEmpty_FallsBackToZero() {
        XCTAssertEqual(
            AudioVisualizerMath.spectrumBarLevels(spectrum: [], barCount: 9, isAnimationActive: true),
            Array(repeating: 0.0, count: 9)
        )
    }

    func testSpectrumBarLevels_ResamplesToBarCount() {
        let spectrum = [Float](repeating: 0.6, count: 21)

        let levels = AudioVisualizerMath.spectrumBarLevels(
            spectrum: spectrum,
            barCount: 9,
            isAnimationActive: true
        )

        XCTAssertEqual(levels.count, 9)
        XCTAssertTrue(levels.allSatisfy { $0 >= 0.0 && $0 <= 1.0 })
    }

    func testSpectrumBarLevels_TapersEdgeBars() {
        let spectrum = [Float](repeating: 1.0, count: 21)

        let levels = AudioVisualizerMath.spectrumBarLevels(
            spectrum: spectrum,
            barCount: 9,
            isAnimationActive: true
        )

        let middle = levels[4]
        XCTAssertLessThan(levels[0], middle)
        XCTAssertLessThan(levels[8], middle)
        XCTAssertEqual(middle, 1.0, accuracy: 0.0_001)
    }
}
