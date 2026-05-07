import Carbon.HIToolbox
import Foundation

// MARK: - MirrorSize

enum MirrorSize: String, CaseIterable, Codable {
    case small
    case medium
    case large

    var title: String {
        switch self {
        case .small:  "Small (280×210)"
        case .medium: "Medium (400×300)"
        case .large:  "Large (560×420)"
        }
    }

    var popoverSize: CGSize {
        switch self {
        case .small:  CGSize(width: 280, height: 210)
        case .medium: CGSize(width: 400, height: 300)
        case .large:  CGSize(width: 560, height: 420)
        }
    }
}

// MARK: - CaptureFormat

enum CaptureFormat: String, CaseIterable, Codable {
    case png
    case jpeg
    case heif

    var title: String {
        switch self {
        case .png:  "PNG"
        case .jpeg: "JPEG"
        case .heif: "HEIF"
        }
    }

    var fileExtension: String {
        switch self {
        case .png:  "png"
        case .jpeg: "jpg"
        case .heif: "heic"
        }
    }
}

// MARK: - CaptureCountdown

enum CaptureCountdown: Int, CaseIterable, Codable {
    case off = 0
    case threeSeconds = 3
    case fiveSeconds = 5

    var title: String {
        switch self {
        case .off:          "Off"
        case .threeSeconds: "3 seconds"
        case .fiveSeconds:  "5 seconds"
        }
    }
}

// MARK: - SessionPresetQuality

enum SessionPresetQuality: String, CaseIterable, Codable {
    case low
    case medium
    case high
    case photo

    var title: String {
        switch self {
        case .low:    "Low (360p)"
        case .medium: "Medium (480p)"
        case .high:   "High (720p)"
        case .photo:  "Max (native)"
        }
    }

    var avPreset: AVCaptureSession.Preset {
        switch self {
        case .low:    .low
        case .medium: .medium
        case .high:   .high
        case .photo:  .photo
        }
    }
}

// MARK: - MicSensitivity

enum MicSensitivity: String, CaseIterable, Codable {
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .low:    "Conservative"
        case .medium: "Normal"
        case .high:   "Reactive"
        }
    }

    /// Sensitivity multiplier for StandaloneMicMonitor (baseGain 40×).
    /// low=24× effective, medium=40×, high=64× — calibrated for built-in MacBook mic.
    var gain: Float {
        switch self {
        case .low:    0.6
        case .medium: 1.0
        case .high:   1.6
        }
    }
}

// MARK: - MirrorSettings

@MainActor
final class MirrorSettings: ObservableObject {

    // MARK: - Keys

    private enum Keys {
        // Mirror
        static let mirrorSize          = "mirrorSize"
        static let selectedCameraID    = "selectedCameraID"
        static let isFlipped           = "isFlipped"
        static let sessionQuality      = "sessionQuality"
        // Capture
        static let photoSaveBookmark   = "photoSaveBookmark"
        static let captureFormat       = "captureFormat"
        static let captureCountdown    = "captureCountdown"

        static let copyToClipboard     = "copyToClipboard"
        static let revealInFinder      = "revealInFinder"
        // Mic
        static let micCheckEnabled     = "micCheckEnabled"
        static let hasAutoEnabledMic   = "hasAutoEnabledMic"
        static let selectedMicID       = "selectedMicID"
        static let micSensitivity      = "micSensitivity"
        // Notch
        static let notchHoverEnabled        = "notchHoverEnabled"
        static let hideMenuBarIconWhenNotch = "hideMenuBarIconWhenNotch"
        // General
        static let startAtLogin        = "startAtLogin"
        static let showCaptureFlash    = "showCaptureFlash"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        // Hotkey
        static let hotkeyKeyCode       = "hotkeyKeyCode"
        static let hotkeyModifiers     = "hotkeyModifiers"
    }

    private let defaults: UserDefaults

    // MARK: - Mirror

    @Published var mirrorSize: MirrorSize {
        didSet { defaults.set(mirrorSize.rawValue, forKey: Keys.mirrorSize) }
    }

    @Published var selectedCameraID: String {
        didSet { defaults.set(selectedCameraID, forKey: Keys.selectedCameraID) }
    }

    @Published var isFlipped: Bool {
        didSet { defaults.set(isFlipped, forKey: Keys.isFlipped) }
    }

    @Published var sessionQuality: SessionPresetQuality {
        didSet { defaults.set(sessionQuality.rawValue, forKey: Keys.sessionQuality) }
    }

    // MARK: - Capture

    @Published var photoSaveBookmark: Data? {
        didSet { defaults.set(photoSaveBookmark, forKey: Keys.photoSaveBookmark) }
    }

