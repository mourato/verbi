import Foundation
@testable import MeetingAssistantCoreAI
@testable import MeetingAssistantCoreInfrastructure
import XCTest

@MainActor
final class LocalModelResidencyCoordinatorTests: XCTestCase {
    func testEvaluateDoesNotUnloadWhenTimeoutIsNever() {
        let manager = MockLocalModelResidencyManager(
            residencyManagerID: "manager-a",
            managedLocalModelIDs: [LocalTranscriptionModel.parakeetTdt06BV3.rawValue],
            asrResident: true,
            diarizationResident: true,
            lastASRActivityAt: Date(timeIntervalSince1970: 0),
            lastDiarizationActivityAt: Date(timeIntervalSince1970: 0),
        )
        let settings = MockModelResidencySettings(timeout: .never)
        let coordinator = LocalModelResidencyCoordinator(
            modelManager: manager,
            settingsStore: settings,
            checkIntervalSeconds: 1,
        )

        coordinator.evaluateAndUnloadIfNeeded(now: Date(timeIntervalSince1970: 10_000))

        XCTAssertEqual(manager.asrUnloadAttempts, 0)
        XCTAssertEqual(manager.diarizationUnloadAttempts, 0)
    }

    func testEvaluateUnloadsBothModelsWhenInactivityThresholdIsExceeded() {
        let referenceDate = Date(timeIntervalSince1970: 1_000)
        let manager = MockLocalModelResidencyManager(
            residencyManagerID: "manager-a",
            managedLocalModelIDs: [LocalTranscriptionModel.parakeetTdt06BV3.rawValue],
            asrResident: true,
            diarizationResident: true,
            lastASRActivityAt: referenceDate,
            lastDiarizationActivityAt: referenceDate,
        )
        let settings = MockModelResidencySettings(timeout: .minutes5)
        let coordinator = LocalModelResidencyCoordinator(
            modelManager: manager,
            settingsStore: settings,
            checkIntervalSeconds: 1,
        )

        coordinator.evaluateAndUnloadIfNeeded(now: referenceDate.addingTimeInterval(5 * 60))

        XCTAssertEqual(manager.asrUnloadAttempts, 1)
        XCTAssertEqual(manager.diarizationUnloadAttempts, 1)
        XCTAssertFalse(manager.isASRResidentInMemory)
        XCTAssertFalse(manager.isDiarizationResidentInMemory)
    }

    func testEvaluateSkipsUnloadWhenModelsAreInUse() {
        let referenceDate = Date(timeIntervalSince1970: 1_000)
        let manager = MockLocalModelResidencyManager(
            residencyManagerID: "manager-a",
            managedLocalModelIDs: [LocalTranscriptionModel.parakeetTdt06BV3.rawValue],
            asrResident: true,
            diarizationResident: true,
            lastASRActivityAt: referenceDate,
            lastDiarizationActivityAt: referenceDate,
            isASRInUse: true,
            isDiarizationInUse: true,
        )
        let settings = MockModelResidencySettings(timeout: .minutes5)
        let coordinator = LocalModelResidencyCoordinator(
            modelManager: manager,
            settingsStore: settings,
            checkIntervalSeconds: 1,
        )

        coordinator.evaluateAndUnloadIfNeeded(now: referenceDate.addingTimeInterval(15 * 60))

        XCTAssertEqual(manager.asrUnloadAttempts, 0)
        XCTAssertEqual(manager.diarizationUnloadAttempts, 0)
    }

