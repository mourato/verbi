import AppKit
import Foundation

public struct SettingsWindowLayoutStateEvaluation: Sendable, Equatable {
    public let keysToReset: [String]
    public let shouldCenterWindow: Bool
    public let requiresFrameClamp: Bool

    public var shouldResetPersistedLayout: Bool {
        !keysToReset.isEmpty
    }

    public init(
        keysToReset: [String],
        shouldCenterWindow: Bool,
        requiresFrameClamp: Bool
    ) {
        self.keysToReset = keysToReset.sorted()
        self.shouldCenterWindow = shouldCenterWindow
        self.requiresFrameClamp = requiresFrameClamp
    }
}

public enum SettingsWindowLayoutStateEvaluator {
    public static let autosaveWindowFrameDefaultsKey = "NSWindow Frame MeetingAssistantSettingsWindow"
    public static let legacyWindowFrameDefaultsKey = "NSWindow Frame com_apple_SwiftUI_Settings_window"
    public static let splitViewFramesDefaultsKey = "NSSplitView Subview Frames com_apple_SwiftUI_Settings_window, SidebarNavigationSplitView"

    private static let minimumVisibleAreaRatio: CGFloat = 0.6
    private static let sidebarWidthTolerance: CGFloat = 60
    private static let splitWidthTolerance: CGFloat = 40

    public static func evaluate(
        userDefaults: UserDefaults = .standard,
        visibleScreenFrames: [CGRect],
        defaultContentSize: CGSize = CGSize(width: 900, height: 700),
        sidebarWidthRange: ClosedRange<CGFloat> = 215 ... 215
    ) -> SettingsWindowLayoutStateEvaluation {
        evaluate(
            autosaveWindowFrameString: userDefaults.string(forKey: autosaveWindowFrameDefaultsKey),
            legacyWindowFrameString: userDefaults.string(forKey: legacyWindowFrameDefaultsKey),
            splitViewFrameStrings: userDefaults.stringArray(forKey: splitViewFramesDefaultsKey) ?? [],
            visibleScreenFrames: visibleScreenFrames,
            defaultContentSize: defaultContentSize,
            sidebarWidthRange: sidebarWidthRange
        )
    }

    public static func evaluate(
        autosaveWindowFrameString: String?,
        legacyWindowFrameString: String?,
        splitViewFrameStrings: [String],
        visibleScreenFrames: [CGRect],
        defaultContentSize: CGSize,
        sidebarWidthRange: ClosedRange<CGFloat>
    ) -> SettingsWindowLayoutStateEvaluation {
        let autosaveFrame = parseWindowFrame(autosaveWindowFrameString)
        let legacyFrame = parseWindowFrame(legacyWindowFrameString)
        let referenceFrame = autosaveFrame ?? legacyFrame
        let hasAutosaveFrame = autosaveFrame != nil
        let splitViewResetRequired = splitViewStateIsInvalid(
            frameStrings: splitViewFrameStrings,
            referenceWindowWidth: referenceFrame?.width ?? defaultContentSize.width,
            sidebarWidthRange: sidebarWidthRange
        )

        var keysToReset = Set<String>()

        if let autosaveFrame {
            switch evaluateWindowFrame(autosaveFrame, visibleScreenFrames: visibleScreenFrames) {
            case .invalid:
                keysToReset.insert(autosaveWindowFrameDefaultsKey)
                if legacyWindowFrameString != nil {
                    keysToReset.insert(legacyWindowFrameDefaultsKey)
                }
                if !splitViewFrameStrings.isEmpty {
                    keysToReset.insert(splitViewFramesDefaultsKey)
                }
            case .valid, .requiresClamp:
                if splitViewResetRequired {
                    keysToReset.insert(splitViewFramesDefaultsKey)
                }
            }
        } else {
            if let legacyFrame {
                if evaluateWindowFrame(legacyFrame, visibleScreenFrames: visibleScreenFrames) == .invalid {
                    keysToReset.insert(legacyWindowFrameDefaultsKey)
                }
            }

            if splitViewResetRequired {
                keysToReset.insert(splitViewFramesDefaultsKey)
            }
        }

        let shouldCenterWindow = !hasAutosaveFrame || keysToReset.contains(autosaveWindowFrameDefaultsKey)
        let requiresFrameClamp = hasAutosaveFrame && !keysToReset.contains(autosaveWindowFrameDefaultsKey)

        return SettingsWindowLayoutStateEvaluation(
            keysToReset: Array(keysToReset),
            shouldCenterWindow: shouldCenterWindow,
            requiresFrameClamp: requiresFrameClamp
        )
    }

