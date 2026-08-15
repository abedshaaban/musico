import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import UIKit

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var items: [LibraryItem] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var recentlyPlayedIDs: [UUID] = []
    @Published private(set) var knownArtists: [String] = []
    @Published var lastError: String?

    private let artworkCache = NSCache<NSString, UIImage>()

    init() {
        // Keep decoded artwork bounded on memory-constrained devices such as iPhone 7.
        artworkCache.totalCostLimit = 24 * 1024 * 1024
        artworkCache.countLimit = 80
        load()
    }

    func fileURL(for item: LibraryItem) -> URL {
        AppPaths.media.appendingPathComponent(item.localFilename)
    }

    func artworkURL(for item: LibraryItem) -> URL? {
        guard let filename = item.artworkFilename else { return nil }
        let url = AppPaths.artwork.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func artworkImage(for item: LibraryItem, targetSize: CGFloat) -> UIImage? {
        guard let filename = item.artworkFilename,
              let url = artworkURL(for: item) else { return nil }

        let maximumPixels = min(max(Int(targetSize * UIScreen.main.scale), 64), 1_200)
        let cacheKey = "\(filename)|\(maximumPixels)" as NSString
        if let cached = artworkCache.object(forKey: cacheKey) { return cached }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumPixels
                ] as CFDictionary
              ) else { return nil }

        let decoded = UIImage(cgImage: image, scale: UIScreen.main.scale, orientation: .up)
        artworkCache.setObject(decoded, forKey: cacheKey, cost: image.bytesPerRow * image.height)
        return decoded
    }

    func clearArtworkCache() {
        artworkCache.removeAllObjects()
    }

    func recentlyPlayedItems() -> [LibraryItem] {
        recentlyPlayedIDs.compactMap { id in items.first(where: { $0.id == id }) }
    }

    func recordPlayed(_ itemID: UUID) {
        recentlyPlayedIDs.removeAll { $0 == itemID }
        recentlyPlayedIDs.insert(itemID, at: 0)
        if recentlyPlayedIDs.count > 100 {
            recentlyPlayedIDs = Array(recentlyPlayedIDs.prefix(100))
        }
        if let index = items.firstIndex(where: { $0.id == itemID }) {
            items[index].playCount += 1
            items[index].lastPlayedAt = Date()
        }
        save()
    }

    func clearPlaybackHistory() {
        recentlyPlayedIDs = []
        save()
    }

    func updateResumePosition(itemID: UUID, seconds: Double, duration: Double, completed: Bool = false) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let shouldClear = completed || seconds < 30 || (duration > 0 && duration - seconds < 30)
        let position = shouldClear ? 0 : seconds
        guard abs(items[index].resumePosition - position) >= 2 else { return }
        items[index].resumePosition = position
        save()
    }

    func sortedItems(
        _ source: [LibraryItem],
        by sort: LibrarySortOption,
        filter kindFilter: MediaKindFilter
    ) -> [LibraryItem] {
        let filtered = source.filter { kindFilter.matches($0.kind) }
        switch sort {
        case .dateAdded:
            return filtered.sorted { $0.addedAt > $1.addedAt }
        case .title:
            return filtered.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .artist:
            return filtered.sorted {
                let artistCompare = $0.artist.localizedCaseInsensitiveCompare($1.artist)
                if artistCompare == .orderedSame {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return artistCompare == .orderedAscending
            }
        case .album:
            return filtered.sorted { optionalText($0.album, fallback: $0.title) < optionalText($1.album, fallback: $1.title) }
        case .year:
            return filtered.sorted { ($0.year ?? Int.min, $0.title.lowercased()) > ($1.year ?? Int.min, $1.title.lowercased()) }
        case .genre:
            return filtered.sorted { optionalText($0.genre, fallback: $0.title) < optionalText($1.genre, fallback: $1.title) }
        case .fileSize:
            return filtered.sorted {
                let left = fileSize(for: $0)
                let right = fileSize(for: $1)
                return left == right ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending : left > right
            }
        case .playCount:
            return filtered.sorted {
                $0.playCount == $1.playCount
                    ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    : $0.playCount > $1.playCount
            }
        }
    }

    private func optionalText(_ value: String?, fallback: String) -> String {
        (value?.isEmpty == false ? value! : "\u{10FFFF}\(fallback)").lowercased()
    }

    func fileSize(for item: LibraryItem) -> Int64 {
        let values = try? fileURL(for: item).resourceValues(forKeys: [.fileAllocatedSizeKey, .fileSizeKey])
        return Int64(values?.fileAllocatedSize ?? values?.fileSize ?? 0)
    }

    func isMissing(_ item: LibraryItem) -> Bool {
        !FileManager.default.fileExists(atPath: fileURL(for: item).path)
    }

    func importFiles(_ sourceURLs: [URL]) async {
        do {
            let destination = AppPaths.media
            let artworkDirectory = AppPaths.artwork
            let imported = try await Task.detached(priority: .userInitiated) {
                var newItems: [LibraryItem] = []
                try FileManager.default.createDirectory(
                    at: destination,
                    withIntermediateDirectories: true
                )
                try FileManager.default.createDirectory(
                    at: artworkDirectory,
                    withIntermediateDirectories: true
                )

                for sourceURL in sourceURLs {
                    let accessed = sourceURL.startAccessingSecurityScopedResource()
                    defer {
                        if accessed { sourceURL.stopAccessingSecurityScopedResource() }
                    }

                    let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .nameKey])
                    guard values.isRegularFile == true else { continue }

                    let ext = sourceURL.pathExtension.lowercased()
                    guard let type = UTType(filenameExtension: ext) else { continue }

                    let kind: MediaKind
                    if type.conforms(to: .audio) {
                        kind = .audio
                    } else if type.conforms(to: .movie) || type.conforms(to: .video) {
                        kind = .video
                    } else {
                        continue
                    }

                    let storedName = UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
                    let destinationURL = destination.appendingPathComponent(storedName)
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

                    guard await MediaMetadataExtractor.isPlayable(destinationURL) else {
                        try? FileManager.default.removeItem(at: destinationURL)
                        continue
                    }

                    let originalName = values.name ?? sourceURL.lastPathComponent
                    let fallbackTitle = sourceURL.deletingPathExtension().lastPathComponent
                    let metadata = await MediaMetadataExtractor.extract(from: destinationURL)
                    var artworkFilename: String?
                    if let artworkData = metadata.artworkData {
                        artworkFilename = try? MediaMetadataExtractor.saveArtwork(
                            artworkData,
                            to: artworkDirectory
                        )
                    }

                    newItems.append(
                        LibraryItem(
                            id: UUID(),
                            title: metadata.title?.isEmpty == false ? metadata.title! : fallbackTitle,
                            artist: metadata.artist?.isEmpty == false ? metadata.artist! : "Unknown Artist",
                            album: metadata.album,
                            genre: metadata.genre,
                            year: metadata.year,
                            trackNumber: metadata.trackNumber,
                            kind: kind,
                            localFilename: storedName,
                            originalFilename: originalName,
                            addedAt: Date(),
                            artworkFilename: artworkFilename,
                            normalizationGainDB: metadata.replayGainDB
                        )
                    )
                }
                return newItems
            }.value

            guard !imported.isEmpty else {
                lastError = "No supported audio or video files were selected."
                return
            }
            items.append(contentsOf: imported)
            items.sort { $0.addedAt > $1.addedAt }
            imported.forEach { registerArtist($0.artist) }
            save()
        } catch {
            lastError = "Import failed: \(error.localizedDescription)"
        }
    }

    /// Register a file the DownloadManager has already moved into the media directory.
    @discardableResult
    func adoptDownloadedFile(
        storedFilename: String,
        title: String,
        artist: String? = nil,
        kind: MediaKind,
        originalFilename: String,
        thumbnailURL: URL? = nil
    ) async -> UUID {
        let mediaURL = AppPaths.media.appendingPathComponent(storedFilename)
        let metadata = await MediaMetadataExtractor.extract(from: mediaURL)
        var artworkFilename: String?
        if let artworkData = metadata.artworkData {
            artworkFilename = try? MediaMetadataExtractor.saveArtwork(artworkData, to: AppPaths.artwork)
        }

        let confirmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let confirmedArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = LibraryItem(
            id: UUID(),
            title: Self.downloadedTitle(confirmed: confirmedTitle, embedded: metadata.title),
            artist: Self.downloadedArtist(confirmed: confirmedArtist, embedded: metadata.artist),
            album: metadata.album,
            genre: metadata.genre,
            year: metadata.year,
            trackNumber: metadata.trackNumber,
            kind: kind,
            localFilename: storedFilename,
            originalFilename: originalFilename,
            addedAt: Date(),
            artworkFilename: artworkFilename,
            normalizationGainDB: metadata.replayGainDB
        )
        items.insert(item, at: 0)
        items.sort { $0.addedAt > $1.addedAt }
        registerArtist(item.artist)
        save()

        // Thumbnail enrichment is optional. The durable library entry above must exist
        // before the background-session completion handler is released.
        if artworkFilename == nil, let thumbnailURL {
            Task { [weak self] in
                guard let self, let downloaded = await downloadArtwork(from: thumbnailURL),
                      let index = items.firstIndex(where: { $0.id == item.id }) else { return }
                items[index].artworkFilename = downloaded
                clearArtworkCache()
                save()
            }
        }
        return item.id
    }

    static func downloadedTitle(confirmed: String, embedded: String?) -> String {
        if !confirmed.isEmpty { return confirmed }
        if let embedded, !embedded.isEmpty { return embedded }
        return "Untitled"
    }

    static func downloadedArtist(confirmed: String?, embedded: String?) -> String {
        if let confirmed, !confirmed.isEmpty { return confirmed }
        if let embedded, !embedded.isEmpty { return embedded }
        return "Unknown Artist"
    }

    func setArtwork(for item: LibraryItem, from sourceURL: URL) async {
        do {
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessed { sourceURL.stopAccessingSecurityScopedResource() }
            }

            let data = try Data(contentsOf: sourceURL)
            let filename = try MediaMetadataExtractor.saveArtwork(data, to: AppPaths.artwork)
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

            if let previous = items[index].artworkFilename {
                try? FileManager.default.removeItem(at: AppPaths.artwork.appendingPathComponent(previous))
            }
            items[index].artworkFilename = filename
            clearArtworkCache()
            save()
        } catch {
            lastError = "Cover image could not be saved: \(error.localizedDescription)"
        }
    }

    func update(
        _ item: LibraryItem,
        title: String,
        artist: String,
        album: String?,
        genre: String?,
        year: Int?,
        trackNumber: Int?,
        tags: [String]? = nil
    ) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let cleanedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].artist = cleanedArtist
        items[index].album = Self.cleanedOptional(album)
        items[index].genre = Self.cleanedOptional(genre)
        items[index].year = year
        items[index].trackNumber = trackNumber
        if let tags { items[index].tags = Self.cleanedTags(tags) }
        registerArtist(cleanedArtist)
        save()
    }

    private static func cleanedTags(_ tags: [String]) -> [String] {
        var result: [String] = []
        for tag in tags {
            let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty,
                  !result.contains(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame }) else { continue }
            result.append(cleaned)
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func bulkUpdate(
        itemIDs: Set<UUID>, artist: String?, album: String?, genre: String?,
        year: Int?, tags: [String]?, replaceTags: Bool
    ) {
        guard !itemIDs.isEmpty else { return }
        for index in items.indices where itemIDs.contains(items[index].id) {
            if let artist = Self.cleanedOptional(artist) { items[index].artist = artist; registerArtist(artist) }
            if let album = Self.cleanedOptional(album) { items[index].album = album }
            if let genre = Self.cleanedOptional(genre) { items[index].genre = genre }
            if let year { items[index].year = year }
            if let tags {
                items[index].tags = Self.cleanedTags(replaceTags ? tags : items[index].tags + tags)
            }
        }
        save()
    }

    private static func cleanedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    func registerArtist(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isUsefulArtist(trimmed) else { return }
        guard !knownArtists.contains(where: {
            $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) else { return }
        knownArtists.append(trimmed)
        knownArtists.sort {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    func filteredArtists(matching query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return knownArtists }
        return knownArtists.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    private static func isUsefulArtist(_ name: String) -> Bool {
        !name.isEmpty && name.localizedCaseInsensitiveCompare("Unknown Artist") != .orderedSame
    }

    private func seedKnownArtists(from persisted: [String]) {
        knownArtists = persisted
        for item in items {
            registerArtist(item.artist)
        }
    }

    func delete(_ item: LibraryItem) {
        try? FileManager.default.removeItem(at: fileURL(for: item))
        if let artworkFilename = item.artworkFilename {
            try? FileManager.default.removeItem(at: AppPaths.artwork.appendingPathComponent(artworkFilename))
        }
        items.removeAll { $0.id == item.id }
        clearArtworkCache()
        recentlyPlayedIDs.removeAll { $0 == item.id }
        for index in playlists.indices {
            playlists[index].itemIDs.removeAll { $0 == item.id }
        }
        save()
    }

    func createPlaylist(named name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        playlists.append(Playlist(id: UUID(), name: cleaned, itemIDs: [], createdAt: Date()))
        save()
    }

    /// Returns a stable destination for a bulk import, reusing a playlist with the
    /// same name so repeated imports don't create visually identical playlists.
    @discardableResult
    func ensurePlaylist(named name: String) -> UUID? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if let existing = playlists.first(where: {
            $0.name.caseInsensitiveCompare(cleaned) == .orderedSame
        }) {
            return existing.id
        }
        let playlist = Playlist(id: UUID(), name: cleaned, itemIDs: [], createdAt: Date())
        playlists.append(playlist)
        save()
        return playlist.id
    }

    func add(itemID: UUID, toPlaylistID playlistID: UUID, at position: Int? = nil) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }),
              items.contains(where: { $0.id == itemID }),
              !playlists[index].itemIDs.contains(itemID) else { return }
        if let position {
            playlists[index].itemIDs.insert(
                itemID,
                at: min(max(position, 0), playlists[index].itemIDs.count)
            )
        } else {
            playlists[index].itemIDs.append(itemID)
        }
        save()
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        save()
    }

    func add(_ item: LibraryItem, to playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        guard !playlists[index].itemIDs.contains(item.id) else { return }
        playlists[index].itemIDs.append(item.id)
        save()
    }

    func remove(_ item: LibraryItem, from playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].itemIDs.removeAll { $0 == item.id }
        save()
    }

    func items(in playlist: Playlist) -> [LibraryItem] {
        playlist.itemIDs.compactMap { id in items.first(where: { $0.id == id }) }
    }

    func itemCount(inPlaylistID playlistID: UUID) -> Int {
        playlists.first(where: { $0.id == playlistID })?.itemIDs.count ?? 0
    }

    func backupSnapshot() -> PersistedLibrary {
        PersistedLibrary(
            items: items,
            playlists: playlists,
            recentlyPlayedIDs: recentlyPlayedIDs,
            knownArtists: knownArtists
        )
    }

    func reloadAfterRestore() {
        items = []
        playlists = []
        recentlyPlayedIDs = []
        knownArtists = []
        lastError = nil
        clearArtworkCache()
        load()
    }

    func storageReport() async -> StorageReport {
        let snapshot = items
        return await Task.detached(priority: .utility) {
            LibraryStorageScanner.scan(
                items: snapshot,
                mediaDirectory: AppPaths.media,
                artworkDirectory: AppPaths.artwork,
                metadataFiles: [AppPaths.libraryFile, AppPaths.downloadsFile]
            )
        }.value
    }

    func cleanOrphanedStorage(_ report: StorageReport) async -> StorageCleanupResult {
        let result = await Task.detached(priority: .utility) {
            LibraryStorageScanner.removeOrphans(report.orphanedFiles)
        }.value
        clearArtworkCache()
        if !result.errors.isEmpty {
            lastError = "Some unused files could not be removed: \(result.errors.first ?? "Unknown error")"
        }
        return result
    }

    func maintenanceReport() async -> LibraryMaintenanceReport {
        let snapshot = items
        return await Task.detached(priority: .utility) {
            LibraryMaintenanceScanner.scan(items: snapshot, mediaDirectory: AppPaths.media)
        }.value
    }

    func removeMissingRecords() {
        let missingIDs = Set(items.filter(isMissing).map(\.id))
        guard !missingIDs.isEmpty else { return }
        items.removeAll { missingIDs.contains($0.id) }
        recentlyPlayedIDs.removeAll { missingIDs.contains($0) }
        for index in playlists.indices { playlists[index].itemIDs.removeAll { missingIDs.contains($0) } }
        save()
    }

    @discardableResult
    func repairMissingItem(itemID: UUID, from sourceURL: URL) async -> Bool {
        guard let item = items.first(where: { $0.id == itemID }), isMissing(item) else { return false }
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
        let destination = fileURL(for: item)
        let staging = AppPaths.media.appendingPathComponent("repair-\(UUID().uuidString).tmp")
        do {
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: AppPaths.media, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: sourceURL, to: staging)
            }.value
            guard await MediaMetadataExtractor.isPlayable(staging) else {
                try? FileManager.default.removeItem(at: staging)
                lastError = "The selected replacement is not a playable audio or video file."
                return false
            }
            try FileManager.default.moveItem(at: staging, to: destination)
            _ = await rescanEmbeddedMetadata(itemIDs: Set([itemID]))
            return true
        } catch {
            try? FileManager.default.removeItem(at: staging)
            lastError = "The missing file could not be repaired: \(error.localizedDescription)"
            return false
        }
    }

    func removeDuplicates(keeping keepIDs: Set<UUID>, from report: LibraryMaintenanceReport) {
        let duplicateIDs = Set(report.duplicateGroups.flatMap(\.items).map(\.id))
        let removals = items.filter { duplicateIDs.contains($0.id) && !keepIDs.contains($0.id) }
        removals.forEach(delete)
    }

    @discardableResult
    func rescanEmbeddedMetadata(itemIDs: Set<UUID>? = nil) async -> Int {
        let targets = items.filter { itemIDs == nil || itemIDs!.contains($0.id) }.filter { !isMissing($0) }
        var changed = 0
        for target in targets {
            let metadata = await MediaMetadataExtractor.extract(from: fileURL(for: target))
            guard let index = items.firstIndex(where: { $0.id == target.id }) else { continue }
            let before = items[index]
            if (before.title == "Untitled" || before.title.isEmpty), let value = metadata.title, !value.isEmpty { items[index].title = value }
            if before.artist == "Unknown Artist", let value = metadata.artist, !value.isEmpty { items[index].artist = value }
            if let value = metadata.album { items[index].album = value }
            if let value = metadata.genre { items[index].genre = value }
            if let value = metadata.year { items[index].year = value }
            if let value = metadata.trackNumber { items[index].trackNumber = value }
            if let value = metadata.replayGainDB { items[index].normalizationGainDB = value }
            if items[index].artworkFilename == nil, let data = metadata.artworkData {
                items[index].artworkFilename = try? MediaMetadataExtractor.saveArtwork(data, to: AppPaths.artwork)
            }
            if items[index] != before { changed += 1 }
        }
        if changed > 0 { clearArtworkCache(); save() }
        return changed
    }

    private func downloadArtwork(from url: URL) async -> String? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return try MediaMetadataExtractor.saveArtwork(data, to: AppPaths.artwork)
        } catch {
            return nil
        }
    }

    private func load() {
        AppPaths.ensureDirectories()
        do {
            guard FileManager.default.fileExists(atPath: AppPaths.libraryFile.path) else { return }
            let data = try Data(contentsOf: AppPaths.libraryFile)
            let persisted = try JSONDecoder.musico.decode(PersistedLibrary.self, from: data)
            // Keep missing records so Library Maintenance can repair or remove them.
            items = persisted.items
            playlists = persisted.playlists
            recentlyPlayedIDs = persisted.recentlyPlayedIDs.filter { id in
                items.contains(where: { $0.id == id })
            }
            seedKnownArtists(from: persisted.knownArtists)
        } catch {
            lastError = "The saved library could not be loaded: \(error.localizedDescription)"
        }
    }

    private func save() {
        AppPaths.ensureDirectories()
        do {
            let data = try JSONEncoder.musico.encode(
                PersistedLibrary(
                    items: items,
                    playlists: playlists,
                    recentlyPlayedIDs: recentlyPlayedIDs,
                    knownArtists: knownArtists
                )
            )
            try data.write(to: AppPaths.libraryFile, options: .atomic)
        } catch {
            lastError = "Changes could not be saved: \(error.localizedDescription)"
        }
    }
}

