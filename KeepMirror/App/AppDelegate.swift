import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: KeepMirrorAppEnvironment?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // LSUIElement = true in Info.plist keeps us accessory (no Dock icon).
        // No runtime activation policy change needed — doing both can race on macOS 26.
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = AppEnvironment.makeEnvironment()
        self.environment = env
        Task {
            await env.controller.handleLaunch()
            // Start notch monitor (it only fires callbacks when notchHoverEnabled == true)
            env.notchMonitor.start()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.notchMonitor.stop()
        environment?.controller.stopCamera()
    }
}
