import AppKit
import AVFoundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - MirrorSettingsTabView

struct MirrorSettingsTabView: View {
    @ObservedObject var controller: MirrorController
    @ObservedObject var settings: MirrorSettings
    @Binding var isHotkeyRecording: Bool

    @StateObject private var micMonitor = StandaloneMicMonitor()

    // Permission state (polled/refreshed on appear)
    @State private var cameraStatus: AVAuthorizationStatus = .notDetermined
    @State private var micStatus:    AVAuthorizationStatus = .notDetermined

    // Controls whether the Test Mic live meter is showing
    @State private var isTestingMic = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                privacySection           // ← NEW: always first
                mirrorSection
                captureSection
                micSection
                // Notch feature only exists on macOS 12+ (notch hardware debuted in 2021)
                if #available(macOS 12.0, *) {
                    if NotchHoverMonitor.currentMacHasNotch { notchSection }
                }
                generalSection
            }
            .padding(.vertical, 8)
        }
        .onAppear  { refreshPermissions() }
        .onDisappear {
            // Stop the test-mic monitor when leaving the settings page
            if isTestingMic { micMonitor.stop(); isTestingMic = false }
        }
        // When micCheckEnabled toggled off, stop any active test
        .onChange(of: settings.micCheckEnabled) { enabled in
            if !enabled && isTestingMic { micMonitor.stop(); isTestingMic = false }
        }
        // Live sensitivity update — no engine restart needed
        .onChange(of: settings.micSensitivity) { newVal in
            micMonitor.updateSensitivity(newVal.gain)
        }
        // Re-check permissions when user returns from System Settings
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Bundle.main.bundleIdentifier else { return }
            refreshPermissions()
        }
    }

    // MARK: - Permission helpers

    private func refreshPermissions() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        micStatus    = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    // MARK: - Mic monitor helpers

    /// Starts the test-mic monitor. Only called from the Test Mic button.
    private func startTestMic() {
        guard settings.micCheckEnabled else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        micMonitor.start(micID: settings.selectedMicID, gain: settings.micSensitivity.gain)
    }

    private func stopTestMic() {
        micMonitor.stop()
    }

    // MARK: - ── Privacy & Permissions ─────────────────────────────────────────

    private var privacySection: some View {
        SettingsSection(title: "Privacy & Permissions", icon: "lock.shield.fill", iconColor: .indigo) {

            PermissionRow(
                icon: "camera.fill",
                label: "Camera",
                detail: "Required to show your mirror.",
                status: cameraStatus
            ) {
                Task {
                    switch cameraStatus {
                    case .notDetermined:
                        _ = await controller.cameraManager.requestCameraPermission()
                        refreshPermissions()
                    default:
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                    }
                }
            }

            SettingsDivider()

            PermissionRow(
                icon: "mic.fill",
                label: "Microphone",
                detail: "Optional — powers the mic level meter.",
                status: micStatus
            ) {
                Task {
                    switch micStatus {
                    case .notDetermined:
                        let granted = await controller.cameraManager.requestMicPermission()
                        refreshPermissions()
                        if granted {
                            // Permission just granted — user can now click "Test Now" to verify
                            refreshPermissions()
                        }
                    default:
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                    }
                }
            }
        }
    }

    // MARK: - ── Mirror ────────────────────────────────────────────────────────

    private var mirrorSection: some View {
        SettingsSection(title: "Mirror", icon: "camera.viewfinder", iconColor: .blue) {

            SettingsRow(label: "Size", hint: "Controls the popover window dimensions.") {
                Picker("", selection: $settings.mirrorSize) {
                    ForEach(MirrorSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu).frame(width: 160)
                .accessibilityIdentifier("settings.mirrorSize")
            }

            SettingsDivider()

            if !controller.cameraManager.availableCameras.isEmpty {
                SettingsRow(label: "Camera", hint: "Which camera to use.") {
                    Picker("", selection: $settings.selectedCameraID) {
                        ForEach(controller.cameraManager.availableCameras) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.menu).frame(width: 160)
                    .accessibilityIdentifier("settings.camera")
                }
                SettingsDivider()
            }

            // Quality with "takes effect on next open" hint
            VStack(alignment: .leading, spacing: 2) {
                SettingsRow(label: "Quality", hint: "Higher quality uses more CPU and battery.") {
                    Picker("", selection: $settings.sessionQuality) {
                        ForEach(SessionPresetQuality.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu).frame(width: 160)
                    .accessibilityIdentifier("settings.quality")
                }
                Text("Takes effect the next time you open the mirror.")
                    .font(.system(size: 10))
                    .foregroundStyle(KeepMirrorPalette.mutedInk)
                    .padding(.bottom, 4)
            }

            SettingsDivider()

            SettingsToggleRow(
                label: "Flip Horizontally",
                detail: "Mirror the image left-to-right.",
                isOn: $settings.isFlipped,
                identifier: "settings.flip"
            )
            .onChange(of: settings.isFlipped) { _ in controller.applyFlipChange() }
        }
    }

    // MARK: - ── Capture ───────────────────────────────────────────────────────

    private var captureSection: some View {
        SettingsSection(title: "Capture", icon: "camera.on.rectangle.fill", iconColor: .purple) {

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save Location")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(KeepMirrorPalette.ink)
                    if settings.photoSaveBookmark == nil {
                        Text("Not set — will prompt on first capture")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    } else {
                        Text(settings.resolvedPhotoSaveURL.abbreviatedPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(KeepMirrorPalette.mutedInk)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    if settings.photoSaveBookmark != nil {
                        Button("Clear") { settings.photoSaveBookmark = nil }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .help("Reset — next capture will prompt for save location")
                            .accessibilityIdentifier("settings.clearFolder")
                    }
                    Button("Choose…") { chooseSaveFolder() }
                        .controlSize(.small)
                        .accessibilityIdentifier("settings.chooseFolder")
                }
            }
            .padding(.vertical, 8)


            SettingsDivider()

            SettingsRow(label: "Format", hint: "File format for saved photos.") {
                Picker("", selection: $settings.captureFormat) {
                    ForEach(CaptureFormat.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 140)
                .accessibilityIdentifier("settings.format")
            }

            SettingsDivider()

            SettingsRow(label: "Countdown", hint: "Wait before taking a photo.") {
                Picker("", selection: $settings.captureCountdown) {
                    ForEach(CaptureCountdown.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu).frame(width: 120)
                .accessibilityIdentifier("settings.countdown")
            }

            SettingsDivider()
            SettingsToggleRow(label: "Copy to Clipboard", detail: "Copy each photo to the clipboard.",           isOn: $settings.copyToClipboard,   identifier: "settings.clipboard")
            SettingsDivider()
            SettingsToggleRow(label: "Reveal in Finder",  detail: "Show the saved file in Finder after capture.", isOn: $settings.revealInFinder,    identifier: "settings.revealFinder")
            SettingsDivider()
            SettingsToggleRow(label: "Flash on Capture",  detail: "Show a white flash animation.",                isOn: $settings.showCaptureFlash,  identifier: "settings.flash")
        }
    }

    // MARK: - ── Mic Check ─────────────────────────────────────────────────────

    private var micSection: some View {
        SettingsSection(title: "Mic Check", icon: "waveform", iconColor: .green) {

            SettingsToggleRow(
                label: "Enable Mic Check",
                detail: "Show a live level meter in the mirror view.",
                isOn: micCheckBinding,
                identifier: "settings.micCheck"
            )

            if settings.micCheckEnabled {
                SettingsDivider()

                // Microphone device picker
                if !controller.cameraManager.availableMics.isEmpty {
                    SettingsRow(label: "Microphone", hint: "Audio input for level metering.") {
                        Picker("", selection: $settings.selectedMicID) {
                            ForEach(controller.cameraManager.availableMics) { Text($0.name).tag($0.id) }
                        }
                        .pickerStyle(.menu).frame(width: 160)
                        .accessibilityIdentifier("settings.mic")
                    }
                    SettingsDivider()
                }

                // Sensitivity — segmented picker; onChange calls updateSensitivity live
                // so the running engine reacts instantly without a restart.
                SettingsRow(label: "Sensitivity", hint: "How reactive the bars are to sound.") {
                    Picker("", selection: $settings.micSensitivity) {
                        Text("Low").tag(MicSensitivity.low)
                        Text("Medium").tag(MicSensitivity.medium)
                        Text("High").tag(MicSensitivity.high)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .accessibilityIdentifier("settings.micSensitivity")
                }

                SettingsDivider()

                // ── Test Mic section ───────────────────────────────────────────
                // Live meter only appears while the user is actively testing.
                // This avoids the mic light being permanently on while in settings.
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Test Mic")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(KeepMirrorPalette.ink)
                            Text("Verify your mic is working and sensitivity is correct.")
                                .font(.system(size: 11))
                                .foregroundStyle(KeepMirrorPalette.mutedInk)
                        }
                        Spacer()
                        Button(isTestingMic ? "Stop" : "Test Now") {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isTestingMic.toggle()
                            }
                            if isTestingMic {
                                startTestMic()
                            } else {
                                stopTestMic()
                            }
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .tint(isTestingMic ? .red : .accentColor)
                        .accessibilityIdentifier("settings.testMic")
                    }

                    if isTestingMic {
                        LiveMicMeter(
                            level: micMonitor.level,
                            isActive: micMonitor.isRunning
                        )
                        .frame(height: 32)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                    }
                }
                .padding(.vertical, 8)
                .animation(.easeInOut(duration: 0.18), value: isTestingMic)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: settings.micCheckEnabled)
    }

    // MARK: - ── Notch ─────────────────────────────────────────────────────────

    @ViewBuilder
    private var notchSection: some View {
        SettingsSection(title: "Notch", icon: "macbook", iconColor: .orange) {
            SettingsToggleRow(
                label: "Open Mirror from Notch",
                detail: "Hover near the top of your screen to reveal the mirror.",
                isOn: $settings.notchHoverEnabled,
                identifier: "settings.notchHover"
            )
            if settings.notchHoverEnabled {
                SettingsDivider()
                SettingsToggleRow(
                    label: "Hide Menu Bar Icon",
                    detail: "Hide the KeepMirror icon when notch mode is on.",
                    isOn: $settings.hideMenuBarIconWhenNotch,
                    identifier: "settings.hideIcon"
                )
            }
        }
        .animation(.easeInOut(duration: 0.18), value: settings.notchHoverEnabled)
    }

    // MARK: - ── General ───────────────────────────────────────────────────────

    private var generalSection: some View {
        SettingsSection(title: "General", icon: "gearshape.fill", iconColor: .gray) {
            SettingsToggleRow(
                label: "Start at Login",
                detail: "Launch KeepMirror automatically when you log in.",
                isOn: Binding(get: { controller.startAtLoginEnabled },
                              set: { controller.startAtLoginEnabled = $0 }),
                identifier: "settings.startAtLogin"
            )
            SettingsDivider()

            // Global shortcut recorder
            HotkeyRecorderRow(
                settings: settings,
                hotkeyManager: controller.hotkeyManager,
                isRecording: $isHotkeyRecording
            )

            SettingsDivider()
            HStack {
                Text("Version")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(KeepMirrorPalette.ink)
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    .font(.system(size: 12)).foregroundStyle(KeepMirrorPalette.mutedInk)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Mic permission binding

    private var micCheckBinding: Binding<Bool> {
        Binding(
            get: { settings.micCheckEnabled },
            set: { newValue in
                if newValue {
                    Task {
                        let granted = await controller.cameraManager.requestMicPermission()
                        refreshPermissions()
                        if granted {
                            settings.micCheckEnabled = true
                            // Monitor is started explicitly via "Test Now" button
                        } else if AVCaptureDevice.authorizationStatus(for: .audio) == .denied {
                            showMicDeniedAlert()
                        } else {
                            // .restricted or unknown — open settings
                            showMicDeniedAlert()
                        }
                    }
                } else {
                    settings.micCheckEnabled = false
                    micMonitor.stop()
                }
            }
        )
    }

    // MARK: - Helpers

    private func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "Choose"; panel.message = "Select where KeepMirror should save photos."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if let bm = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                settings.photoSaveBookmark = bm
            }
        }
    }

    private func showMicDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Microphone Access Denied"
        alert.informativeText = "Enable microphone access in System Settings → Privacy & Security → Microphone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }
}

// MARK: - PermissionRow

private struct PermissionRow: View {
    let icon:   String
    let label:  String
    let detail: String
    let status: AVAuthorizationStatus
    let onTap:  () -> Void

    private var statusColor: Color {
        switch status {
        case .authorized: return .green
        case .denied, .restricted: return .red
        default: return .orange
        }
    }

    private var statusLabel: String {
        switch status {
        case .authorized:   return "Granted"
        case .denied:       return "Denied"
        case .restricted:   return "Restricted"
        default:            return "Not Requested"
        }
    }

    private var buttonLabel: String {
        switch status {
        case .notDetermined: return "Grant Access"
        case .authorized:    return "Granted ✓"
        default:             return "Open Settings"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(statusColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KeepMirrorPalette.ink)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(KeepMirrorPalette.mutedInk)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .overlay { if status == .authorized { Circle().stroke(statusColor.opacity(0.3), lineWidth: 4).scaleEffect(1.5) } }

                Button(buttonLabel) { onTap() }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .tint(status == .authorized ? .green : .accentColor)
                    .disabled(status == .authorized)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - LiveMicMeter
// Horizontal fill-bar meter: green → yellow → red gradient.
// TimelineView at 30fps drives smoothing so the bar responds continuously
// even when the level float value stays constant between audio callbacks.

struct LiveMicMeter: View {
    let level:    Float
    let isActive: Bool

    @State private var smoothed: Float = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.07))

                    // Filled portion with gradient
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(meterGradient)
                        .frame(width: max(8, geo.size.width * CGFloat(smoothed)))
                        .animation(.easeOut(duration: 0.06), value: smoothed)

                    // Tick marks at 25% intervals
                    ForEach([0.25, 0.50, 0.75], id: \.self) { pos in
                        Rectangle()
                            .fill(Color.primary.opacity(0.18))
                            .frame(width: 1, height: geo.size.height * 0.55)
                            .offset(x: geo.size.width * pos - 0.5)
                    }

                    // Level % label (right-aligned inside bar area)
                    Text("\(Int(smoothed * 100))%")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(smoothed > 0.15 ? 0.85 : 0))
                        .padding(.leading, max(12, geo.size.width * CGFloat(smoothed) - 28))
                }
                // Advance smoothing on every 30fps tick
                .onChange(of: timeline.date) { _ in
                    guard isActive else { return }
                    let alpha: Float = level > smoothed ? 0.22 : 0.85
                    smoothed = alpha * smoothed + (1.0 - alpha) * level
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .onChange(of: isActive) { active in if !active { smoothed = 0 } }
    }

    private var meterGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .green,                   location: 0.00),
                .init(color: .green,                   location: 0.50),
                .init(color: .yellow,                  location: 0.72),
                .init(color: .red.opacity(0.85),       location: 1.00)
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }
}

