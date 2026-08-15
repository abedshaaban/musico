import Foundation

enum MediaKind: String, Codable, CaseIterable, Identifiable {
    case audio
    case video

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var systemImage: String { self == .audio ? "music.note" : "film" }
}

enum LibrarySortOption: String, CaseIterable, Identifiable {
    case dateAdded
    case title
    case artist

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dateAdded: return "Date Added"
        case .title: return "Title"
        case .artist: return "Artist"
        }
    }
}

enum MediaKindFilter: String, CaseIterable, Identifiable {
    case all
    case audio
    case video

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .audio: return "Audio"
        case .video: return "Video"
        }
    }

    func matches(_ kind: MediaKind) -> Bool {
        switch self {
        case .all: return true
        case .audio: return kind == .audio
        case .video: return kind == .video
        }
    }
}

struct LibraryItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var artist: String
    let kind: MediaKind
    let localFilename: String
    let originalFilename: String
    let addedAt: Date
    var artworkFilename: String?
}

struct Playlist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var itemIDs: [UUID]
    let createdAt: Date
}

enum DownloadState: String, Codable, CaseIterable {
    case validating
    case queued
    case downloading
    case completed
    case failed
    case cancelled

    var label: String {
        switch self {
        case .validating: return "Validating"
        default: return rawValue.capitalized
        }
    }

    var isActive: Bool {
        self == .validating || self == .queued || self == .downloading
    }
}

struct DownloadRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var sourceName: String
    var state: DownloadState
    var progress: Double
    let createdAt: Date
    var detail: String?

    // Direct, authorized media URL and the media type resolved during validation.
    var remoteURL: URL?
    var mediaKind: MediaKind?
    var receivedBytes: Int64
    var totalBytes: Int64
    var thumbnailURL: URL?

    init(
        id: UUID = UUID(),
        title: String,
        sourceName: String,
        state: DownloadState,
        progress: Double = 0,
        createdAt: Date = Date(),
        detail: String? = nil,
        remoteURL: URL? = nil,
        mediaKind: MediaKind? = nil,
        receivedBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        thumbnailURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceName = sourceName
        self.state = state
        self.progress = progress
        self.createdAt = createdAt
        self.detail = detail
        self.remoteURL = remoteURL
        self.mediaKind = mediaKind
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        self.thumbnailURL = thumbnailURL
    }
}

struct PersistedLibrary: Codable {
    var items: [LibraryItem]
    var playlists: [Playlist]
    var recentlyPlayedIDs: [UUID]
    var knownArtists: [String]

    private enum CodingKeys: String, CodingKey {
        case items, playlists, recentlyPlayedIDs, knownArtists
    }

    init(
        items: [LibraryItem],
        playlists: [Playlist],
        recentlyPlayedIDs: [UUID] = [],
        knownArtists: [String] = []
    ) {
        self.items = items
        self.playlists = playlists
        self.recentlyPlayedIDs = recentlyPlayedIDs
        self.knownArtists = knownArtists
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([LibraryItem].self, forKey: .items)
        playlists = try container.decode([Playlist].self, forKey: .playlists)
        recentlyPlayedIDs = try container.decodeIfPresent([UUID].self, forKey: .recentlyPlayedIDs) ?? []
        knownArtists = try container.decodeIfPresent([String].self, forKey: .knownArtists) ?? []
    }
}

struct PersistedDownloads: Codable {
    var records: [DownloadRecord]
}

/// Shared on-disk locations. Downloaded and imported media both live inside
/// Application Support so the library is fully offline and self-contained.
enum AppPaths {
    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Musico", isDirectory: true)
    }

    static var media: URL {
        applicationSupport.appendingPathComponent("Media", isDirectory: true)
    }

    static var artwork: URL {
        applicationSupport.appendingPathComponent("Artwork", isDirectory: true)
    }

    static var libraryFile: URL {
        applicationSupport.appendingPathComponent("library.json")
    }

    static var downloadsFile: URL {
        applicationSupport.appendingPathComponent("downloads.json")
    }

    @discardableResult
    static func ensureDirectories() -> Bool {
        do {
            try FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: artwork, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }
}

/// The container formats Musico can validate on download and play back with AVFoundation.
/// Extension point: widen these sets only for formats an authorized converter or a new
/// AVFoundation-supported container can actually play. Do not add formats that would
/// require bundled third-party decoders.
enum SupportedMedia {
    static let audioMIMETypes: Set<String> = [
        "audio/mpeg", "audio/mp3", "audio/mp4", "audio/aac", "audio/aacp",
        "audio/x-m4a", "audio/m4a", "audio/wav", "audio/x-wav", "audio/wave",
        "audio/aiff", "audio/x-aiff", "audio/x-caf", "audio/flac", "audio/x-flac",
        "audio/alac", "audio/x-alac", "audio/ac3", "audio/eac3"
    ]

    static let videoMIMETypes: Set<String> = [
        "video/mp4", "video/quicktime", "video/x-m4v", "video/3gpp"
    ]

    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "mp4a"
    ]

    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "3gp"
    ]

    static func normalizedMIME(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.split(separator: ";").first.map(String.init) ?? raw
        return value.trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func kind(forMIME raw: String?) -> MediaKind? {
        guard let mime = normalizedMIME(raw) else { return nil }
        if audioMIMETypes.contains(mime) { return .audio }
        if videoMIMETypes.contains(mime) { return .video }
        return nil
    }

    static func kind(forExtension ext: String) -> MediaKind? {
        let lowered = ext.lowercased()
        if audioExtensions.contains(lowered) { return .audio }
        if videoExtensions.contains(lowered) { return .video }
        return nil
    }

    /// A file extension suitable for the resolved kind, preferring the URL's own
    /// extension when it is one we recognize.
    static func fileExtension(for kind: MediaKind, url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty, self.kind(forExtension: ext) == kind {
            return ext
        }
        return kind == .audio ? "m4a" : "mp4"
    }
}
