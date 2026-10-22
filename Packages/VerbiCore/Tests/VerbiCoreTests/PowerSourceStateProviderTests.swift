import IOKit.ps
@testable import VerbiCore
import XCTest

final class PowerSourceStateProviderTests: XCTestCase {
    func testResolvePowerSourceState_PrefersBatteryWhenAnyBatterySourceIsPresent() {
        let descriptions: [[String: Any]] = [
            [kIOPSPowerSourceStateKey as String: kIOPSACPowerValue],
            [kIOPSPowerSourceStateKey as String: kIOPSBatteryPowerValue],
        ]

        let state = PowerSourceStateProvider.resolvePowerSourceState(from: descriptions)

        XCTAssertEqual(state, .battery)
    }

    func testResolvePowerSourceState_ReturnsChargingWhenOnlyACSourcesExist() {
        let descriptions: [[String: Any]] = [
            [kIOPSPowerSourceStateKey as String: kIOPSACPowerValue],
        ]

        let state = PowerSourceStateProvider.resolvePowerSourceState(from: descriptions)

        XCTAssertEqual(state, .charging)
    }

    func testResolvePowerSourceState_ReturnsChargingWhenDescriptionsAreUnusable() {
        let descriptions: [[String: Any]] = [
            [:],
            [kIOPSPowerSourceStateKey as String: "Unknown"],
        ]

        let state = PowerSourceStateProvider.resolvePowerSourceState(from: descriptions)

        XCTAssertEqual(state, .charging)
    }
}
