import AppKit
import CoreGraphics

// MARK: - NSScreen notch helpers

extension NSScreen {
    /// True when this screen has a physical notch (safeAreaInsets.top > 0).
    var hasNotch: Bool {
        if #available(macOS 12.0, *) {
            return safeAreaInsets.top > 0
        }
        return false
    }

    /// The approximate CGRect of the notch area in Cocoa screen coordinates
    /// (origin = bottom-left). Returns nil on non-notch screens.
    var notchRect: CGRect? {
        guard hasNotch else { return nil }
        let notchHeight: CGFloat
        if #available(macOS 12.0, *) {
            notchHeight = safeAreaInsets.top
        } else {
            return nil
        }
        let notchWidth: CGFloat = 260   // conservative safe estimate
        return CGRect(
            x: frame.midX - notchWidth / 2,
            y: frame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )
    }
}

// MARK: - NotchHoverMonitor

/// Monitors global mouse movement and fires callbacks when the cursor
/// enters or leaves the notch area (plus a 28 pt extension below the notch).
///
/// Uses `NSEvent.addGlobalMonitorForEvents(.mouseMoved)` which requires
/// NO special permissions for cursor position only (no keystrokes, no clicks).
@MainActor
final class NotchHoverMonitor {

    /// Called when the cursor enters the notch zone.
    var onEnterNotch: (() -> Void)?
    /// Called when the cursor leaves the notch zone.
    var onLeaveNotch: (() -> Void)?

    private var monitor: Any?
    private var isInside = false
    private var debounceTimer: Timer?

    /// The extra vertical space (in points) below the notch that also triggers the hover.
    private let extensionBelow: CGFloat = 28

    // MARK: - Control

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMouseMoved(event)
            }
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        isInside = false
        debounceTimer?.invalidate()
        debounceTimer = nil
    }

    // MARK: - Detection

    private func handleMouseMoved(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        let nowInside = notchZoneContains(location)

        guard nowInside != isInside else { return }
        isInside = nowInside

        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isInside {
                    self.onEnterNotch?()
                } else {
                    self.onLeaveNotch?()
                }
            }
        }
    }

    /// Checks whether `point` (Cocoa screen coords) is within any notch zone.
    private func notchZoneContains(_ point: CGPoint) -> Bool {
        for screen in NSScreen.screens {
            guard let notch = screen.notchRect else { continue }
            // Extend the hot zone downward by `extensionBelow` points
            let zone = CGRect(
                x: notch.minX,
                y: notch.minY - extensionBelow,
                width: notch.width,
                height: notch.height + extensionBelow
            )
            if zone.contains(point) { return true }
        }
        return false
    }

    /// Returns true if the current Mac has at least one screen with a notch.
    static var currentMacHasNotch: Bool {
        NSScreen.screens.contains(where: \.hasNotch)
    }
}
