import AppKit
import Combine
import SwiftUI

// MARK: - StatusItemController

/// Manages the menu bar `NSStatusItem` and the `NSPopover` hosting `MirrorPopoverView`.
///
/// Camera lifecycle:
///   • Opens popover  →  camera starts immediately (before SwiftUI onAppear)
///   • Closes popover →  camera stops synchronously (green light off before animation)
///
/// This conforms to `NSPopoverDelegate` so that transient outside-clicks (which
/// NSPopover handles internally) also trigger the same camera-stop path.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {

    private let controller: MirrorController
    private let statusItem: NSStatusItem
    private var popover: NSPopover?
    private var cancellables: Set<AnyCancellable> = []

    // Mic monitor owned here — not inside the SwiftUI view — so we can call
    // stop() synchronously in closePopover/popoverWillClose without relying
    // on SwiftUI's onDisappear (which is non-deterministic for NSPopover).
    private let micMonitor = StandaloneMicMonitor()

    /// Lightweight watchdog: polls every 500ms for up to 2s after openPopover().
    /// If the session isn't running by then, it cycles it once to recover from
    /// hardware hiccups (common when the same camera was used by another app).
    private var watchdog: DispatchSourceTimer?

    init(controller: MirrorController) {
        self.controller = controller
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureButton()
        observeSettings()
        applyVisibility()
    }

    // MARK: - Button setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = handMirrorImage(active: false)
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "KeepMirror  (⌘⇧M to toggle)"
        button.target = self
        button.action = #selector(statusBarButtonClicked(_:))
        _ = button.sendAction(on: [.leftMouseDown, .rightMouseUp])
    }

    // MARK: - Menu bar icon

    /// Returns the appropriate menu bar icon.
    /// • Inactive → cam1 (white template, adapts to light/dark menu bar)
    /// • Active   → cam2 (original rendering — shows green / custom colour)
    /// Falls back to the legacy CoreGraphics drawing if the assets aren't bundled.
    private func handMirrorImage(active: Bool = false) -> NSImage {
        let assetName = active ? "MenuBarCam2" : "MenuBarCam1"

        if let img = NSImage(named: assetName) {
            // Clone so we can set per-use properties without mutating the cached asset
            let copy = img.copy() as! NSImage
            copy.size = NSSize(width: 18, height: 18)   // standard menu bar icon size
            copy.isTemplate = !active   // cam1 = template (tinted by OS), cam2 = original (green)
            copy.accessibilityDescription = active ? "KeepMirror (open)" : "KeepMirror"
            return copy
        }

        // ── Fallback: programmatic drawing (used if assets aren't in the bundle) ──
        let size = NSSize(width: 18, height: active ? 22 : 20)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)
            let faceD: CGFloat = 13
            let faceX = (rect.width - faceD) / 2
            let faceY = rect.height - faceD - 1 - (active ? 3 : 0)
            let faceRect = CGRect(x: faceX, y: faceY, width: faceD, height: faceD)
            ctx.fillEllipse(in: faceRect)
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: faceRect.insetBy(dx: 2.5, dy: 2.5))
            ctx.setBlendMode(.normal)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: faceRect.insetBy(dx: 1, dy: 1))
            let handleW: CGFloat = 3
            let handleH: CGFloat = active ? 5 : 7
            let handleY: CGFloat = active ? 3 : 0
            let handleRect = CGRect(x: (rect.width - handleW) / 2, y: handleY, width: handleW, height: handleH)
            let hp = NSBezierPath(roundedRect: handleRect, xRadius: 1.5, yRadius: 1.5)
            NSColor.black.setFill(); hp.fill()
            if active {
                let dotD: CGFloat = 4
                ctx.setFillColor(NSColor.systemGreen.cgColor)
                ctx.fillEllipse(in: CGRect(x: (rect.width - dotD) / 2, y: 0, width: dotD, height: dotD))
            }
            return true
        }
        image.isTemplate = !active
        image.accessibilityDescription = active ? "KeepMirror (open)" : "KeepMirror"
        return image
    }


    // MARK: - Settings observation

    private func observeSettings() {
        controller.settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyVisibility() }
            .store(in: &cancellables)
    }
    // MARK: - Visibility

    var isPopoverShown: Bool { popover?.isShown == true }

    private func applyVisibility() {
        let hide = controller.settings.notchHoverEnabled && controller.settings.hideMenuBarIconWhenNotch
        statusItem.isVisible = !hide
    }

    // MARK: - Click handler

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        switch event.type {
        case .rightMouseUp:
            showContextMenu()
        case .leftMouseDown where event.modifierFlags.contains(.control):
            showContextMenu()
        default:
            popover?.isShown == true ? closePopover() : openPopover()
        }
    }

    // MARK: - Popover open

    func openPopover() {
        if let existing = popover, existing.isShown { return }
        controller.startCamera()

        // Pre-warm: give the preview layer real dimensions before the popover
        // appears so there's no zero-size blank flash on first open.
        let sz = controller.settings.mirrorSize.popoverSize
        controller.cameraManager.previewLayer.frame = CGRect(origin: .zero, size: sz)

        let pop = buildPopover()
        self.popover = pop
        guard let button = statusItem.button else { return }
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.image = handMirrorImage(active: true)

        // Start watchdog: if camera isn't running after 2s, cycle it once.
        startWatchdog()

        // Start mic explicitly now that the popover is visible.
        startMicIfNeeded()
    }

    // MARK: - Popover close (also called from NSPopoverDelegate)

    func closePopover() {
        stopWatchdog()
        micMonitor.stop()
        controller.stopCamera()
        popover?.performClose(nil)
        popover = nil
        statusItem.button?.image = handMirrorImage(active: false)
    }

    func popoverWillClose(_ notification: Notification) {
        stopWatchdog()
        micMonitor.stop()
        if controller.cameraManager.isRunning { controller.stopCamera() }
        DispatchQueue.main.async { [weak self] in
            self?.popover = nil
            self?.statusItem.button?.image = self?.handMirrorImage(active: false)
        }
    }

    // MARK: - Mic helper

    private func startMicIfNeeded() {
        guard controller.settings.micCheckEnabled,
              controller.cameraManager.micPermissionGranted else { return }
        micMonitor.start(gain: controller.settings.micSensitivity.gain)
    }

    // MARK: - Camera watchdog

    private func startWatchdog() {
        stopWatchdog()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        var elapsed = 0
        let intervalMs = 500
        let timeoutMs  = 2000
        timer.schedule(deadline: .now() + .milliseconds(intervalMs),
                       repeating: .milliseconds(intervalMs))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            elapsed += intervalMs

            if self.controller.cameraManager.isRunning {
                // Camera is up — watchdog job done
                self.stopWatchdog()
                return
            }

            if elapsed >= timeoutMs {
                // Still not running after timeout — cycle once
                self.stopWatchdog()
                guard self.popover?.isShown == true else { return }
                self.controller.stopCamera()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    guard self.popover?.isShown == true else { return }
                    self.controller.startCamera()
                }
            }
        }
        timer.resume()
        watchdog = timer
    }

    private func stopWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    // MARK: - Popover builder

    private func buildPopover() -> NSPopover {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates  = true
        pop.delegate  = self

        let sz = controller.settings.mirrorSize.popoverSize
        let rootView = MirrorPopoverView(controller: controller, micMonitor: micMonitor) { [weak self] in
            self?.closePopover()
        }
        let hosting = NSHostingController(rootView: rootView)
        hosting.view.frame = NSRect(origin: .zero, size: sz)

        // Transparent hosting view so the NSPopover's own system material (liquid glass
        // on macOS 26, vibrancy on earlier versions) renders correctly behind our content.
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = .clear

        // macOS 26+: NSPopover renders liquid glass automatically when the view is transparent.
        // Earlier: .ultraThinMaterial in SwiftUI provides the vibrancy effect.
        if #available(macOS 26.0, *) {
            // System handles it — just ensure no opaque background blocks the effect
            pop.appearance = nil   // let the system choose
        }

        pop.contentViewController = hosting
        pop.contentSize = sz
        return pop
    }

    // MARK: - Context menu (right-click)

    private func showContextMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let mirrorItem = NSMenuItem(title: "Open Mirror", action: #selector(openMirrorFromMenu), keyEquivalent: "")
        mirrorItem.target = self
        mirrorItem.isEnabled = true
        mirrorItem.image = handMirrorImage()   // same hand-mirror template as status bar
        menu.addItem(mirrorItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.isEnabled = true
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit KeepMirror", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in self?.statusItem.menu = nil }
    }

    @objc private func openMirrorFromMenu()   { openPopover() }
    @objc private func openSettingsFromMenu() {
        closePopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.controller.openSettings()
        }
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
