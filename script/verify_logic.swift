import Foundation

@main
struct LogicChecks {
    @MainActor
    static func main() {
        let suiteName = "KeepMirror.LogicChecks"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(store: defaults)

        precondition(settings.defaultDuration == .minutes(15))
        precondition(settings.availableDurations.contains(.indefinite))
        precondition(settings.sessionOptions.allowPowerNap == false)
        precondition(settings.sessionOptions.allowDisplaySleep == false)

        let custom = ActivationDuration(hours: 0, minutes: 45, seconds: 0)
        settings.addDuration(custom)
        settings.setDefaultDuration(custom.id)
        settings.pin(custom.id)

        let reloaded = AppSettings(store: defaults)
        precondition(reloaded.defaultDurationID == custom.id)
        precondition(reloaded.availableDurations.contains(custom))
        precondition(reloaded.pinnedDurationIDs.contains(custom.id))

        precondition(AppSettings.applyMagneticSnap(18) == 20)
        precondition(AppSettings.applyMagneticSnap(63) == 63)

        print("Logic checks passed.")
    }
}
