import AppKit
import SwiftUI

// MARK: - NotchMirrorView

/// Compact camera preview used inside the notch panel.
/// The mic monitor is injected by NotchPanelController so that its lifecycle
/// is driven by show()/hide() rather than SwiftUI's onDisappear (which never
/// fires on a reused NSPanel's hosting view).
private struct NotchMirrorView: View {
    @ObservedObject var controller: MirrorController
    @ObservedObject var micMonitor: StandaloneMicMonitor

    @State private var flashOverlay = false
    @State private var isCapturing  = false

    private var micEnabled: Bool { controller.settings.micCheckEnabled }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()

            if controller.cameraManager.permissionGranted {
                CameraPreviewView(layer: controller.cameraManager.previewLayer)
                    .ignoresSafeArea()
            }

            if flashOverlay {
                Color.white.ignoresSafeArea().transition(.opacity)
            }

            if micEnabled {
                VStack {
                    Spacer()
                    HStack {
                        PopoverMicBadge(
                            level: micMonitor.level,
                            permissionGranted: controller.cameraManager.micPermissionGranted
                        )
                        .padding(8)
                        .onTapGesture {
                            if !controller.cameraManager.micPermissionGranted {
                                Task {
                                    let granted = await controller.cameraManager.requestMicPermission()
                                    if !granted {
                                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                }
            }

            SpaceKeyCapture { triggerCapture() }
                .frame(width: 0, height: 0)
        }
        .onTapGesture { triggerCapture() }
        .onAppear {
            controller.startCamera()
            // Mic is started/stopped by NotchPanelController — not here.
        }
        .onDisappear {
            // Camera stop is handled by NotchPanelController.hide() as well,
            // but keep this as a fallback for unexpected SwiftUI teardown.
            controller.stopCamera()
        }
        .onChange(of: controller.cameraManager.micPermissionGranted) { granted in
            // Notify panel controller indirectly — mic start is owned by the panel.
        }
    }

    private func triggerCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        withAnimation(.easeIn(duration: 0.05)) { flashOverlay = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.25)) { flashOverlay = false }
        }
        controller.capturePhoto()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isCapturing = false }
    }
}


// MARK: - SpaceKeyCapture (shared helper)

struct SpaceKeyCapture: NSViewRepresentable {
    let onSpace: () -> Void

    func makeNSView(context: Context) -> SpaceNSView {
        let v = SpaceNSView()
        v.onSpace = onSpace
        return v
    }
    func updateNSView(_ nsView: SpaceNSView, context: Context) {
        nsView.onSpace = onSpace
    }

    final class SpaceNSView: NSView {
        var onSpace: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 49 { onSpace?() } else { super.keyDown(with: event) }
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }
    }
}

// MARK: - NotchPanelController

/// Manages a borderless, non-activating `NSPanel` that floats just below
/// the macOS notch area. It appears with a fade + subtle upward settle when
/// the cursor enters the notch zone, and fades out on leave.
@MainActor
final class NotchPanelController {

    private var panel: NSPanel?
    private let controller: MirrorController

    // Mic monitor owned here — not inside the SwiftUI view — so we can call
    // stop() synchronously in hide() without relying on onDisappear.
    private let micMonitor = StandaloneMicMonitor()

    // Fixed dimensions for the notch floating panel
    private let panelWidth: CGFloat  = 300
    private let panelHeight: CGFloat = 220
    private let cornerRadius: CGFloat = 16

    private var isVisible = false

    init(controller: MirrorController) {
        self.controller = controller
    }

    // MARK: - Show / Hide

    /// Float the panel just below the notch with a fade + settle animation.
    func show() {
        guard !isVisible else { return }
        guard let screen = notchScreen else { return }
        isVisible = true

        if panel == nil { buildPanel() }
        guard let panel else { return }

        let target = panelOrigin(screen: screen)
        // Start 8 pt higher — slight upward drift during the fade-in
        let startOrigin = NSPoint(x: target.x, y: target.y + 8)

        panel.setFrameOrigin(startOrigin)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(target)
            panel.animator().alphaValue = 1
        }

        // Start mic explicitly now that the panel is visible.
        startMicIfNeeded()
    }

    /// Fade the panel out, stop mic immediately, hide it, stop camera.
    func hide() {
        guard isVisible, let panel else { return }
        isVisible = false

        // Stop mic immediately — do NOT wait for the animation or onDisappear
        // (onDisappear never fires on a reused NSPanel's hosting view).
        micMonitor.stop()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }) {
            Task { @MainActor [weak self, weak panel] in
                panel?.orderOut(nil)
                self?.controller.stopCamera()
            }
        }
    }

    // MARK: - Mic helper

    private func startMicIfNeeded() {
        guard controller.settings.micCheckEnabled,
              controller.cameraManager.micPermissionGranted else { return }
        micMonitor.start(gain: controller.settings.micSensitivity.gain)
    }

    // MARK: - Panel construction

    private func buildPanel() {
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: panelWidth, height: panelHeight)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovable = false
        p.isFloatingPanel = true

        // Inject the controller-owned micMonitor so NotchMirrorView doesn't
        // create its own @StateObject that would outlive the panel visibility.
        let mirrorView = NotchMirrorView(controller: controller, micMonitor: micMonitor)
        let hosting = NSHostingView(rootView: mirrorView)
        hosting.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = cornerRadius
        hosting.layer?.masksToBounds = true

        p.contentView = hosting
        p.setContentSize(NSSize(width: panelWidth, height: panelHeight))
        self.panel = p
    }

    // MARK: - Geometry

    private var notchScreen: NSScreen? {
        NSScreen.screens.first(where: \.hasNotch)
    }

    /// Position: centred horizontally on screen, floating 6 pt below the notch.
    private func panelOrigin(screen: NSScreen) -> NSPoint {
        let x = screen.frame.midX - panelWidth / 2
        let notchBottom: CGFloat
        if #available(macOS 12.0, *) {
            notchBottom = screen.frame.maxY - screen.safeAreaInsets.top
        } else {
            notchBottom = screen.frame.maxY - 28
        }
        // Float 6 pt below the bottom edge of the notch
        let y = notchBottom - panelHeight - 6
        return NSPoint(x: x, y: y)
    }
}
