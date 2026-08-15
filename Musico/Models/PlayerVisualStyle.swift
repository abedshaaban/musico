import Foundation

enum PlayerVisualStyle: String, CaseIterable, Identifiable, Codable {
    case vinyl
    case compactDisc
    case cassette
    case classic
    case video

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vinyl: return "Vinyl"
        case .compactDisc: return "CD"
        case .cassette: return "Cassette"
        case .classic: return "Classic"
        case .video: return "Video"
        }
    }

    var systemImage: String {
        switch self {
        case .vinyl: return "record.circle"
        case .compactDisc: return "circle.circle"
        case .cassette: return "rectangle.on.rectangle"
        case .classic: return "square.stack"
        case .video: return "play.rectangle"
        }
    }

    static func options(for item: LibraryItem) -> [PlayerVisualStyle] {
        if item.kind == .video {
            return allCases
        }
        return allCases.filter { $0 != .video }
    }
}
