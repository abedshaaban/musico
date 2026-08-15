import Foundation
import UniformTypeIdentifiers

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var items: [LibraryItem] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published var lastError: String?

    init() {
        load()
    }

    func fileURL(for item: LibraryItem) -> URL {
        AppPaths.media.appendingPathComponent(item.localFilename)
    }

    func importFiles(_ sourceURLs: [URL]) async {
        do {
            let destination = AppPaths.media
            let imported = try await Task.detached(priority: .userInitiated) {
                var newItems: [LibraryItem] = []
                try FileManager.default.createDirectory(
                    at: destination,
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

                    let originalName = values.name ?? sourceURL.lastPathComponent
                    let displayName = sourceURL.deletingPathExtension().lastPathComponent
                    newItems.append(
                        LibraryItem(
                            id: UUID(),
                            title: displayName,
                            artist: "Unknown Artist",
                            kind: kind,
                            localFilename: storedName,
                            originalFilename: originalName,
                            addedAt: Date()
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
            save()
        } catch {
            lastError = "Import failed: \(error.localizedDescription)"
        }
    }

    /// Register a file the DownloadManager has already moved into the media directory.
    func adoptDownloadedFile(storedFilename: String, title: String, kind: MediaKind, originalFilename: String) {
        let item = LibraryItem(
            id: UUID(),
            title: title.isEmpty ? "Untitled" : title,
            artist: "Unknown Artist",
            kind: kind,
            localFilename: storedFilename,
            originalFilename: originalFilename,
            addedAt: Date()
        )
        items.insert(item, at: 0)
        items.sort { $0.addedAt > $1.addedAt }
        save()
    }

    func update(_ item: LibraryItem, title: String, artist: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    func delete(_ item: LibraryItem) {
        try? FileManager.default.removeItem(at: fileURL(for: item))
        items.removeAll { $0.id == item.id }
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

    private func load() {
        AppPaths.ensureDirectories()
        do {
            guard FileManager.default.fileExists(atPath: AppPaths.libraryFile.path) else { return }
            let data = try Data(contentsOf: AppPaths.libraryFile)
            let persisted = try JSONDecoder.musico.decode(PersistedLibrary.self, from: data)
            items = persisted.items.filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
            playlists = persisted.playlists
        } catch {
            lastError = "The saved library could not be loaded: \(error.localizedDescription)"
        }
    }

    private func save() {
        AppPaths.ensureDirectories()
        do {
            let data = try JSONEncoder.musico.encode(PersistedLibrary(items: items, playlists: playlists))
            try data.write(to: AppPaths.libraryFile, options: .atomic)
        } catch {
            lastError = "Changes could not be saved: \(error.localizedDescription)"
        }
    }
}