struct StorageReport: Equatable {
    struct ItemUsage: Identifiable, Equatable {
        let id: UUID
        let title: String
        let artist: String
        let bytes: Int64
    }

    struct OrphanFile: Identifiable, Equatable {
        enum Category: String {
            case media = "Media"
            case artwork = "Artwork"
        }

        var id: String { url.path }
        let url: URL
        let bytes: Int64
        let category: Category
    }

    var mediaBytes: Int64
    var artworkBytes: Int64
    var metadataBytes: Int64
    var itemUsage: [ItemUsage]
    var orphanedFiles: [OrphanFile]

    static let empty = StorageReport(
        mediaBytes: 0,
        artworkBytes: 0,
        metadataBytes: 0,
        itemUsage: [],
        orphanedFiles: []
    )

    var totalBytes: Int64 { mediaBytes + artworkBytes + metadataBytes }
    var reclaimableBytes: Int64 { orphanedFiles.reduce(0) { $0 + $1.bytes } }
}

struct StorageCleanupResult: Equatable {
    var removedFiles: Int
    var reclaimedBytes: Int64
    var errors: [String]
}

struct LibraryMaintenanceReport: Equatable {
    struct MissingItem: Identifiable, Equatable {
        let id: UUID
        let title: String
        let filename: String
    }

