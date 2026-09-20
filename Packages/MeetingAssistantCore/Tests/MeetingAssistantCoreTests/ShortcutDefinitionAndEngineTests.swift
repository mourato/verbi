import Foundation
@testable import MeetingAssistantCore
import XCTest

final class ShortcutDefinitionAndEngineTests: XCTestCase {
    func testSimpleShortcutOnlyAllowsSingleTap() {
        let shortcut = ShortcutDefinition(
            modifiers: [.leftCommand],
            primaryKey: .letter("G", keyCode: 0x05),
            trigger: .singleTap,
        )

        XCTAssertEqual(shortcut.patternType, .simple)
        XCTAssertEqual(shortcut.allowedTriggers, [.singleTap])
        XCTAssertTrue(shortcut.isValid)
    }

    func testIntermediateShortcutRejectsDoubleTap() {
        let shortcut = ShortcutDefinition(
            modifiers: [.leftCommand, .leftShift],
            primaryKey: .letter("K", keyCode: 0x28),
            trigger: .doubleTap,
        )

        XCTAssertEqual(shortcut.validate(), .unsupportedTriggerForSimpleOrIntermediate)
    }

    func testAdvancedShortcutRejectsSingleTap() {
        let shortcut = ShortcutDefinition(
            modifiers: [.rightCommand],
            primaryKey: nil,
            trigger: .singleTap,
        )

        XCTAssertEqual(shortcut.patternType, .advanced)
        XCTAssertEqual(shortcut.validate(), .unsupportedTriggerForAdvanced)
    }

    func testAdvancedShortcutRejectsMultipleModifiers() {
        let shortcut = ShortcutDefinition(
            modifiers: [.leftCommand, .rightCommand],
            primaryKey: nil,
            trigger: .doubleTap,
        )

        XCTAssertEqual(shortcut.validate(), .advancedRequiresSingleModifier)
    }

    func testAdvancedShortcutRejectsSideAgnosticModifier() {
        let shortcut = ShortcutDefinition(
            modifiers: [.command],
            primaryKey: nil,
            trigger: .doubleTap,
        )

        XCTAssertEqual(shortcut.validate(), .advancedRequiresSideSpecificModifier)
    }

    func testFunctionPrimaryKeyRangeValidation() {
        let valid = ShortcutPrimaryKey.function(index: 12, keyCode: 0x6f)
        let invalid = ShortcutPrimaryKey.function(index: 21, keyCode: 0x00)

        XCTAssertTrue(valid.isValid)
        XCTAssertFalse(invalid.isValid)
    }

    func testModifierlessFunctionShortcutIsValid() {
        let shortcut = ShortcutDefinition(
            modifiers: [],
            primaryKey: .function(index: 5, keyCode: 0x60),
            trigger: .singleTap,
        )

        XCTAssertEqual(shortcut.patternType, .simple)
        XCTAssertTrue(shortcut.isValid)
    }

    func testModifierlessLetterShortcutIsRejected() {
        let shortcut = ShortcutDefinition(
            modifiers: [],
            primaryKey: .letter("G", keyCode: 0x05),
            trigger: .singleTap,
        )

        XCTAssertEqual(shortcut.validate(), .missingModifiers)
    }

    func testGenericConflictServiceDetectsSameSignature() {
        let existing = ShortcutBinding(
            actionID: .assistant,
            actionDisplayName: "Assistant",
            shortcut: ShortcutDefinition(
                modifiers: [.leftCommand],
                primaryKey: .letter("G", keyCode: 0x05),
                trigger: .singleTap,
            ),
        )

        let candidate = ShortcutBinding(
            actionID: .meeting,
            actionDisplayName: "Meeting",
            shortcut: ShortcutDefinition(
                modifiers: [.leftCommand],
                primaryKey: .letter("G", keyCode: 0x05),
                trigger: .singleTap,
            ),
        )

        let conflict = ModifierShortcutConflictService.conflict(for: candidate, in: [existing])
        XCTAssertEqual(conflict?.conflicting.actionID, .assistant)
        XCTAssertEqual(conflict?.candidate.actionID, .meeting)
        XCTAssertEqual(conflict?.reason, .identicalSignature)
    }

