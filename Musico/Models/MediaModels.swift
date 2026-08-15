import Foundation

enum MediaKind: String, Codable, CaseIterable, Identifiable {
    case audio
    case video

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var systemImage: String { self == .audio ? "music.note" : "film" }
}

struct LibraryItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var artist: String
    let kind: MediaKind
    let localFilename: String
    let originalFilename: String
    let addedAt: Date
}

struct Playlist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var itemIDs: [UUID]
    let createdAt: Date
}

enum DownloadState: String, Codable, CaseIterable {
    case queued
    case downloading
    case completed
    case failed
    case cancelled

    var label: String { rawValue.capitalized }
}

struct DownloadRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var sourceName: String
    var state: DownloadState
    var progress: Double
    let createdAt: Date
    var detail: String?
}

struct PersistedLibrary: Codable {
    var items: [LibraryItem]
    var playlists: [Playlist]
}