// MARK: - SettingsSection

private struct SettingsSection<Content: View>: View {
    let title: String; let icon: String; let iconColor: Color
    @ViewBuilder let content: () -> Content


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(iconColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text(title)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(KeepMirrorPalette.mutedInk)
                    .textCase(.uppercase).kerning(0.4)
            }
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(KeepMirrorPalette.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(KeepMirrorPalette.border, lineWidth: 0.5)
                        }
                }
                .padding(.horizontal, 12)
        }
    }
}

// MARK: - SettingsRow

private struct SettingsRow<Control: View>: View {
    let label: String; let hint: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(KeepMirrorPalette.ink)
            Spacer()
            control()
        }
        .padding(.vertical, 8).help(hint)
    }
}

// MARK: - SettingsToggleRow

private struct SettingsToggleRow: View {
    let label: String; let detail: String
    @Binding var isOn: Bool; let identifier: String

    var body: some View {
        Button { withAnimation(.easeInOut(duration: 0.12)) { isOn.toggle() } } label: {
            HStack(alignment: .center, spacing: 10) {
                Toggle("", isOn: $isOn)
                    .toggleStyle(.switch).scaleEffect(0.8).labelsHidden().allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(KeepMirrorPalette.ink)
                    Text(detail).font(.system(size: 11)).foregroundStyle(KeepMirrorPalette.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .contentShape(Rectangle()).padding(.vertical, 7)
        }
        .buttonStyle(.plain).accessibilityIdentifier(identifier)
        .accessibilityLabel("\(label), \(isOn ? "on" : "off")")
    }
}

// MARK: - SettingsDivider

private struct SettingsDivider: View {
    var body: some View { Divider().padding(.leading, 38).opacity(0.5) }
}

// MARK: - SettingsMicMeter (kept for legacy reference — superseded by LiveMicWaveform)

struct SettingsMicMeter: View {
    let level: Float; let isActive: Bool
    private let segments = 16

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { i in
                let lit = isActive && level > Float(i) / Float(segments)
                RoundedRectangle(cornerRadius: 2).fill(lit ? segColor(i) : Color.primary.opacity(0.08))
                    .frame(width: 10, height: 14)
                    .animation(.easeOut(duration: lit ? 0.04 : 0.18), value: level)
            }
        }
        .padding(6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }

    private func segColor(_ i: Int) -> Color {
        let f = Float(i) / Float(segments)
        return f < 0.6 ? .green : f < 0.85 ? .yellow : .red
    }
}

// MARK: - URL helper

private extension URL {
    var abbreviatedPath: String { (path as NSString).abbreviatingWithTildeInPath }
}
