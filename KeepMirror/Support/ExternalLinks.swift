import Foundation

enum ExternalLink: CaseIterable {
    case repository

    var url: URL {
        switch self {
        case .repository:
            URL(string: "https://github.com/adhamhaithameid/KeepMirror")!
        }
    }
}
