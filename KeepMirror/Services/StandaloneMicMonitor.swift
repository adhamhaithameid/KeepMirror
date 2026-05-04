import AVFoundation
import AppKit
import Combine

// MARK: - StandaloneMicMonitor
//
// AVAudioEngine-based mic level monitor.
// Used by the Settings page (explicit start/stop) AND the mirror popover
// (always-on while permission is granted and micCheckEnabled).
//
// GAIN CALIBRATION:
//   Built-in MacBook mic RMS at normal speech ≈ 0.003 – 0.015 (Float32).
//   baseGain = 40 maps ~0.010 → 0.40, ~0.015 → 0.60 on-screen.
//   sensitivityMultiplier from MicSensitivity:
//     low    → 0.6   (effective 24×) — damps ambient noise
//     medium → 1.0   (effective 40×) — default
//     high   → 1.6   (effective 64×) — for quiet environments
//
//   OLD bug: rms * gain * 20.0 where gain was 3–10 → 60–200× total.
//   Silence-level noise hit 1.0, bars stayed red permanently. Fixed.

final class StandaloneMicMonitor: NSObject, ObservableObject, @unchecked Sendable {

    @MainActor @Published private(set) var level:     Float = 0
    @MainActor @Published private(set) var isRunning: Bool  = false

    private let engineQueue = DispatchQueue(
        label: "com.keepmirror.micmonitor.engine", qos: .userInteractive)
    private nonisolated(unsafe) var engine: AVAudioEngine?

    private nonisolated(unsafe) var smoothed: Float = 0
    private nonisolated(unsafe) var shouldBeRunning = false

    // Sensitivity multiplier — updated live without engine restart
    private nonisolated(unsafe) var sensitivityMultiplier: Float = 1.0
    private let baseGain: Float = 40.0

    // MARK: - Compat shim (no-op — AVAudioEngine ≠ AVCaptureSession conflict)
    @MainActor func observeMainSession(_ cameraManager: CameraManager) {}

    // MARK: - Public API

    /// Start monitoring. `gain` = MicSensitivity.sensitivityMultiplier (0.6 / 1.0 / 1.6).
    func start(micID: String = "", gain: Float = 1.0) {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        sensitivityMultiplier = gain
        shouldBeRunning = true
        engineQueue.async { [weak self] in self?.engineStart() }
    }

    /// Hot-update sensitivity without restarting — called when picker changes.
    func updateSensitivity(_ multiplier: Float) {
        sensitivityMultiplier = multiplier
    }

    func stop() {
        shouldBeRunning = false
        engineQueue.async { [weak self] in self?.engineStop(publishLevel: true) }
    }

    deinit {
        // Guarantee the AVAudioEngine is torn down even if stop() was never called.
        // This is the safety net for cases where the @StateObject is released
        // mid-animation (popover dealloc) or the hosting view is never destroyed
        // (notch panel reuse). Direct teardown is safe here — deinit owns all
        // resources and the engine queue tap closure already uses [weak self].
        shouldBeRunning = false
        if let eng = engine {
            eng.inputNode.removeTap(onBus: 0)
            eng.stop()
        }
        engine = nil
    }

    /// Call after permission is granted to kick the engine immediately.
    func recheckPermissionAndStart() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              shouldBeRunning else { return }
        engineQueue.async { [weak self] in self?.engineStart() }
    }

    // MARK: - Engine (engineQueue only)

    private func engineStart() {
        engineStop(publishLevel: false)

        let eng = AVAudioEngine()
        let input = eng.inputNode
        let hwFormat = input.inputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            Task { @MainActor in self.isRunning = false }
            return
        }

        // Reads sensitivityMultiplier live on each callback — no stale capture
        input.installTap(onBus: 0, bufferSize: 1024, format: hwFormat) { [weak self] buf, _ in
            self?.processPCMBuffer(buf)
        }

        do { try eng.start() } catch {
            input.removeTap(onBus: 0)
            Task { @MainActor in self.isRunning = false }
            return
        }

        engine  = eng
        smoothed = 0
        Task { @MainActor in self.isRunning = true }
    }

    private func engineStop(publishLevel: Bool) {
        if let eng = engine {
            eng.inputNode.removeTap(onBus: 0)
            eng.stop()
        }
        engine   = nil
        smoothed = 0
        if publishLevel {
            Task { @MainActor in self.level = 0; self.isRunning = false }
        }
    }

    // MARK: - PCM (AVAudioEngine render thread)

    private func processPCMBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let channelCount = Int(buffer.format.channelCount)
        var sumSq: Float = 0

        for ch in 0..<channelCount {
            let ptr = channelData[ch]
            for i in 0..<frameCount { let f = ptr[i]; sumSq += f * f }
        }

        let totalSamples = channelCount * frameCount
        guard totalSamples > 0 else { return }

        let rms = sqrt(sumSq / Float(totalSamples))
        // Single calibrated path — no stacking
        let raw = min(rms * baseGain * sensitivityMultiplier, 1.0)

        // Fast attack (0.20 weight on old), slow decay (0.85 weight)
        let alpha: Float = raw > smoothed ? 0.20 : 0.85
        smoothed = alpha * smoothed + (1.0 - alpha) * raw

        let published = min(smoothed, 1.0)
        Task { @MainActor in self.level = published }
    }
}
