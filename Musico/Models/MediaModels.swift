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
    case album
    case year
    case genre
    case fileSize
    case playCount

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dateAdded: return "Date Added"
        case .title: return "Title"
        case .artist: return "Artist"
        case .album: return "Album"
        case .year: return "Year"
        case .genre: return "Genre"
        case .fileSize: return "File Size"
        case .playCount: return "Play Count"
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
    var album: String? = nil
    var genre: String? = nil
    var year: Int? = nil
    var trackNumber: Int? = nil
    let kind: MediaKind
    let localFilename: String
    let originalFilename: String
    let addedAt: Date
    var artworkFilename: String?
    var tags: [String] = []
    var playCount: Int = 0
    var lastPlayedAt: Date? = nil
    var resumePosition: Double = 0
    var normalizationGainDB: Double? = nil

    init(
        id: UUID,
        title: String,
        artist: String,
        album: String? = nil,
        genre: String? = nil,
        year: Int? = nil,
        trackNumber: Int? = nil,
        kind: MediaKind,
        localFilename: String,
        originalFilename: String,
        addedAt: Date,
        artworkFilename: String?,
        tags: [String] = [],
        playCount: Int = 0,
        lastPlayedAt: Date? = nil,
        resumePosition: Double = 0,
        normalizationGainDB: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.year = year
        self.trackNumber = trackNumber
        self.kind = kind
        self.localFilename = localFilename
        self.originalFilename = originalFilename
        self.addedAt = addedAt
        self.artworkFilename = artworkFilename
        self.tags = tags
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
        self.resumePosition = resumePosition
        self.normalizationGainDB = normalizationGainDB
    }

    var collectionSummary: String? {
        let parts = [
            album?.nilIfBlank,
            year.map(String.init),
            genre?.nilIfBlank
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, artist, album, genre, year, trackNumber, kind
        case localFilename, originalFilename, addedAt, artworkFilename
        case tags, playCount, lastPlayedAt, resumePosition, normalizationGainDB
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decode(String.self, forKey: .artist)
        album = try container.decodeIfPresent(String.self, forKey: .album)
        genre = try container.decodeIfPresent(String.self, forKey: .genre)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        trackNumber = try container.decodeIfPresent(Int.self, forKey: .trackNumber)
        kind = try container.decode(MediaKind.self, forKey: .kind)
        localFilename = try container.decode(String.self, forKey: .localFilename)
        originalFilename = try container.decode(String.self, forKey: .originalFilename)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        artworkFilename = try container.decodeIfPresent(String.self, forKey: .artworkFilename)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        playCount = try container.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
        lastPlayedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
        resumePosition = try container.decodeIfPresent(Double.self, forKey: .resumePosition) ?? 0
        normalizationGainDB = try container.decodeIfPresent(Double.self, forKey: .normalizationGainDB)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(artist, forKey: .artist)
        try container.encodeIfPresent(album, forKey: .album)
        try container.encodeIfPresent(genre, forKey: .genre)
        try container.encodeIfPresent(year, forKey: .year)
        try container.encodeIfPresent(trackNumber, forKey: .trackNumber)
        try container.encode(kind, forKey: .kind)
        try container.encode(localFilename, forKey: .localFilename)
        try container.encode(originalFilename, forKey: .originalFilename)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encodeIfPresent(artworkFilename, forKey: .artworkFilename)
        try container.encode(tags, forKey: .tags)
        try container.encode(playCount, forKey: .playCount)
        try container.encodeIfPresent(lastPlayedAt, forKey: .lastPlayedAt)
        try container.encode(resumePosition, forKey: .resumePosition)
        try container.encodeIfPresent(normalizationGainDB, forKey: .normalizationGainDB)
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
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
    var artist: String?
    var sourceName: String
    var state: DownloadState
    var progress: Double
    let createdAt: Date
    var detail: String?
    /// Persisted technical context for the failure-details sheet. Kept separate from
    /// `detail` so the Downloads list can remain short and readable.
    var diagnostic: String?

    // Direct, authorized media URL and the media type resolved during validation.
    var remoteURL: URL?
    var mediaKind: MediaKind?
    var receivedBytes: Int64
    var totalBytes: Int64
    var thumbnailURL: URL?
    /// When set, the completed library item is also added to this local playlist.
    /// Persisting this on the record preserves bulk-import intent across retries and
    /// background-session relaunches.
    var targetPlaylistID: UUID?
    var targetPlaylistPosition: Int?

    init(
        id: UUID = UUID(),
        title: String,
        artist: String? = nil,
        sourceName: String,
        state: DownloadState,
        progress: Double = 0,
        createdAt: Date = Date(),
        detail: String? = nil,
        diagnostic: String? = nil,
        remoteURL: URL? = nil,
        mediaKind: MediaKind? = nil,
        receivedBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        thumbnailURL: URL? = nil,
        targetPlaylistID: UUID? = nil,
        targetPlaylistPosition: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.sourceName = sourceName
        self.state = state
        self.progress = progress
        self.createdAt = createdAt
        self.detail = detail
        self.diagnostic = diagnostic
        self.remoteURL = remoteURL
        self.mediaKind = mediaKind
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        self.thumbnailURL = thumbnailURL
        self.targetPlaylistID = targetPlaylistID
        self.targetPlaylistPosition = targetPlaylistPosition
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, artist, sourceName, state, progress, createdAt, detail, diagnostic
        case remoteURL, mediaKind, receivedBytes, totalBytes, thumbnailURL
        case targetPlaylistID, targetPlaylistPosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        sourceName = try container.decode(String.self, forKey: .sourceName)
        state = try container.decode(DownloadState.self, forKey: .state)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        diagnostic = try container.decodeIfPresent(String.self, forKey: .diagnostic)
        remoteURL = try container.decodeIfPresent(URL.self, forKey: .remoteURL)
        mediaKind = try container.decodeIfPresent(MediaKind.self, forKey: .mediaKind)
        receivedBytes = try container.decodeIfPresent(Int64.self, forKey: .receivedBytes) ?? 0
        totalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0
        thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
        targetPlaylistID = try container.decodeIfPresent(UUID.self, forKey: .targetPlaylistID)
        targetPlaylistPosition = try container.decodeIfPresent(Int.self, forKey: .targetPlaylistPosition)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(artist, forKey: .artist)
        try container.encode(sourceName, forKey: .sourceName)
        try container.encode(state, forKey: .state)
        try container.encode(progress, forKey: .progress)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encodeIfPresent(diagnostic, forKey: .diagnostic)
        try container.encodeIfPresent(remoteURL, forKey: .remoteURL)
        try container.encodeIfPresent(mediaKind, forKey: .mediaKind)
        try container.encode(receivedBytes, forKey: .receivedBytes)
        try container.encode(totalBytes, forKey: .totalBytes)
        try container.encodeIfPresent(thumbnailURL, forKey: .thumbnailURL)
        try container.encodeIfPresent(targetPlaylistID, forKey: .targetPlaylistID)
        try container.encodeIfPresent(targetPlaylistPosition, forKey: .targetPlaylistPosition)
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

struct PersistedPlaybackState: Codable, Equatable {
    var queueIDs: [UUID]
    var currentItemID: UUID?
    var currentQueueIndex: Int
    var elapsed: Double
    var isShuffleEnabled: Bool
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

    static var playbackFile: URL {
        applicationSupport.appendingPathComponent("playback.json")
    }

    @discardableResult
    static func ensureDirectories() -> Bool {
        do {
            try createDirectories()
            return true
        } catch {
            return false
        }
    }

    static func createDirectories() throws {
        try FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: artwork, withIntermediateDirectories: true)
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