    struct DuplicateItem: Identifiable, Equatable {
        let id: UUID
        let title: String
        let artist: String
        let bytes: Int64
        let addedAt: Date
    }

    struct DuplicateGroup: Identifiable, Equatable {
        let id: String
        let items: [DuplicateItem]
        let bytesPerFile: Int64

        var reclaimableBytes: Int64 { bytesPerFile * Int64(max(items.count - 1, 0)) }
        var suggestedKeepID: UUID? {
            items.sorted {
                if $0.addedAt != $1.addedAt { return $0.addedAt < $1.addedAt }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }.first?.id
        }
    }

    var missingItems: [MissingItem]
    var duplicateGroups: [DuplicateGroup]

    static let empty = LibraryMaintenanceReport(missingItems: [], duplicateGroups: [])
    var duplicateReclaimableBytes: Int64 { duplicateGroups.reduce(0) { $0 + $1.reclaimableBytes } }
}

enum LibraryMaintenanceScanner {
    static func scan(
        items: [LibraryItem],
        mediaDirectory: URL,
        fileManager: FileManager = .default
    ) -> LibraryMaintenanceReport {
        var missing: [LibraryMaintenanceReport.MissingItem] = []
        var candidatesBySize: [Int64: [(LibraryItem, URL)]] = [:]

        for item in items {
            let url = mediaDirectory.appendingPathComponent(item.localFilename)
            guard fileManager.fileExists(atPath: url.path) else {
                missing.append(.init(id: item.id, title: item.title, filename: item.originalFilename))
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, let size = values?.fileSize else { continue }
            candidatesBySize[Int64(size), default: []].append((item, url))
        }

        var groups: [LibraryMaintenanceReport.DuplicateGroup] = []
        for (size, candidates) in candidatesBySize where candidates.count > 1 {
            var byDigest: [String: [(LibraryItem, URL)]] = [:]
            for candidate in candidates {
                guard let digest = sha256(candidate.1) else { continue }
                byDigest[digest, default: []].append(candidate)
            }
            for (digest, matches) in byDigest where matches.count > 1 {
                groups.append(.init(
                    id: digest,
                    items: matches.map {
                        .init(id: $0.0.id, title: $0.0.title, artist: $0.0.artist, bytes: size, addedAt: $0.0.addedAt)
                    },
                    bytesPerFile: size
                ))
            }
        }

        return LibraryMaintenanceReport(
            missingItems: missing.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending },
            duplicateGroups: groups.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
        )
    }