    func testEvaluateSkipsUnloadBeforeThreshold() {
        let referenceDate = Date(timeIntervalSince1970: 1_000)
        let manager = MockLocalModelResidencyManager(
            residencyManagerID: "manager-a",
            managedLocalModelIDs: [LocalTranscriptionModel.parakeetTdt06BV3.rawValue],
            asrResident: true,
            diarizationResident: true,
            lastASRActivityAt: referenceDate,
            lastDiarizationActivityAt: referenceDate,
        )
        let settings = MockModelResidencySettings(timeout: .minutes10)
        let coordinator = LocalModelResidencyCoordinator(
            modelManager: manager,
            settingsStore: settings,
            checkIntervalSeconds: 1,
        )

        coordinator.evaluateAndUnloadIfNeeded(now: referenceDate.addingTimeInterval(9 * 60))

        XCTAssertEqual(manager.asrUnloadAttempts, 0)
        XCTAssertEqual(manager.diarizationUnloadAttempts, 0)
    }

    func testIsResidencyManagedReturnsTrueWhenModelIDIsCoveredByAnyRegisteredManager() {
        let managerA = MockLocalModelResidencyManager(
            residencyManagerID: "manager-a",
            managedLocalModelIDs: [LocalTranscriptionModel.parakeetTdt06BV3.rawValue],
            asrResident: false,
            diarizationResident: false,
            lastASRActivityAt: nil,
            lastDiarizationActivityAt: nil,
        )
        let managerB = MockLocalModelResidencyManager(
            residencyManagerID: "manager-b",
            managedLocalModelIDs: ["other-local-model"],
            asrResident: false,
            diarizationResident: false,
            lastASRActivityAt: nil,
            lastDiarizationActivityAt: nil,
        )
        let settings = MockModelResidencySettings(timeout: .minutes5)
        let coordinator = LocalModelResidencyCoordinator(
            modelManagers: [managerA, managerB],
            settingsStore: settings,
            checkIntervalSeconds: 1,
        )

        XCTAssertTrue(
            coordinator.isResidencyManaged(localModelID: LocalTranscriptionModel.parakeetTdt06BV3.rawValue),
        )
        XCTAssertTrue(
            coordinator.isResidencyManaged(localModelID: "other-local-model"),
        )
    }

    func testIsResidencyManagedReturnsFalseWhenModelIDIsNotCovered() {
        let manager = MockLocalModelResidencyManager(
            residencyManagerID: "manager-a",
            managedLocalModelIDs: [LocalTranscriptionModel.parakeetTdt06BV3.rawValue],
            asrResident: false,
            diarizationResident: false,
            lastASRActivityAt: nil,
            lastDiarizationActivityAt: nil,
        )
        let settings = MockModelResidencySettings(timeout: .minutes5)
        let coordinator = LocalModelResidencyCoordinator(
            modelManagers: [manager],
            settingsStore: settings,
            checkIntervalSeconds: 1,
        )

        XCTAssertFalse(
            coordinator.isResidencyManaged(localModelID: "unmanaged-local-model"),
        )
    }

    func testPerformDictationIdleUnloadUnloadsASRAfterGraceWhenIdle() async {
        let referenceDate = Date(timeIntervalSince1970: 1_000)
        let manager = MockLocalModelResidencyManager(
            residencyManagerID: "manager-a",
            managedLocalModelIDs: [LocalTranscriptionModel.parakeetTdt06BV3.rawValue],
            asrResident: true,
            diarizationResident: true,
            lastASRActivityAt: referenceDate,
            lastDiarizationActivityAt: referenceDate,
        )
        let settings = MockModelResidencySettings(timeout: .minutes30)
        let coordinator = LocalModelResidencyCoordinator(
            modelManager: manager,
            settingsStore: settings,
            checkIntervalSeconds: 1,
        )

        await coordinator.performDictationIdleUnloadIfEligible(
            now: referenceDate.addingTimeInterval(120),
            grace: 120,
        )

        XCTAssertEqual(manager.asrUnloadAttempts, 1)
        XCTAssertEqual(manager.diarizationUnloadAttempts, 0)
        XCTAssertFalse(manager.isASRResidentInMemory)
        XCTAssertTrue(manager.isDiarizationResidentInMemory)
    }

