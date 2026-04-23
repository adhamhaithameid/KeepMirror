import XCTest
@testable import KeepMirror

@MainActor
final class ActivationSessionControllerTests: XCTestCase {
    func test_starting_a_duration_replaces_the_existing_session() async {
        let assertions = WakeAssertionControllerSpy()
        let provider = StubPowerStatusProvider()
        let controller = ActivationSessionController(assertions: assertions, powerStatusProvider: provider)

        await controller.start(duration: .minutes(15), options: .default)
        await controller.start(duration: .hours(1), options: .default)

        XCTAssertEqual(assertions.activations.map(\.allowDisplaySleep), [false, false])
        XCTAssertEqual(controller.activeSession?.duration, .hours(1))
    }

    func test_low_power_mode_rule_stops_the_session() async {
        let assertions = WakeAssertionControllerSpy()
        let provider = StubPowerStatusProvider(snapshot: PowerSnapshot(batteryLevel: 82, isLowPowerModeEnabled: true))
        let controller = ActivationSessionController(assertions: assertions, powerStatusProvider: provider)

        await controller.start(
            duration: .minutes(30),
            options: SessionOptions(
                allowDisplaySleep: false,
                allowPowerNap: false,
                batteryThreshold: nil,
                stopOnLowPowerMode: true
            )
        )

        XCTAssertNil(controller.activeSession)
        XCTAssertEqual(controller.lastStopReason, .lowPowerMode)
    }

    func test_allow_display_sleep_passes_flag_to_assertions() async {
        let assertions = WakeAssertionControllerSpy()
        let provider = StubPowerStatusProvider()
        let controller = ActivationSessionController(assertions: assertions, powerStatusProvider: provider)

        await controller.start(
            duration: .hours(1),
            options: SessionOptions(
                allowDisplaySleep: true,
                allowPowerNap: false,
                batteryThreshold: nil,
                stopOnLowPowerMode: false
            )
        )

        XCTAssertEqual(assertions.activations.map(\.allowDisplaySleep), [true])
    }
}

private final class WakeAssertionControllerSpy: WakeAssertionControlling {
    var activations: [(allowDisplaySleep: Bool, allowPowerNap: Bool)] = []
    var deactivateCalls = 0

    func activate(allowDisplaySleep: Bool, allowPowerNap: Bool) throws {
        activations.append((allowDisplaySleep: allowDisplaySleep, allowPowerNap: allowPowerNap))
    }

    func deactivate() {
        deactivateCalls += 1
    }
}

private struct StubPowerStatusProvider: PowerStatusProviding {
    var snapshot: PowerSnapshot = PowerSnapshot(batteryLevel: 100, isLowPowerModeEnabled: false)

    func currentSnapshot() -> PowerSnapshot {
        snapshot
    }
}