    private static func sha256(_ url: URL) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }
        var hasher = SHA256()
        let capacity = 256 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: capacity)
            if count < 0 { return nil }
            if count == 0 { break }
            hasher.update(data: Data(bytes: buffer, count: count))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum LibraryStorageScanner {
    static let orphanGraceInterval: TimeInterval = 60 * 60

    static func scan(
        items: [LibraryItem],
        mediaDirectory: URL,
        artworkDirectory: URL,
        metadataFiles: [URL],
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> StorageReport {
        let mediaFiles = regularFiles(in: mediaDirectory, fileManager: fileManager)
        let artworkFiles = regularFiles(in: artworkDirectory, fileManager: fileManager)
        let referencedMedia = Set(items.map(\.localFilename))
        let referencedArtwork = Set(items.compactMap(\.artworkFilename))
        let cutoff = now.addingTimeInterval(-orphanGraceInterval)

        let mediaSizes = Dictionary(uniqueKeysWithValues: mediaFiles.map { ($0.url.lastPathComponent, $0.bytes) })
        let itemUsage = items.compactMap { item -> StorageReport.ItemUsage? in
            guard let bytes = mediaSizes[item.localFilename] else { return nil }
            return StorageReport.ItemUsage(
                id: item.id,
                title: item.title,
                artist: item.artist,
                bytes: bytes
            )
        }.sorted { $0.bytes > $1.bytes }

        let orphanedMedia = mediaFiles.compactMap { file -> StorageReport.OrphanFile? in
            guard !referencedMedia.contains(file.url.lastPathComponent),
                  file.modifiedAt <= cutoff else { return nil }
            return StorageReport.OrphanFile(url: file.url, bytes: file.bytes, category: .media)
        }
        let orphanedArtwork = artworkFiles.compactMap { file -> StorageReport.OrphanFile? in
            guard !referencedArtwork.contains(file.url.lastPathComponent),
                  file.modifiedAt <= cutoff else { return nil }
            return StorageReport.OrphanFile(url: file.url, bytes: file.bytes, category: .artwork)
        }

        return StorageReport(
            mediaBytes: mediaFiles.reduce(0) { $0 + $1.bytes },
            artworkBytes: artworkFiles.reduce(0) { $0 + $1.bytes },
            metadataBytes: metadataFiles.reduce(0) { $0 + fileSize(at: $1, fileManager: fileManager) },
            itemUsage: itemUsage,
            orphanedFiles: (orphanedMedia + orphanedArtwork).sorted { $0.bytes > $1.bytes }
        )
    }

    static func removeOrphans(
        _ files: [StorageReport.OrphanFile],
        fileManager: FileManager = .default
    ) -> StorageCleanupResult {
        var result = StorageCleanupResult(removedFiles: 0, reclaimedBytes: 0, errors: [])
        for file in files {
            do {
                try fileManager.removeItem(at: file.url)
                result.removedFiles += 1
                result.reclaimedBytes += file.bytes
            } catch {
                result.errors.append("\(file.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return result
    }

    private struct ScannedFile {
        let url: URL
        let bytes: Int64
        let modifiedAt: Date
    }

    private static func regularFiles(
        in directory: URL,
        fileManager: FileManager
    ) -> [ScannedFile] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileAllocatedSizeKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else { return nil }
            return ScannedFile(
                url: url,
                bytes: Int64(values.fileAllocatedSize ?? values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }
    }

    private static func fileSize(at url: URL, fileManager: FileManager) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileAllocatedSizeKey, .fileSizeKey]) else {
            return 0
        }
        return Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
    }
}