    func testPerformDictationIdleUnloadSkipsWhenASRIsInUse() async {
        let referenceDate = Date(timeIntervalSince1970: 1_000)
        let manager = MockLocalModelResidencyManager(
            residencyManagerID: "manager-a",
            managedLocalModelIDs: [LocalTranscriptionModel.parakeetTdt06BV3.rawValue],
            asrResident: true,
            diarizationResident: true,
            lastASRActivityAt: referenceDate,
            lastDiarizationActivityAt: referenceDate,
            isASRInUse: true,
        )
        let settings = MockModelResidencySettings(timeout: .minutes30)
        let coordinator = LocalModelResidencyCoordinator(
            modelManager: manager,
            settingsStore: settings,
            checkIntervalSeconds: 1,
        )

        await coordinator.performDictationIdleUnloadIfEligible(
            now: referenceDate.addingTimeInterval(120),
            grace: 120,
        )

        XCTAssertEqual(manager.asrUnloadAttempts, 0)
    }

    func testPerformDictationIdleUnloadSkipsWhenMeetingCaptureIsActive() async {
        let referenceDate = Date(timeIntervalSince1970: 1_000)
        let manager = MockLocalModelResidencyManager(
            residencyManagerID: "manager-a",
            managedLocalModelIDs: [LocalTranscriptionModel.parakeetTdt06BV3.rawValue],
            asrResident: true,
            diarizationResident: false,
            lastASRActivityAt: referenceDate,
            lastDiarizationActivityAt: nil,
        )
        let settings = MockModelResidencySettings(timeout: .minutes30)
        let coordinator = LocalModelResidencyCoordinator(
            modelManager: manager,
            settingsStore: settings,
            checkIntervalSeconds: 1,
        )

        await coordinator.performDictationIdleUnloadIfEligible(
            now: referenceDate.addingTimeInterval(120),
            grace: 120,
            isMeetingCaptureActive: { true },
        )

        XCTAssertEqual(manager.asrUnloadAttempts, 0)
    }

    func testScheduleDictationIdleUnloadDoesNothingWhenTimeoutIsNever() async {
        let manager = MockLocalModelResidencyManager(
            residencyManagerID: "manager-a",
            managedLocalModelIDs: [LocalTranscriptionModel.parakeetTdt06BV3.rawValue],
            asrResident: true,
            diarizationResident: false,
            lastASRActivityAt: Date(timeIntervalSince1970: 0),
            lastDiarizationActivityAt: nil,
        )
        let settings = MockModelResidencySettings(timeout: .never)
        let coordinator = LocalModelResidencyCoordinator(
            modelManager: manager,
            settingsStore: settings,
            checkIntervalSeconds: 1,
        )

        coordinator.scheduleDictationIdleUnload(grace: 0.01)

        XCTAssertEqual(manager.asrUnloadAttempts, 0)
    }

    func testScheduleDictationIdleUnloadSkipsWhenGraceExceedsGlobalTimeout() async {
        let referenceDate = Date(timeIntervalSince1970: 1_000)
        let manager = MockLocalModelResidencyManager(
            residencyManagerID: "manager-a",
            managedLocalModelIDs: [LocalTranscriptionModel.parakeetTdt06BV3.rawValue],
            asrResident: true,
            diarizationResident: false,
            lastASRActivityAt: referenceDate,
            lastDiarizationActivityAt: nil,
        )
        let settings = MockModelResidencySettings(timeout: .minutes5)
        let coordinator = LocalModelResidencyCoordinator(
            modelManager: manager,
            settingsStore: settings,
            checkIntervalSeconds: 1,
        )

        coordinator.scheduleDictationIdleUnload(grace: 400)

        XCTAssertEqual(manager.asrUnloadAttempts, 0)
    }

