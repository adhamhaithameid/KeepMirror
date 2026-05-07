import AVFoundation
import AppKit
import SwiftUI

// MARK: - CameraPreviewView

struct CameraPreviewView: NSViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> PreviewNSView {
        let v = PreviewNSView(); v.wantsLayer = true; v.layer = layer; return v
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        if nsView.layer !== layer { nsView.layer = layer }
        DispatchQueue.main.async { nsView.layer?.frame = nsView.bounds }
    }

    final class PreviewNSView: NSView {
        override func layout() { super.layout(); layer?.frame = bounds }
        override var isFlipped: Bool { false }
    }
}

// MARK: - MirrorPopoverView

// MARK: - Liquid Glass availability helper

private struct LiquidGlassCircleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}

private struct LiquidGlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

extension View {
    func liquidGlassCircle() -> some View { modifier(LiquidGlassCircleModifier()) }
    func liquidGlassCapsule() -> some View { modifier(LiquidGlassCapsuleModifier()) }
}

struct MirrorPopoverView: View {
    @ObservedObject var controller: MirrorController
    @ObservedObject var micMonitor: StandaloneMicMonitor
    let onClose: () -> Void

    @State private var flashOverlay     = false
    @State private var isCapturing      = false
    @State private var countdown: Int?  = nil
    @State private var permCheckTimer: Timer?
    @State private var controlsVisible  = false

    var body: some View {
        let sz = controller.settings.mirrorSize.popoverSize
        ZStack {
            // Glass base
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()

            // Camera feed (or permission prompt)
            cameraLayer.ignoresSafeArea()

            // White flash on capture
            if flashOverlay {
                Color.white.ignoresSafeArea()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            // Countdown number
            if let n = countdown { countdownView(n) }

            // ── Top hint — visible while hovering ────────────────────────────
            if controlsVisible && countdown == nil && !isCapturing {
                VStack {
                    captureHint
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .allowsHitTesting(false)
            }

            // ── Floating controls — appear on hover ───────────────────────────
            VStack(spacing: 0) {
                Spacer()
                HStack(alignment: .bottom, spacing: 0) {

                    // Left: mic orb
                    if controller.settings.micCheckEnabled {
                        PopoverMicBadge(
                            level: micMonitor.level,
                            permissionGranted: controller.cameraManager.micPermissionGranted
                        )
                        .padding(.leading, 10)
                        .onTapGesture { handleMicBadgeTap() }
                    }

                    Spacer()

                    // Right: settings gear
                    settingsButton
                        .padding(.trailing, 10)
                }
                .padding(.bottom, 10)
            }
            .opacity(controlsVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.22), value: controlsVisible)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.22)) { controlsVisible = hovering }
        }
        .frame(width: sz.width, height: sz.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { handleCaptureTrigger() }
        .background(SpaceKeyCapture { handleCaptureTrigger() })
        .onAppear {
            startPermCheckTimerIfNeeded()
            // Mic is started/stopped by StatusItemController — not here.
        }
        .onDisappear {
            permCheckTimer?.invalidate()
            permCheckTimer = nil
            // Camera and mic stop are handled by StatusItemController.closePopover()
            // as well, but keep camera stop as a fallback.
            controller.stopCamera()
        }
        .onChange(of: controller.cameraManager.micPermissionGranted) { granted in
            // Mic lifecycle is driven by StatusItemController; permission
            // changes are picked up on next open.
        }
        .onChange(of: controller.settings.micCheckEnabled) { enabled in
            if !enabled { micMonitor.stop() }
        }
    }

    // MARK: - Capture hint

