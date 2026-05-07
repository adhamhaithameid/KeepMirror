import SwiftUI

struct SettingsWindowView: View {
    @ObservedObject var controller: MirrorController

    // Shared recording state — lifted here so the overlay can cover the full window
    @State private var isHotkeyRecording = false

    var body: some View {
        ZStack(alignment: .top) {
            KeepMirrorAmbientBackground()

            VStack(spacing: 18) {
                tabBar
                    .padding(.top, 24)

                Group {
                    switch controller.selectedTab {
                    case .onboarding:
                        OnboardingTabView(controller: controller)
                    case .settings:
                        MirrorSettingsTabView(
                            controller: controller,
                            settings: controller.settings,
                            isHotkeyRecording: $isHotkeyRecording
                        )
                    case .about:
                        AboutTabView(controller: controller)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Bottom bar — Quit button
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        NSApp.terminate(nil)
                    } label: {
                        Label("Quit", systemImage: "power")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.red.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)

            // Full-window hotkey recording overlay — sits above everything
            HotkeyRecordingOverlay(isRecording: isHotkeyRecording) {
                withAnimation(.easeOut(duration: 0.2)) { isHotkeyRecording = false }
            }
        }
        .frame(minWidth: 480, idealWidth: 540, minHeight: 480)
    }

    private var tabBar: some View {
        let tabs: [AppTab] = controller.settings.hasCompletedOnboarding
            ? [.settings, .about]
            : [.onboarding, .settings, .about]

        return HStack(spacing: 4) {
            ForEach(tabs) { tab in
                tabButton(for: tab)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(KeepMirrorPalette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(KeepMirrorPalette.border, lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func tabButton(for tab: AppTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                controller.selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(tab.title)
                    .font(.system(size: 13, weight: controller.selectedTab == tab ? .semibold : .medium))
            }
            .foregroundStyle(controller.selectedTab == tab ? Color.white : KeepMirrorPalette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                if controller.selectedTab == tab {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(KeepMirrorPalette.blue)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab.\(tab.rawValue)")
    }
}
