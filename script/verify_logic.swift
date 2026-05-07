import Foundation

@main
struct LogicChecks {
    @MainActor
    static func main() {
        let suiteName = "KeepMirror.LogicChecks"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = MirrorSettings(defaults: defaults)

        precondition(settings.mirrorSize == .medium)
        precondition(settings.isFlipped == false)
        precondition(settings.sessionQuality == .photo)
        precondition(settings.captureFormat == .png)
        precondition(settings.captureCountdown == .off)
        precondition(settings.copyToClipboard == false)
        precondition(settings.revealInFinder == false)
        precondition(settings.micCheckEnabled == false)
        precondition(settings.micSensitivity == .medium)
        precondition(settings.notchHoverEnabled == false)
        precondition(settings.hideMenuBarIconWhenNotch == false)
        precondition(settings.startAtLogin == false)
        precondition(settings.showCaptureFlash == true)
        precondition(settings.hotkeyKeyCode == 46)
        precondition(settings.hotkeyModifiers == 768)

        settings.mirrorSize = .large
        settings.selectedCameraID = "cam-123"
        settings.isFlipped = true
        settings.sessionQuality = .high
        settings.captureFormat = .jpeg
        settings.captureCountdown = .threeSeconds
        settings.copyToClipboard = true
        settings.revealInFinder = true
        settings.micCheckEnabled = true
        settings.selectedMicID = "mic-456"
        settings.micSensitivity = .high
        settings.notchHoverEnabled = true
        settings.hideMenuBarIconWhenNotch = true
        settings.startAtLogin = true
        settings.showCaptureFlash = false
        settings.hotkeyKeyCode = 3
        settings.hotkeyModifiers = 4096

        let reloaded = MirrorSettings(defaults: defaults)
        precondition(reloaded.mirrorSize == .large)
        precondition(reloaded.selectedCameraID == "cam-123")
        precondition(reloaded.isFlipped == true)
        precondition(reloaded.sessionQuality == .high)
        precondition(reloaded.captureFormat == .jpeg)
        precondition(reloaded.captureCountdown == .threeSeconds)
        precondition(reloaded.copyToClipboard == true)
        precondition(reloaded.revealInFinder == true)
        precondition(reloaded.micCheckEnabled == true)
        precondition(reloaded.selectedMicID == "mic-456")
        precondition(reloaded.micSensitivity == .high)
        precondition(reloaded.notchHoverEnabled == true)
        precondition(reloaded.hideMenuBarIconWhenNotch == true)
        precondition(reloaded.startAtLogin == true)
        precondition(reloaded.showCaptureFlash == false)
        precondition(reloaded.hotkeyKeyCode == 3)
        precondition(reloaded.hotkeyModifiers == 4096)
        precondition(reloaded.resolvedPhotoSaveURL.lastPathComponent == "KeepMirror")

        print("Logic checks passed.")
    }
}
