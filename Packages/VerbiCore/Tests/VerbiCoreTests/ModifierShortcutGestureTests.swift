@testable import VerbiCore
import XCTest

final class ModifierShortcutGestureTests: XCTestCase {
    func testGestureNormalizationSortsAndDeduplicatesKeys() {
        let gesture = ModifierShortcutGesture(
            keys: [.rightShift, .leftCommand, .leftCommand, .fn],
            triggerMode: .singleTap,
        )

        XCTAssertEqual(gesture.keys, [.leftCommand, .rightShift, .fn])
    }

    func testLegacyPresetMappingUsesActivationMode() {
        let gesture = PresetShortcutKey.rightCommand
            .asLegacyModifierGesture(activationMode: .doubleTap)

        XCTAssertEqual(gesture?.keys, [.rightCommand])
        XCTAssertEqual(gesture?.triggerMode, .doubleTap)
    }

    func testLegacyPresetMappingReturnsNilForCustom() {
        XCTAssertNil(PresetShortcutKey.custom.asLegacyModifierGesture(activationMode: .hold))
    }

    func testConflictServiceDetectsConflictingSignature() {
        let existing = ModifierShortcutBinding(
            actionID: .assistant,
            actionDisplayName: "Assistant",
            gesture: ModifierShortcutGesture(
                keys: [.rightCommand],
                triggerMode: .singleTap,
            ),
        )
        let candidate = ModifierShortcutBinding(
            actionID: .dictation,
            actionDisplayName: "Dictation",
            gesture: ModifierShortcutGesture(
                keys: [.rightCommand],
                triggerMode: .singleTap,
            ),
        )

        let conflict = ModifierShortcutConflictService.conflict(for: candidate, in: [existing])

        XCTAssertEqual(conflict?.candidate.actionID, .dictation)
        XCTAssertEqual(conflict?.conflicting.actionID, .assistant)
        XCTAssertEqual(conflict?.conflicting.actionDisplayName, "Assistant")
    }

    func testConflictServiceIgnoresSameActionIdentifier() {
        let existing = ModifierShortcutBinding(
            actionID: .dictation,
            actionDisplayName: "Dictation",
            gesture: ModifierShortcutGesture(keys: [.rightCommand], triggerMode: .singleTap),
        )
        let candidate = ModifierShortcutBinding(
            actionID: .dictation,
            actionDisplayName: "Dictation",
            gesture: ModifierShortcutGesture(keys: [.rightCommand], triggerMode: .singleTap),
        )

        let conflict = ModifierShortcutConflictService.conflict(for: candidate, in: [existing])

        XCTAssertNil(conflict)
    }

    func testAllConflictsReturnsOnlyDuplicatesAfterFirstOccurrence() {
        let dictation = ModifierShortcutBinding(
            actionID: .dictation,
            actionDisplayName: "Dictation",
            gesture: ModifierShortcutGesture(keys: [.rightOption], triggerMode: .hold),
        )
        let assistant = ModifierShortcutBinding(
            actionID: .assistant,
            actionDisplayName: "Assistant",
            gesture: ModifierShortcutGesture(keys: [.rightOption], triggerMode: .hold),
        )
        let meeting = ModifierShortcutBinding(
            actionID: .meeting,
            actionDisplayName: "Meetings",
            gesture: ModifierShortcutGesture(keys: [.leftShift], triggerMode: .singleTap),
        )

        let conflicts = ModifierShortcutConflictService.allConflicts(in: [dictation, assistant, meeting])

        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts.first?.candidate.actionID, .assistant)
        XCTAssertEqual(conflicts.first?.conflicting.actionID, .dictation)
    }
}