    func testConflictServiceDetectsSideSpecificVsAgnosticOverlap() {
        let existing = ShortcutBinding(
            actionID: .assistant,
            actionDisplayName: "Assistant",
            shortcut: ShortcutDefinition(
                modifiers: [.command],
                primaryKey: .letter("G", keyCode: 0x05),
                trigger: .singleTap,
            ),
        )

        let candidate = ShortcutBinding(
            actionID: .meeting,
            actionDisplayName: "Meeting",
            shortcut: ShortcutDefinition(
                modifiers: [.leftCommand],
                primaryKey: .letter("G", keyCode: 0x05),
                trigger: .singleTap,
            ),
        )

        let conflict = ModifierShortcutConflictService.conflict(for: candidate, in: [existing])

        XCTAssertEqual(conflict?.reason, .sideSpecificVsAgnosticOverlap)
        XCTAssertEqual(conflict?.conflicting.actionID, .assistant)
    }

    func testConflictServiceDetectsAssistantIntegrationConcurrentActivation() {
        let existing = ShortcutBinding(
            actionID: .assistant,
            actionDisplayName: "Assistant",
            shortcut: ShortcutDefinition(
                modifiers: [.command],
                primaryKey: .letter("K", keyCode: 0x28),
                trigger: .singleTap,
            ),
        )

        let candidate = ShortcutBinding(
            actionID: .assistantIntegration(UUID()),
            actionDisplayName: "Raycast",
            shortcut: ShortcutDefinition(
                modifiers: [.leftCommand],
                primaryKey: .letter("K", keyCode: 0x28),
                trigger: .singleTap,
            ),
        )

        let conflict = ModifierShortcutConflictService.conflict(for: candidate, in: [existing])

        XCTAssertEqual(conflict?.reason, .assistantIntegrationConcurrentActivation)
        XCTAssertEqual(conflict?.conflicting.actionID, .assistant)
    }

    func testConflictServiceDetectsLayerLeaderKeyCollision() {
        let integrationID = UUID()
        let candidate = ShortcutBinding(
            actionID: .assistant,
            actionDisplayName: "Assistant",
            shortcut: ShortcutDefinition(
                modifiers: [.command],
                primaryKey: .letter("R", keyCode: 0x0f),
                trigger: .singleTap,
            ),
        )

        let context = ShortcutConflictContext(
            layerBindings: [
                ShortcutLayerBinding(
                    actionID: .assistantIntegration(integrationID),
                    actionDisplayName: "Raycast",
                    layerKey: "R",
                ),
            ],
        )

        let conflict = ModifierShortcutConflictService.conflict(
            for: candidate,
            in: [],
            context: context,
        )

        XCTAssertEqual(conflict?.reason, .layerLeaderKeyCollision(layerKey: "R"))
        XCTAssertEqual(conflict?.conflicting.actionID, .assistantIntegration(integrationID))
    }

    func testConflictServiceDoesNotReportConflictForOppositeSidesWithoutAgnostic() {
        let existing = ShortcutBinding(
            actionID: .assistant,
            actionDisplayName: "Assistant",
            shortcut: ShortcutDefinition(
                modifiers: [.leftCommand],
                primaryKey: .letter("U", keyCode: 0x20),
                trigger: .singleTap,
            ),
        )

        let candidate = ShortcutBinding(
            actionID: .meeting,
            actionDisplayName: "Meeting",
            shortcut: ShortcutDefinition(
                modifiers: [.rightCommand],
                primaryKey: .letter("U", keyCode: 0x20),
                trigger: .singleTap,
            ),
        )

        let conflict = ModifierShortcutConflictService.conflict(for: candidate, in: [existing])

        XCTAssertNil(conflict)
    }