    private var captureHint: some View {
        HStack(spacing: 5) {
            Image(systemName: "hand.tap")
                .font(.system(size: 10, weight: .medium))
            Text("Tap or Space to capture")
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .liquidGlassCapsule()
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        .padding(.top, 10)
    }

    // MARK: - Mic action

    private func handleMicBadgeTap() {
        if !controller.cameraManager.micPermissionGranted {
            Task {
                let granted = await controller.cameraManager.requestMicPermission()
                if !granted {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
            }
        }
    }

    // MARK: - Countdown

    private func countdownView(_ n: Int) -> some View {
        let color: Color = n > 1 ? .white : .green
        return ZStack {
            Circle()
                .fill(.clear)
                .frame(width: 100, height: 100)
                .liquidGlassCircle()
                .scaleEffect(1.0 + 0.15 * sin(Double(n) * .pi))
                .animation(.easeOut(duration: 0.4), value: n)
            Text("\(n)")
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.5), radius: 12)
                .scaleEffect(n == 1 ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: n)
        }
        .allowsHitTesting(false)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }

    // MARK: - Camera layer

    @ViewBuilder
    private var cameraLayer: some View {
        if controller.cameraManager.permissionGranted {
            CameraPreviewView(layer: controller.cameraManager.previewLayer)
        } else {
            permissionPrompt
        }
    }

    private var permissionPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("Camera Access Required").font(.system(size: 15, weight: .semibold))
            Text("System Settings → Privacy & Security → Camera\nEnable KeepMirror, then click the icon again.")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Settings button

    private var settingsButton: some View {
        Button {
            onClose()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { controller.openSettings() }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.90))
                .frame(width: 32, height: 32)
                .liquidGlassCircle()
                .shadow(color: .black.opacity(0.28), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .help("Open Settings")
    }

    // MARK: - Capture

    private func handleCaptureTrigger() {
        guard !isCapturing, countdown == nil else { return }
        let delay = controller.settings.captureCountdown.rawValue
        if delay > 0 { runCountdown(from: delay) } else { fireCapture() }
    }

    private func runCountdown(from seconds: Int) {
        func tick(_ n: Int) {
            guard n > 0 else { withAnimation { countdown = nil }; fireCapture(); return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { countdown = n }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { tick(n - 1) }
        }
        tick(seconds)
    }

    private func fireCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        if controller.settings.showCaptureFlash {
            withAnimation(.easeIn(duration: 0.04)) { flashOverlay = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeOut(duration: 0.2)) { flashOverlay = false }
            }
        }
        controller.capturePhoto()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isCapturing = false }
    }

    // MARK: - Permission re-check timer

    private func startPermCheckTimerIfNeeded() {
        guard !controller.cameraManager.permissionGranted else {
            if controller.settings.micCheckEnabled,
               !controller.cameraManager.micPermissionGranted {
                startMicPermCheckTimer()
            }
            return
        }
        permCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                controller.cameraManager.recheckCameraPermission()
                controller.cameraManager.recheckMicPermission()
                if controller.cameraManager.permissionGranted {
                    permCheckTimer?.invalidate()
                    permCheckTimer = nil
                    controller.startCamera()
                    // Mic start is owned by StatusItemController.openPopover() —
                    // it will be started on the next open once permission is granted.
                }
            }
        }
    }

    private func startMicPermCheckTimer() {
        permCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                controller.cameraManager.recheckMicPermission()
                if controller.cameraManager.micPermissionGranted {
                    permCheckTimer?.invalidate()
                    permCheckTimer = nil
                    // Mic start is owned by StatusItemController.openPopover().
                }
            }
        }
    }
}

// MARK: - PopoverMicBadge
//
// Premium liquid-glass mic orb:
//   • 5 concentric rings with angular-gradient halos (prismatic hue drift per ring)
//   • Bloom aura behind the badge that breathes with audio level
//   • Sonar-pulse transient ring fires on sharp audio spikes
//   • Badge body scales up slightly when loud (orb pump)
//   • Icon: mic.fill (silent) → waveform (active), colour-zoned mint → yellow → red
//   • Rich outer glow, lift shadow, idle breathing keeps it alive in silence

