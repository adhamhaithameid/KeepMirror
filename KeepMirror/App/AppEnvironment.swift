import AppKit
import SwiftUI

// MARK: - KeepMirrorAppEnvironment

@MainActor
final class KeepMirrorAppEnvironment {
    let controller: MirrorController
    let settingsWindowManager: SettingsWindowManager
    let statusItemController: StatusItemController
    let notchMonitor: NotchHoverMonitor
    let notchPanelController: NotchPanelController
    let hotkeyManager: GlobalHotkeyManager

    init(
        controller: MirrorController,
        settingsWindowManager: SettingsWindowManager,
        statusItemController: StatusItemController,
        notchMonitor: NotchHoverMonitor,
        notchPanelController: NotchPanelController,
        hotkeyManager: GlobalHotkeyManager
    ) {
        self.controller = controller
        self.settingsWindowManager = settingsWindowManager
        self.statusItemController = statusItemController
        self.notchMonitor = notchMonitor
        self.notchPanelController = notchPanelController
        self.hotkeyManager = hotkeyManager
    }
}

// MARK: - AppEnvironment factory

enum AppEnvironment {
    @MainActor
    static func makeEnvironment() -> KeepMirrorAppEnvironment {
        let settings = MirrorSettings()
        let cameraManager = CameraManager()
        let launchAtLoginManager = LiveLaunchAtLoginManager()
        let linkOpener = WorkspaceLinkOpener()

        let bridgeWindowManager = BridgeSettingsWindowManager()

        let controller = MirrorController(
            settings: settings,
            cameraManager: cameraManager,
            windowManager: bridgeWindowManager,
            launchAtLoginManager: launchAtLoginManager,
            linkOpener: linkOpener
        )

        let settingsWindowManager = SettingsWindowManager {
            SettingsWindowView(controller: controller)
        }
        bridgeWindowManager.base = settingsWindowManager

        let statusItemController = StatusItemController(controller: controller)

        let notchMonitor = NotchHoverMonitor()
        let notchPanelController = NotchPanelController(controller: controller)

        // Wire notch hover callbacks
        notchMonitor.onEnterNotch = { [weak notchPanelController, weak controller] in
            guard let controller, controller.settings.notchHoverEnabled else { return }
            notchPanelController?.show()
        }
        notchMonitor.onLeaveNotch = { [weak notchPanelController, weak controller] in
            guard let controller, controller.settings.notchHoverEnabled else { return }
            notchPanelController?.hide()
        }

        let hotkeyManager = GlobalHotkeyManager {
            if statusItemController.isPopoverShown {
                statusItemController.closePopover()
            } else {
                statusItemController.openPopover()
            }
        }

        // Seed hotkey from saved settings (may differ from default ⌘⇧M)
        hotkeyManager.reconfigure(
            keyCode:   settings.hotkeyKeyCode,
            modifiers: settings.hotkeyModifiers
        )

        // Inject into controller so settings view can drive reconfiguration
        controller.hotkeyManager = hotkeyManager

        return KeepMirrorAppEnvironment(
            controller: controller,
            settingsWindowManager: settingsWindowManager,
            statusItemController: statusItemController,
            notchMonitor: notchMonitor,
            notchPanelController: notchPanelController,
            hotkeyManager: hotkeyManager
        )
    }
}

// MARK: - BridgeSettingsWindowManager

@MainActor
private final class BridgeSettingsWindowManager: SettingsWindowManaging {
    var base: SettingsWindowManaging?
    func show(selectedTab: AppTab) { base?.show(selectedTab: selectedTab) }
}
