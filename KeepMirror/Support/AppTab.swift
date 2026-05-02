import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case settings
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .settings: "Settings"
        case .about:    "About"
        }
    }

    var icon: String {
        switch self {
        case .settings: "gearshape"
        case .about:    "info.circle"
        }
    }
}
