import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case onboarding
    case settings
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onboarding: "Onboarding"
        case .settings: "Settings"
        case .about:    "About"
        }
    }

    var icon: String {
        switch self {
        case .onboarding: "sparkles"
        case .settings: "gearshape"
        case .about:    "info.circle"
        }
    }
}