struct PopoverMicBadge: View {
    let level: Float
    let permissionGranted: Bool

    @State private var smoothed:    Float  = 0
    @State private var breathPhase: Double = 0
    @State private var prevSmoothed: Float = 0   // for transient detection
    @State private var pulseScale:  CGFloat = 1
    @State private var pulseOpacity: Double = 0

    private let orbSize: CGFloat = 32
    private let ringCount        = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
            ZStack {

                // ── 1. Bloom aura — large radial haze behind everything ──────
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                glowColor.opacity(Double(smoothed) * 0.38 + breathGlow * 0.6),
                                glowColor.opacity(Double(smoothed) * 0.08),
                                .clear
                            ],
                            center: .center,
                            startRadius: orbSize * 0.3,
                            endRadius:   orbSize * 1.8
                        )
                    )
                    .frame(width: orbSize * 3.6, height: orbSize * 3.6)
                    .blendMode(.screen)

                // ── 2. Sonar-pulse ring (transient flash) ────────────────────
                Circle()
                    .stroke(glowColor.opacity(pulseOpacity), lineWidth: 1.2)
                    .frame(width: orbSize, height: orbSize)
                    .scaleEffect(pulseScale)

                // ── 3. Ripple rings (5, angular-gradient halos) ─────────────
                ForEach(0 ..< ringCount, id: \.self) { i in
                    rippleRing(index: i)
                }

                // ── 4. Badge body — liquid glass ─────────────────────────────
                ZStack {
                    Circle()
                        .fill(.clear)
                        .frame(width: orbSize, height: orbSize)
                        .liquidGlassCircle()

                    // Level-reactive radial fill — colour floods up with level
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    glowColor.opacity(Double(smoothed) * 0.35 + 0.04),
                                    glowColor.opacity(Double(smoothed) * 0.08),
                                    .clear
                                ],
                                center: .init(x: 0.38, y: 0.28),
                                startRadius: 0,
                                endRadius: orbSize * 0.85
                            )
                        )
                        .frame(width: orbSize, height: orbSize)
                        .allowsHitTesting(false)
                }
                // Orb pump — badge inflates subtly on loud input
                .scaleEffect(1.0 + CGFloat(smoothed) * 0.07)
                .animation(.spring(response: 0.20, dampingFraction: 0.52), value: smoothed)

                // ── 5. Icon ───────────────────────────────────────────────────
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor)
                    .scaleEffect(
                        1.0
                        + CGFloat(smoothed) * 0.20
                        + CGFloat(sin(breathPhase)) * 0.028
                    )
                    .animation(.spring(response: 0.18, dampingFraction: 0.58), value: smoothed)
            }
            .frame(width: orbSize, height: orbSize)
            // Outer glow — richer colour, deeper radius when loud
            .shadow(
                color: glowColor.opacity(Double(smoothed) * 0.70 + breathGlow),
                radius: 10 + CGFloat(smoothed) * 16
            )
            // Steady lift shadow
            .shadow(color: .black.opacity(0.28), radius: 8, y: 4)
            .onChange(of: timeline.date) { _ in
                breathPhase += 0.042   // one cycle ≈ 2.5 s at 60 fps

                guard permissionGranted else {
                    smoothed     = max(0, smoothed - 0.04)
                    prevSmoothed = smoothed
                    return
                }

                let alpha: Float = level > smoothed ? 0.22 : 0.88
                let next = alpha * smoothed + (1.0 - alpha) * level

                // Detect sharp upward transient → fire sonar pulse
                let spike = next - prevSmoothed
                if spike > 0.18 && pulseOpacity < 0.1 {
                    fireSonarPulse()
                }
                prevSmoothed = smoothed
                smoothed     = next
            }
        }
    }

    // MARK: - Sonar pulse

    private func fireSonarPulse() {
        pulseScale   = 1.0
        pulseOpacity = 0.70
        withAnimation(.easeOut(duration: 0.65)) {
            pulseScale   = 2.8
            pulseOpacity = 0.0
        }
    }

    // MARK: - Ripple ring (enhanced — angular gradient halo)

    @ViewBuilder
    private func rippleRing(index: Int) -> some View {
        // Expansion: outer rings spread further
        let maxExp: CGFloat = CGFloat(index + 1) * 0.46
        let breathDelta     = CGFloat(sin(breathPhase + Double(index) * 2.1)) * 0.025
        let scale           = 1.0 + CGFloat(smoothed) * maxExp + breathDelta

        // Opacity: inner brightest, outer fades faster
        let baseOpacity = Double(smoothed) * (0.62 - Double(index) * 0.11)
        let idleOpacity = sin(breathPhase + Double(index) * 1.55) * 0.038 + (permissionGranted ? 0.038 : 0)
        let opacity     = max(0, baseOpacity + idleOpacity)

        // Stroke tapers on outer rings
        let strokeW: CGFloat = max(0.4, 2.2 - CGFloat(index) * 0.44)

        // Prismatic hue drift: each ring shifts hue slightly
        let hueDrift = Double(index) * 0.018
        let ringColor = driftedGlowColor(hueDrift: hueDrift)

        // Angular gradient gives each ring a rotating-halo shimmer
        Circle()
            .strokeBorder(
                AngularGradient(
                    colors: [
                        ringColor.opacity(opacity),
                        ringColor.opacity(opacity * 0.55),
                        ringColor.opacity(opacity * 0.10),
                        ringColor.opacity(opacity * 0.55),
                        ringColor.opacity(opacity)
                    ],
                    center: .center,
                    startAngle: .degrees(-90 + breathPhase * 4),  // slow rotation
                    endAngle:   .degrees(270 + breathPhase * 4)
                ),
                lineWidth: strokeW
            )
            .frame(width: orbSize, height: orbSize)
            .scaleEffect(scale)
            // Staggered spring: inner snappiest → outer softest
            .animation(
                .spring(response: 0.26 + Double(index) * 0.09, dampingFraction: 0.58),
                value: smoothed
            )
    }

    // MARK: - Derived values

    private var breathGlow: Double {
        guard permissionGranted else { return 0 }
        return (sin(breathPhase) * 0.5 + 0.5) * 0.07
    }

    private var iconName: String {
        if !permissionGranted { return "mic.slash.fill" }
        return smoothed > 0.03 ? "waveform" : "mic.fill"
    }

    private var iconColor: Color {
        if !permissionGranted { return .orange }
        if smoothed < 0.02 { return .white.opacity(0.55) }
        if smoothed < 0.55 { return mintColor(for: smoothed) }
        if smoothed < 0.82 { return .yellow }
        return .red
    }

    private var glowColor: Color {
        if !permissionGranted { return .orange }
        if smoothed < 0.55 { return Color(hue: 0.46, saturation: 0.72, brightness: 0.97) }
        if smoothed < 0.82 { return .yellow }
        return .red
    }

    /// Hue-shifted copy of glowColor for prismatic ring colouring
    private func driftedGlowColor(hueDrift: Double) -> Color {
        if !permissionGranted { return .orange }
        if smoothed < 0.55 {
            return Color(hue: 0.46 + hueDrift, saturation: 0.72, brightness: 0.97)
        }
        if smoothed < 0.82 { return Color(hue: 0.13 + hueDrift, saturation: 0.90, brightness: 1.0) }
        return Color(hue: 0.02 + hueDrift, saturation: 0.90, brightness: 1.0)
    }

    /// Smooth hue shift from cool mint (quiet) → warmer green (louder)
    private func mintColor(for level: Float) -> Color {
        let t = Double(level / 0.55)
        return Color(
            hue:        0.47 - t * 0.06,
            saturation: 0.55 + t * 0.25,
            brightness: 0.94
        )
    }
}