    func testPrimaryKeyNormalizedTokenIncludesKeyCode() {
        let first = ShortcutPrimaryKey.letter("A", keyCode: 0x00)
        let second = ShortcutPrimaryKey.letter("A", keyCode: 0x32)

        XCTAssertNotEqual(first.normalizedToken, second.normalizedToken)
    }

    func testAssistantIntegrationDecodeRejectsModifierOnlySingleTapShortcut() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": UUID().uuidString,
            "name": "Legacy Integration",
            "kind": "deeplink",
            "isEnabled": true,
            "deepLink": "raycast://extensions/raycast/raycast-ai/ai-chat",
            "shortcutActivationMode": "holdOrToggle",
            "modifierShortcutGesture": [
                "keys": ["rightCommand"],
                "triggerMode": "singleTap",
            ],
        ])

        let decoded = try JSONDecoder().decode(AssistantIntegrationConfig.self, from: data)

        XCTAssertNil(decoded.shortcutDefinition)
    }

    @MainActor
    func testExecutionEngineSingleTapStartsWhenNotRecording() {
        let engine = ShortcutExecutionEngine()
        let actions = engine.handleDown(trigger: .singleTap, isRecording: false)
        XCTAssertEqual(actions, [.start])
    }

    @MainActor
    func testExecutionEngineSingleTapStopsWhenRecording() {
        let engine = ShortcutExecutionEngine()
        let actions = engine.handleDown(trigger: .singleTap, isRecording: true)
        XCTAssertEqual(actions, [.stop])
    }

    @MainActor
    func testExecutionEngineHoldStartsOnDownAndStopsOnUp() {
        let engine = ShortcutExecutionEngine()
        let downActions = engine.handleDown(trigger: .hold, isRecording: false)
        let upActions = engine.handleUp(trigger: .hold, isRecording: true)

        XCTAssertEqual(downActions, [.start])
        XCTAssertEqual(upActions, [.stop])
    }

    @MainActor
    func testExecutionEngineDoubleTapTogglesOnSecondRelease() {
        let engine = ShortcutExecutionEngine(doubleTapInterval: 1)
        _ = engine.handleUp(trigger: .doubleTap, isRecording: false)
        let secondTap = engine.handleUp(trigger: .doubleTap, isRecording: false)

        XCTAssertEqual(secondTap, [.start])
    }

    @MainActor
    func testShortcutEventRoutingOrchestratorRoutesInHouseDefinitionTransition() {
        let orchestrator = ShortcutEventRoutingOrchestrator()
        let configuration = ShortcutEventRoutingConfiguration(
            definition: ShortcutDefinition(
                modifiers: [.leftCommand],
                primaryKey: .letter("G", keyCode: 0x05),
                trigger: .singleTap,
            ),
            modifierGesture: nil,
            presetKey: .custom,
            presetRequiresModifierMonitoring: false,
            defaultActivationMode: .toggle,
            sources: ShortcutEventRoutingSources(
                inHouseDefinition: "in_house_definition",
                modifierGesture: "modifier_gesture",
                preset: "preset",
            ),
        )

        let result = orchestrator.routeMonitorEvent(
            configuration: configuration,
            mode: .allSources,
            wasPressed: false,
            isDefinitionActive: { _ in true },
            isModifierGestureActive: { _ in false },
            isPresetActive: { _ in false },
        )

        XCTAssertEqual(result.nextPressedState, true)
        XCTAssertEqual(
            result.outcomes,
            [
                .detected(source: "in_house_definition", trigger: .toggle),
                .dispatchDown(activationMode: .toggle),
            ],
        )
    }

    @MainActor
    func testShortcutEventRoutingOrchestratorIgnoresNonDefinitionSourcesWhenModeIsInHouseOnly() {
        let orchestrator = ShortcutEventRoutingOrchestrator()
        let configuration = ShortcutEventRoutingConfiguration(
            definition: nil,
            modifierGesture: ModifierShortcutGesture(keys: [.rightCommand], triggerMode: .hold),
            presetKey: .rightCommand,
            presetRequiresModifierMonitoring: true,
            defaultActivationMode: .toggle,
            sources: ShortcutEventRoutingSources(
                inHouseDefinition: "in_house_definition",
                modifierGesture: "modifier_gesture",
                preset: "preset",
            ),
        )

        let result = orchestrator.routeMonitorEvent(
            configuration: configuration,
            mode: .inHouseDefinitionOnly,
            wasPressed: false,
            isDefinitionActive: { _ in false },
            isModifierGestureActive: { _ in true },
            isPresetActive: { _ in true },
        )

        XCTAssertEqual(result, .none)
    }

    func testAssistantShortcutLayerStateMachineAllowsLeaderTapToArmFromIdle() {
        var machine = AssistantShortcutLayerStateMachine()

        let transition = machine.transition(on: .leaderTapped)

        XCTAssertTrue(transition.isValid)
        XCTAssertEqual(transition.from, .idle)
        XCTAssertEqual(transition.to, .armed)
        XCTAssertEqual(machine.state, .armed)
    }

    func testAssistantShortcutLayerStateMachineRejectsInvalidTransitionFromIdle() {
        var machine = AssistantShortcutLayerStateMachine()

        let transition = machine.transition(on: .layerKeyMatched)

        XCTAssertFalse(transition.isValid)
        XCTAssertEqual(transition.from, .idle)
        XCTAssertEqual(transition.to, .idle)
        XCTAssertEqual(machine.state, .idle)
    }

    func testAssistantShortcutLayerStateMachineConsumesLayerAfterMatch() {
        var machine = AssistantShortcutLayerStateMachine()
        _ = machine.transition(on: .leaderTapped)

        let transition = machine.transition(on: .layerKeyMatched)

        XCTAssertTrue(transition.isValid)
        XCTAssertEqual(transition.from, .armed)
        XCTAssertEqual(transition.to, .consumed)
        XCTAssertEqual(machine.state, .consumed)
    }

    func testAssistantShortcutLayerStateMachineTransitionsToTimedOut() {
        var machine = AssistantShortcutLayerStateMachine()
        _ = machine.transition(on: .leaderTapped)

        let transition = machine.transition(on: .timeoutElapsed)

        XCTAssertTrue(transition.isValid)
        XCTAssertEqual(transition.from, .armed)
        XCTAssertEqual(transition.to, .timedOut)
        XCTAssertEqual(machine.state, .timedOut)
    }

    func testAssistantShortcutLayerStateMachineTransitionsToCancelled() {
        var machine = AssistantShortcutLayerStateMachine()
        _ = machine.transition(on: .leaderTapped)

        let transition = machine.transition(on: .cancelledByEscapeOrBlur)

        XCTAssertTrue(transition.isValid)
        XCTAssertEqual(transition.from, .armed)
        XCTAssertEqual(transition.to, .cancelled)
        XCTAssertEqual(machine.state, .cancelled)
    }

    func testAssistantShortcutLayerStateMachineDisarmsExplicitlyFromTerminalStates() {
        var timedOutMachine = AssistantShortcutLayerStateMachine(initialState: .timedOut)
        let timedOutTransition = timedOutMachine.transition(on: .disarmedExplicitly)
        XCTAssertTrue(timedOutTransition.isValid)
        XCTAssertEqual(timedOutTransition.to, .idle)
        XCTAssertEqual(timedOutMachine.state, .idle)

        var consumedMachine = AssistantShortcutLayerStateMachine(initialState: .consumed)
        let consumedTransition = consumedMachine.transition(on: .disarmedExplicitly)
        XCTAssertTrue(consumedTransition.isValid)
        XCTAssertEqual(consumedTransition.to, .idle)
        XCTAssertEqual(consumedMachine.state, .idle)
    }

    func testShortcutTelemetryShortcutDetectedRecordUsesCanonicalPayload() {
        let record = ShortcutTelemetryEvent
            .shortcutDetected(
                pipeline: "assistant shortcuts",
                scope: "assistant",
                shortcutTarget: "assistant",
                source: "in-house/definition",
                trigger: "double tap",
            )
            .record

        XCTAssertEqual(record.name, .shortcutDetected)
        XCTAssertEqual(record.level, .info)
        XCTAssertEqual(record.payload["pipeline"], "assistant_shortcuts")
        XCTAssertEqual(record.payload["scope"], "assistant")
        XCTAssertEqual(record.payload["shortcut_target"], "assistant")
        XCTAssertEqual(record.payload["source"], "in-house_definition")
        XCTAssertEqual(record.payload["trigger"], "double_tap")
    }

    func testShortcutTelemetryLayerTimeoutRecordNormalizesNegativeTimeout() {
        let record = ShortcutTelemetryEvent
            .layerTimeout(
                pipeline: "assistant_shortcuts",
                scope: "assistant",
                source: "assistant_shortcut",
                timeoutMs: -80,
            )
            .record

        XCTAssertEqual(record.name, .layerTimeout)
        XCTAssertEqual(record.payload["layer_timeout_ms"], "0")
        XCTAssertEqual(record.payload["reason"], "timeout")
    }

    func testShortcutTelemetryCaptureHealthChangedRecordStoresStatusAndBackendFields() {
        let record = ShortcutTelemetryEvent
            .captureHealthChanged(
                pipeline: "global shortcuts",
                scope: "global",
                source: "refresh/event/monitors",
                result: "degraded",
                previousResult: "healthy",
                reason: "key_down_monitor_inactive",
                requiresGlobalCapture: true,
                accessibilityTrusted: true,
                flagsMonitorExpected: true,
                flagsMonitorActive: true,
                keyDownMonitorExpected: true,
                keyDownMonitorActive: false,
                keyUpMonitorExpected: false,
                keyUpMonitorActive: false,
                eventTapExpected: false,
                eventTapActive: false,
                checkedAtEpochMs: -20,
            )
            .record

        XCTAssertEqual(record.name, .captureHealthChanged)
        XCTAssertEqual(record.level, .warning)
        XCTAssertEqual(record.payload["pipeline"], "global_shortcuts")
        XCTAssertEqual(record.payload["source"], "refresh_event_monitors")
        XCTAssertEqual(record.payload["result"], "degraded")
        XCTAssertEqual(record.payload["previous_result"], "healthy")
        XCTAssertEqual(record.payload["reason"], "key_down_monitor_inactive")
        XCTAssertEqual(record.payload["requires_global_capture"], "true")
        XCTAssertEqual(record.payload["key_down_monitor_active"], "false")
        XCTAssertEqual(record.payload["checked_at_epoch_ms"], "0")
    }

    func testShortcutTelemetryCaptureHealthChangedRecordOmitsOptionalFieldsWhenMissing() {
        let record = ShortcutTelemetryEvent
            .captureHealthChanged(
                pipeline: "assistant_shortcuts",
                scope: "assistant",
                source: "periodic",
                result: "healthy",
                previousResult: nil,
                reason: nil,
                requiresGlobalCapture: true,
                accessibilityTrusted: true,
                flagsMonitorExpected: true,
                flagsMonitorActive: true,
                keyDownMonitorExpected: true,
                keyDownMonitorActive: true,
                keyUpMonitorExpected: false,
                keyUpMonitorActive: false,
                eventTapExpected: true,
                eventTapActive: true,
                checkedAtEpochMs: 1_234,
            )
            .record

        XCTAssertEqual(record.name, .captureHealthChanged)
        XCTAssertEqual(record.level, .info)
        XCTAssertEqual(record.payload["result"], "healthy")
        XCTAssertEqual(record.payload["event_tap_expected"], "true")
        XCTAssertEqual(record.payload["event_tap_active"], "true")
        XCTAssertNil(record.payload["previous_result"])
        XCTAssertNil(record.payload["reason"])
    }
}
