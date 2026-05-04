import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - HotkeyRecorderRow
// Settings row that shows the current global shortcut and lets the user re-record it.
// Signals isRecording upward so SettingsWindowView can show a full-window dim overlay.

struct HotkeyRecorderRow: View {
    @ObservedObject var settings: MirrorSettings
    let hotkeyManager: GlobalHotkeyManager?
    @Binding var isRecording: Bool

    @State private var displayText = ""

    var body: some View {
        ZStack {
            rowContent

            // Transparent first-responder NSView — active only while recording
            if isRecording {
                KeyCaptureView { keyCode, mods in
                    guard mods != 0 else { return }   // require at least one modifier
                    settings.hotkeyKeyCode   = keyCode
                    settings.hotkeyModifiers = mods
                    hotkeyManager?.reconfigure(keyCode: keyCode, modifiers: mods)
                    withAnimation(.easeOut(duration: 0.2)) { isRecording = false }
                    updateDisplayText()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(true)
            }
        }
        .onAppear { updateDisplayText() }
        .onChange(of: settings.hotkeyKeyCode)  { _ in updateDisplayText() }
        .onChange(of: settings.hotkeyModifiers) { _ in updateDisplayText() }
    }

    // MARK: - Row layout

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Global Shortcut")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KeepMirrorPalette.ink)
                Text("Toggle the mirror from anywhere on the system.")
                    .font(.system(size: 11))
                    .foregroundStyle(KeepMirrorPalette.mutedInk)
            }
            Spacer()
            HStack(spacing: 6) {
                HotkeyBadge(text: isRecording ? "Press keys…" : displayText,
                            isRecording: isRecording)

                if isRecording {
                    Button("Cancel") {
                        withAnimation(.easeOut(duration: 0.2)) { isRecording = false }
                    }
                    .controlSize(.small).buttonStyle(.bordered)
                } else {
                    Button("Record") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isRecording = true
                        }
                    }
                    .controlSize(.small).buttonStyle(.bordered)

                    Button {
                        settings.hotkeyKeyCode   = UInt32(kVK_ANSI_M)
                        settings.hotkeyModifiers = UInt32(cmdKey | shiftKey)
                        hotkeyManager?.reconfigure(
                            keyCode: settings.hotkeyKeyCode,
                            modifiers: settings.hotkeyModifiers
                        )
                        updateDisplayText()
                    } label: { Image(systemName: "arrow.counterclockwise") }
                    .controlSize(.small).buttonStyle(.bordered).help("Reset to ⌘⇧M")
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func updateDisplayText() {
        displayText = HotkeyDescriptor(
            keyCode:   settings.hotkeyKeyCode,
            modifiers: settings.hotkeyModifiers
        ).displayString
    }
}

// MARK: - HotkeyRecordingOverlay
// Full-window dark overlay with centred card. Placed at the top of SettingsWindowView's ZStack.

struct HotkeyRecordingOverlay: View {
    let isRecording: Bool
    let onCancel: () -> Void

    var body: some View {
        if isRecording {
            ZStack {
                // Dim layer — tapping cancels
                Color.black.opacity(0.40)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onCancel() }

                // Modal card
                VStack(spacing: 12) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.white)

                    VStack(spacing: 4) {
                        Text("Press a shortcut…")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("⌘  ⇧  ⌥  ⌃  + any key")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.65))
                    }

                    Button("Cancel") { onCancel() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            }
            .transition(.opacity)
            .zIndex(100)
            .allowsHitTesting(true)
        }
    }
}

// MARK: - HotkeyBadge

struct HotkeyBadge: View {
    let text: String
    let isRecording: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(isRecording ? Color.accentColor : KeepMirrorPalette.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isRecording ? Color.accentColor.opacity(0.12) : KeepMirrorPalette.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                isRecording ? Color.accentColor.opacity(0.5) : KeepMirrorPalette.border,
                                lineWidth: 1
                            )
                    }
            }
            .animation(.easeInOut(duration: 0.15), value: isRecording)
    }
}

// MARK: - KeyCaptureView

private struct KeyCaptureView: NSViewRepresentable {
    let onKey: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let v = KeyCaptureNSView(); v.onKey = onKey; return v
    }
    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onKey = onKey
    }

    final class KeyCaptureNSView: NSView {
        var onKey: ((UInt32, UInt32) -> Void)?
        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            let usable: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            guard !event.modifierFlags.intersection(usable).isEmpty else { return }
            var mods: UInt32 = 0
            if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }
            if event.modifierFlags.contains(.shift)   { mods |= UInt32(shiftKey) }
            if event.modifierFlags.contains(.option)  { mods |= UInt32(optionKey) }
            if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
            onKey?(UInt32(event.keyCode), mods)
        }
        override func flagsChanged(with event: NSEvent) {}
    }
}
