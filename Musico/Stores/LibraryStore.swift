import Foundation
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
        if recentlyPlayedIDs.count > 30 {
            recentlyPlayedIDs = Array(recentlyPlayedIDs.prefix(30))
        }
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
        }
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
                            kind: kind,
                            localFilename: storedName,
                            originalFilename: originalName,
                            addedAt: Date(),
                            artworkFilename: artworkFilename
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
    func adoptDownloadedFile(
        storedFilename: String,
        title: String,
        kind: MediaKind,
        originalFilename: String,
        thumbnailURL: URL? = nil
    ) async {
        let mediaURL = AppPaths.media.appendingPathComponent(storedFilename)
        let metadata = await MediaMetadataExtractor.extract(from: mediaURL)
        var artworkFilename: String?
        if let artworkData = metadata.artworkData {
            artworkFilename = try? MediaMetadataExtractor.saveArtwork(artworkData, to: AppPaths.artwork)
        }

        let item = LibraryItem(
            id: UUID(),
            title: metadata.title?.isEmpty == false ? metadata.title! : (title.isEmpty ? "Untitled" : title),
            artist: metadata.artist?.isEmpty == false ? metadata.artist! : "Unknown Artist",
            kind: kind,
            localFilename: storedFilename,
            originalFilename: originalFilename,
            addedAt: Date(),
            artworkFilename: artworkFilename
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

    func update(_ item: LibraryItem, title: String, artist: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let cleanedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].artist = cleanedArtist
        registerArtist(cleanedArtist)
        save()
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
            items = persisted.items.filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
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