    var resolvedPhotoSaveURL: URL {
        if let data = photoSaveBookmark {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: data,
                                  options: .withSecurityScope,
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &isStale) {
                return url
            }
        }
        let pics = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return pics.appendingPathComponent("KeepMirror", isDirectory: true)
    }

    @Published var captureFormat: CaptureFormat {
        didSet { defaults.set(captureFormat.rawValue, forKey: Keys.captureFormat) }
    }

    @Published var captureCountdown: CaptureCountdown {
        didSet { defaults.set(captureCountdown.rawValue, forKey: Keys.captureCountdown) }
    }


    @Published var copyToClipboard: Bool {
        didSet { defaults.set(copyToClipboard, forKey: Keys.copyToClipboard) }
    }

    @Published var revealInFinder: Bool {
        didSet { defaults.set(revealInFinder, forKey: Keys.revealInFinder) }
    }

    // MARK: - Mic

    @Published var micCheckEnabled: Bool {
        didSet { defaults.set(micCheckEnabled, forKey: Keys.micCheckEnabled) }
    }

    @Published var selectedMicID: String {
        didSet { defaults.set(selectedMicID, forKey: Keys.selectedMicID) }
    }

    @Published var micSensitivity: MicSensitivity {
        didSet { defaults.set(micSensitivity.rawValue, forKey: Keys.micSensitivity) }
    }

    // MARK: - Notch

    @Published var notchHoverEnabled: Bool {
        didSet { defaults.set(notchHoverEnabled, forKey: Keys.notchHoverEnabled) }
    }

    @Published var hideMenuBarIconWhenNotch: Bool {
        didSet { defaults.set(hideMenuBarIconWhenNotch, forKey: Keys.hideMenuBarIconWhenNotch) }
    }

    // MARK: - General

    @Published var startAtLogin: Bool {
        didSet { defaults.set(startAtLogin, forKey: Keys.startAtLogin) }
    }

    @Published var showCaptureFlash: Bool {
        didSet { defaults.set(showCaptureFlash, forKey: Keys.showCaptureFlash) }
    }

    // MARK: - Hotkey

    /// Carbon key code for the toggle shortcut (default: kVK_ANSI_M = 46)
    @Published var hotkeyKeyCode: UInt32 {
        didSet { defaults.set(Int(hotkeyKeyCode), forKey: Keys.hotkeyKeyCode) }
    }

    /// Carbon modifier flags (default: cmdKey | shiftKey = 4352)
    @Published var hotkeyModifiers: UInt32 {
        didSet { defaults.set(Int(hotkeyModifiers), forKey: Keys.hotkeyModifiers) }
    }

    /// Set to true once we've auto-enabled mic check after the first permission grant.
    var hasAutoEnabledMic: Bool {
        get { defaults.bool(forKey: Keys.hasAutoEnabledMic) }
        set { defaults.set(newValue, forKey: Keys.hasAutoEnabledMic) }
    }

    /// Set to true once first-run onboarding is completed.
    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.mirrorSize = MirrorSize(rawValue: defaults.string(forKey: Keys.mirrorSize) ?? "") ?? .medium
        self.selectedCameraID = defaults.string(forKey: Keys.selectedCameraID) ?? ""
        self.isFlipped = defaults.bool(forKey: Keys.isFlipped)
        self.sessionQuality = SessionPresetQuality(rawValue: defaults.string(forKey: Keys.sessionQuality) ?? "") ?? .photo

        self.photoSaveBookmark = defaults.data(forKey: Keys.photoSaveBookmark)
        self.captureFormat = CaptureFormat(rawValue: defaults.string(forKey: Keys.captureFormat) ?? "") ?? .png
        self.captureCountdown = CaptureCountdown(rawValue: defaults.integer(forKey: Keys.captureCountdown)) ?? .off

        self.copyToClipboard = defaults.bool(forKey: Keys.copyToClipboard)
        self.revealInFinder = defaults.object(forKey: Keys.revealInFinder) as? Bool ?? false

        self.micCheckEnabled = defaults.bool(forKey: Keys.micCheckEnabled)
        self.selectedMicID   = defaults.string(forKey: Keys.selectedMicID) ?? ""
        self.micSensitivity  = MicSensitivity(rawValue: defaults.string(forKey: Keys.micSensitivity) ?? "") ?? .medium

        self.notchHoverEnabled       = defaults.bool(forKey: Keys.notchHoverEnabled)
        self.hideMenuBarIconWhenNotch = defaults.bool(forKey: Keys.hideMenuBarIconWhenNotch)

        self.startAtLogin    = defaults.bool(forKey: Keys.startAtLogin)
        self.showCaptureFlash = defaults.object(forKey: Keys.showCaptureFlash) as? Bool ?? true

        // Hotkey — default ⌘⇧M (kVK_ANSI_M = 46, cmdKey|shiftKey = 4352)
        let storedKeyCode = defaults.object(forKey: Keys.hotkeyKeyCode) as? Int
        self.hotkeyKeyCode  = UInt32(storedKeyCode ?? 46)
        let storedMods = defaults.object(forKey: Keys.hotkeyModifiers) as? Int
        self.hotkeyModifiers = UInt32(storedMods ?? (cmdKey | shiftKey))
    }
}

// MARK: - AVFoundation import (needed for avPreset)

import AVFoundation