    func testNoteASRActivityCancelsPendingDictationIdleUnload() async {
        let referenceDate = Date(timeIntervalSince1970: 1_000)
        let manager = MockLocalModelResidencyManager(
            residencyManagerID: "manager-a",
            managedLocalModelIDs: [LocalTranscriptionModel.parakeetTdt06BV3.rawValue],
            asrResident: true,
            diarizationResident: false,
            lastASRActivityAt: referenceDate,
            lastDiarizationActivityAt: nil,
        )
        let settings = MockModelResidencySettings(timeout: .minutes30)
        let coordinator = LocalModelResidencyCoordinator(
            modelManager: manager,
            settingsStore: settings,
            checkIntervalSeconds: 1,
        )

        // No suspension between schedule and cancel: cancellation always lands
        // before the grace elapses, and the task's guard bars the unload.
        coordinator.scheduleDictationIdleUnload(grace: 0.05)
        coordinator.noteASRActivity()

        XCTAssertEqual(manager.asrUnloadAttempts, 0)
    }

    func testPerformDictationIdleUnloadSkipsWhenIdleDurationIsShorterThanGrace() async {
        let referenceDate = Date(timeIntervalSince1970: 1_000)
        let manager = MockLocalModelResidencyManager(
            residencyManagerID: "manager-a",
            managedLocalModelIDs: [LocalTranscriptionModel.parakeetTdt06BV3.rawValue],
            asrResident: true,
            diarizationResident: false,
            lastASRActivityAt: referenceDate.addingTimeInterval(60),
            lastDiarizationActivityAt: nil,
        )
        let settings = MockModelResidencySettings(timeout: .minutes30)
        let coordinator = LocalModelResidencyCoordinator(
            modelManager: manager,
            settingsStore: settings,
            checkIntervalSeconds: 1,
        )

        await coordinator.performDictationIdleUnloadIfEligible(
            now: referenceDate.addingTimeInterval(120),
            grace: 120,
        )

        XCTAssertEqual(manager.asrUnloadAttempts, 0)
    }
}

@MainActor
private final class MockModelResidencySettings: ModelResidencyTimeoutSettingsProviding {
    var modelResidencyTimeout: AppSettingsStore.ModelResidencyTimeoutOption

    init(timeout: AppSettingsStore.ModelResidencyTimeoutOption) {
        modelResidencyTimeout = timeout
    }
}

@MainActor
private final class MockLocalModelResidencyManager: LocalModelResidencyManaging {
    let residencyManagerID: String
    let managedLocalModelIDs: Set<String>
    var lastASRActivityAt: Date?
    var lastDiarizationActivityAt: Date?
    var isASRInUse: Bool
    var isDiarizationInUse: Bool
    var isASRResidentInMemory: Bool
    var isDiarizationResidentInMemory: Bool

    private(set) var asrUnloadAttempts = 0
    private(set) var diarizationUnloadAttempts = 0

    init(
        residencyManagerID: String,
        managedLocalModelIDs: Set<String>,
        asrResident: Bool,
        diarizationResident: Bool,
        lastASRActivityAt: Date?,
        lastDiarizationActivityAt: Date?,
        isASRInUse: Bool = false,
        isDiarizationInUse: Bool = false,
    ) {
        self.residencyManagerID = residencyManagerID
        self.managedLocalModelIDs = managedLocalModelIDs
        isASRResidentInMemory = asrResident
        isDiarizationResidentInMemory = diarizationResident
        self.lastASRActivityAt = lastASRActivityAt
        self.lastDiarizationActivityAt = lastDiarizationActivityAt
        self.isASRInUse = isASRInUse
        self.isDiarizationInUse = isDiarizationInUse
    }

    @discardableResult
    func unloadASRFromMemoryIfPossible() -> Bool {
        asrUnloadAttempts += 1
        guard isASRResidentInMemory else { return false }
        isASRResidentInMemory = false
        return true
    }

    @discardableResult
    func unloadDiarizationFromMemoryIfPossible() -> Bool {
        diarizationUnloadAttempts += 1
        guard isDiarizationResidentInMemory else { return false }
        isDiarizationResidentInMemory = false
        return true
    }
}
