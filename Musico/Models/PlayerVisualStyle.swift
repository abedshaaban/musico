import Foundation

enum PlayerVisualStyle: String, CaseIterable, Identifiable, Codable {
    case vinyl
    case compactDisc
    case cassette
    case classic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vinyl: return "Vinyl"
        case .compactDisc: return "CD"
        case .cassette: return "Cassette"
        case .classic: return "Classic"
        }
    }

    var systemImage: String {
        switch self {
        case .vinyl: return "record.circle"
        case .compactDisc: return "circle.circle"
        case .cassette: return "rectangle.on.rectangle"
        case .classic: return "square.stack"
        }
    }
}
