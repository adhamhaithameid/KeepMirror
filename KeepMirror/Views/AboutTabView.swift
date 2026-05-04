import AppKit
import SwiftUI

struct AboutTabView: View {
    @ObservedObject var controller: MirrorController

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                KeepMirrorBrandMark(size: 80)

                VStack(spacing: 4) {
                    Text("KeepMirror")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(KeepMirrorPalette.ink)

                    Text("Version \(appVersion)")
                        .font(.system(size: 13))
                        .foregroundStyle(KeepMirrorPalette.mutedInk)
                }

                Text("A beautiful menu bar mirror. Open your camera in an instant — snap photos, check your mic, and access the mirror from the notch.")
                    .font(.system(size: 13))
                    .foregroundStyle(KeepMirrorPalette.mutedInk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                HStack(spacing: 12) {
                    linkButton(
                        title: "GitHub",
                        icon: "chevron.left.forwardslash.chevron.right",
                        identifier: "about.repo"
                    ) {
                        controller.open(.repository)
                    }
                }
            }

            Spacer()

            VStack(spacing: 4) {
                Text("Built with Swift & SwiftUI")
                    .font(.system(size: 11))
                    .foregroundStyle(KeepMirrorPalette.mutedInk.opacity(0.6))

                Text("PolyForm Noncommercial")
                    .font(.system(size: 11))
                    .foregroundStyle(KeepMirrorPalette.mutedInk.opacity(0.6))
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private func linkButton(
        title: String,
        icon: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(KeepMirrorPalette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(KeepMirrorPalette.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(KeepMirrorPalette.border, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
