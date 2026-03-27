import Foundation

enum InspectorTab: Int, CaseIterable, Identifiable {
    case files
    case git
    case search
    case extensions

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .files: "Files"
        case .search: "Search"
        case .git: "Git"
        case .extensions: "Extensions"
        }
    }

    var icon: String {
        switch self {
        case .files: "folder"
        case .search: "magnifyingglass"
        case .git: "point.topleft.down.curvedto.point.bottomright.up"
        case .extensions: "puzzlepiece.extension"
        }
    }

    var selectedIcon: String {
        switch self {
        case .files: "folder.fill"
        case .search: "magnifyingglass.circle.fill"
        case .git: "point.topleft.down.curvedto.point.bottomright.up.fill"
        case .extensions: "puzzlepiece.extension.fill"
        }
    }
}