    private static func evaluateWindowFrame(
        _ frame: CGRect,
        visibleScreenFrames: [CGRect]
    ) -> WindowFrameState {
        guard frame.width > 0, frame.height > 0 else {
            return .invalid
        }

        guard !visibleScreenFrames.isEmpty else {
            return .requiresClamp
        }

        let canFitOnVisibleScreen = visibleScreenFrames.contains {
            frame.width <= $0.width && frame.height <= $0.height
        }
        guard canFitOnVisibleScreen else {
            return .invalid
        }

        let midpoint = CGPoint(x: frame.midX, y: frame.midY)
        let containsMidpoint = visibleScreenFrames.contains { $0.contains(midpoint) }
        let bestIntersectionRatio = visibleScreenFrames
            .map { intersectionAreaRatio(frame, within: $0) }
            .max() ?? 0

        if bestIntersectionRatio == 0 {
            return .invalid
        }

        if !containsMidpoint, bestIntersectionRatio < minimumVisibleAreaRatio {
            return .invalid
        }

        let fullyContained = visibleScreenFrames.contains { $0.contains(frame) }
        return fullyContained ? .valid : .requiresClamp
    }

    private static func splitViewStateIsInvalid(
        frameStrings: [String],
        referenceWindowWidth: CGFloat,
        sidebarWidthRange: ClosedRange<CGFloat>
    ) -> Bool {
        guard !frameStrings.isEmpty else {
            return false
        }

        let parsedFrames = frameStrings.compactMap(parseSplitFrame)
        guard parsedFrames.count == frameStrings.count, parsedFrames.count >= 2 else {
            return true
        }

        let sidebarWidth = parsedFrames[0].width
        let sidebarMinimum = sidebarWidthRange.lowerBound - sidebarWidthTolerance
        let sidebarMaximum = sidebarWidthRange.upperBound + sidebarWidthTolerance
        guard sidebarWidth >= sidebarMinimum, sidebarWidth <= sidebarMaximum else {
            return true
        }

        let layoutWidth = parsedFrames.map(\.maxX).max() ?? 0
        guard layoutWidth > 0 else {
            return true
        }

        return abs(layoutWidth - referenceWindowWidth) > splitWidthTolerance
    }

    private static func parseWindowFrame(_ value: String?) -> CGRect? {
        guard let value else {
            return nil
        }

        let numbers = value
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Double($0) }

        guard numbers.count >= 4 else {
            return nil
        }

        return CGRect(
            x: CGFloat(numbers[0]),
            y: CGFloat(numbers[1]),
            width: CGFloat(numbers[2]),
            height: CGFloat(numbers[3])
        )
    }

    private static func parseSplitFrame(_ value: String) -> CGRect? {
        let numbers = value
            .split(separator: ",")
            .prefix(4)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap(Double.init)

        guard numbers.count == 4 else {
            return nil
        }

        return CGRect(
            x: CGFloat(numbers[0]),
            y: CGFloat(numbers[1]),
            width: CGFloat(numbers[2]),
            height: CGFloat(numbers[3])
        )
    }

    private static func intersectionAreaRatio(_ frame: CGRect, within visibleFrame: CGRect) -> CGFloat {
        let intersection = frame.intersection(visibleFrame)
        guard !intersection.isNull else {
            return 0
        }

        let frameArea = frame.width * frame.height
        guard frameArea > 0 else {
            return 0
        }

        return (intersection.width * intersection.height) / frameArea
    }

    private enum WindowFrameState {
        case valid
        case requiresClamp
        case invalid
    }
}
