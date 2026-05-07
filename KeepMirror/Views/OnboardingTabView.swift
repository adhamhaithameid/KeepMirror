import SwiftUI

struct OnboardingTabView: View {
    @ObservedObject var controller: MirrorController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    KeepMirrorBrandMark(size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome to KeepMirror")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(KeepMirrorPalette.ink)
                        Text("Quick setup so your mirror is ready in seconds.")
                            .font(.system(size: 13))
                            .foregroundStyle(KeepMirrorPalette.mutedInk)
                    }
                    Spacer()
                }

                KeepMirrorPanel {
                    Text("Start Here")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(KeepMirrorPalette.ink)

                    onboardingRow(
                        icon: "video.fill",
                        title: "Pick your camera",
                        subtitle: "Choose the camera you want in the Settings tab."
                    )
                    onboardingRow(
                        icon: "mic.fill",
                        title: "Enable mic check if you need it",
                        subtitle: "See your live mic level while presenting or recording."
                    )
                    onboardingRow(
                        icon: "photo.fill",
                        title: "Set capture preferences",
                        subtitle: "Choose format, countdown, and where snapshots are saved."
                    )
                    onboardingRow(
                        icon: "keyboard",
                        title: "Try the hotkey",
                        subtitle: "Use the default Command+Shift+M or record your own shortcut."
                    )

                    HStack {
                        Spacer()
                        Button {
                            controller.completeOnboarding()
                        } label: {
                            Label("Finish Onboarding", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(KeepMirrorPalette.blue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityIdentifier("onboarding.finish")
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
    }

    private func onboardingRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KeepMirrorPalette.blue)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KeepMirrorPalette.ink)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(KeepMirrorPalette.mutedInk)
            }
        }
    }
}
