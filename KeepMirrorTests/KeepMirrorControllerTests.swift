import XCTest
@testable import KeepMirror

@MainActor
final class KeepMirrorControllerTests: XCTestCase {
    func test_default_tab_is_settings() {
        let controller = makeController()

        XCTAssertEqual(controller.selectedTab, .settings)
    }

    func test_primary_click_starts_and_stops_the_default_duration() async {
        let sessionController = SessionControllerSpy()
        let controller = makeController(sessionController: sessionController)

        await controller.handlePrimaryClick()
        await controller.handlePrimaryClick()

        XCTAssertEqual(sessionController.startedDurations, [.minutes(15)])
        XCTAssertEqual(sessionController.stopCalls, 1)
    }

    func test_quick_activation_does_not_change_saved_default_duration() async {
        let sessionController = SessionControllerSpy()
        let controller = makeController(sessionController: sessionController)

        await controller.activate(duration: .hours(2))

        XCTAssertEqual(controller.settings.defaultDuration, .minutes(15))
        XCTAssertEqual(sessionController.startedDurations, [.hours(2)])
    }

    func test_launch_activates_default_duration_when_enabled() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let settings = AppSettings(store: defaults)
        settings.activateOnLaunch = true

        let sessionController = SessionControllerSpy()
        let controller = KeepMirrorController(
            settings: settings,
            sessionController: sessionController,
            windowManager: WindowManagerSpy(),
            launchAtLoginManager: LaunchAtLoginManagerSpy(),
            linkOpener: NoOpLinkOpener(),
            focusService: FocusDetectionService()
        )

        await controller.handleLaunch()

        XCTAssertEqual(sessionController.startedDurations, [.minutes(15)])
    }

    func test_first_launch_does_not_open_settings_window_implicitly() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let settings = AppSettings(store: defaults)
        let windowManager = WindowManagerSpy()

        let controller = KeepMirrorController(
            settings: settings,
            sessionController: SessionControllerSpy(),
            windowManager: windowManager,
            launchAtLoginManager: LaunchAtLoginManagerSpy(),
            linkOpener: NoOpLinkOpener(),
            focusService: FocusDetectionService()
        )

        await controller.handleLaunch()

        XCTAssertEqual(windowManager.openCalls, 0)
        XCTAssertEqual(windowManager.selectedTabs, [])
    }

    private func makeController(
        sessionController: SessionControllerSpy = SessionControllerSpy()
    ) -> KeepMirrorController {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = AppSettings(store: defaults)
        let windowManager = WindowManagerSpy()
        let loginManager = LaunchAtLoginManagerSpy()

        return KeepMirrorController(
            settings: settings,
            sessionController: sessionController,
            windowManager: windowManager,
            launchAtLoginManager: loginManager,
            linkOpener: NoOpLinkOpener(),
            focusService: FocusDetectionService()
        )
    }
}

private final class SessionControllerSpy: ActivationSessionManaging {
    var activeSession: ActivationSession?
    var lastStopReason: StopReason?
    var startedDurations: [ActivationDuration] = []
    var stopCalls = 0

    func start(duration: ActivationDuration, options: SessionOptions) async {
        startedDurations.append(duration)
        activeSession = ActivationSession(duration: duration, startedAt: .now, endsAt: nil, options: options)
    }

    func stop(reason: StopReason) async {
        stopCalls += 1
        lastStopReason = reason
        activeSession = nil
    }

    func deactivateSync() {
        stopCalls += 1
        lastStopReason = .appTermination
        activeSession = nil
    }
}

private final class WindowManagerSpy: SettingsWindowManaging {
    var openCalls = 0
    var selectedTabs: [AppTab] = []

    func show(selectedTab: AppTab) {
        openCalls += 1
        selectedTabs.append(selectedTab)
    }
}

private final class LaunchAtLoginManagerSpy: LaunchAtLoginManaging {
    var isEnabled = false
}
