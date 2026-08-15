import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackController
    @AppStorage("librarySort") private var sortRaw = LibrarySortOption.dateAdded.rawValue
    @AppStorage("libraryKindFilter") private var filterRaw = MediaKindFilter.all.rawValue
    @State private var isCreatingPlaylist = false
    @State private var playlistName = ""
    @State private var isImporterPresented = false
    @State private var isImporting = false
    @State private var searchText = ""
    @State private var artworkTargetItem: LibraryItem?
    @State private var isArtworkImporterPresented = false
    @State private var editingItem: LibraryItem?
    @State private var isStoragePresented = false

    private var sortOption: LibrarySortOption {
        LibrarySortOption(rawValue: sortRaw) ?? .dateAdded
    }

    private var kindFilter: MediaKindFilter {
        MediaKindFilter(rawValue: filterRaw) ?? .all
    }

    private var searchedItems: [LibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return library.items }
        return library.items.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.artist.localizedCaseInsensitiveContains(query) ||
            $0.album?.localizedCaseInsensitiveContains(query) == true ||
            $0.genre?.localizedCaseInsensitiveContains(query) == true ||
            $0.year.map(String.init)?.localizedCaseInsensitiveContains(query) == true ||
            $0.originalFilename.localizedCaseInsensitiveContains(query)
        }
    }

    private var displayedItems: [LibraryItem] {
        library.sortedItems(searchedItems, by: sortOption, filter: kindFilter)
    }

    private var recentlyPlayed: [LibraryItem] {
        library.recentlyPlayedItems()
    }

    var body: some View {
        NavigationView {
            List {
                if !recentlyPlayed.isEmpty && searchText.isEmpty {
                    Section("Recently Played") {
                        ForEach(recentlyPlayed.prefix(10)) { item in
                            MediaRow(item: item)
                                .padding(.vertical, 8)
                                .musicoFullBleedSwipeRow()
                                .musicoLibraryRowTap {
                                    playback.play(item, from: recentlyPlayed, fileURL: library.fileURL)
                                }
                                .musicoMediaSwipeActions(
                                    onEdit: { editingItem = item },
                                    onDelete: {
                                        if playback.currentItem?.id == item.id { playback.stop() }
                                        library.delete(item)
                                    }
                                )
                        }
                    }
                }

                Section("Playlists") {
                    if library.playlists.isEmpty {
                        Text("No playlists yet")
                            .foregroundColor(.secondary)
                    }
                    ForEach(library.playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlistID: playlist.id)
                        } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(playlist.name)
                                    Text("\(playlist.itemIDs.count) items")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: "music.note.list")
                            }
                        }
                        .musicoFullBleedSwipeRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                library.deletePlaylist(playlist)
                            } label: {
                                Text("Delete")
                            }
                        }
                    }
                }

                Section("All Media") {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label(isImporting ? "Importing…" : "Import from Files", systemImage: "folder.badge.plus")
                    }
                    .disabled(isImporting)

                    if library.items.isEmpty {
                        Text("Import audio or video files from this iPhone, iCloud Drive, or another Files location, or download a link from the Add tab.")
                            .foregroundColor(.secondary)
                    } else if displayedItems.isEmpty {
                        Text(emptyResultsMessage)
                            .foregroundColor(.secondary)
                    }
                    ForEach(displayedItems) { item in
                        MediaRow(item: item)
                            .padding(.vertical, 8)
                            .musicoFullBleedSwipeRow()
                            .musicoLibraryRowTap {
                                playback.play(item, from: displayedItems, fileURL: library.fileURL)
                            }
                            .contextMenu {
                                Button {
                                    editingItem = item
                                } label: {
                                    Label("Edit Metadata", systemImage: "pencil")
                                }
                                if !library.playlists.isEmpty {
                                    Menu("Add to Playlist") {
                                        ForEach(library.playlists) { playlist in
                                            Button(playlist.name) { library.add(item, to: playlist) }
                                        }
                                    }
                                }
                                Button {
                                    artworkTargetItem = item
                                    isArtworkImporterPresented = true
                                } label: {
                                    Label("Set Cover Image", systemImage: "photo")
                                }
                                Button(role: .destructive) {
                                    if playback.currentItem?.id == item.id { playback.stop() }
                                    library.delete(item)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .musicoMediaSwipeActions(
                                onEdit: { editingItem = item },
                                onDelete: {
                                    if playback.currentItem?.id == item.id { playback.stop() }
                                    library.delete(item)
                                }
                            )
                    }
                }
            }
            .musicoPlainLibraryListStyle()
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search title, artist, album, genre, or year")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Menu("Sort By") {
                            ForEach(LibrarySortOption.allCases) { option in
                                Button {
                                    sortRaw = option.rawValue
                                } label: {
                                    if sortOption == option {
                                        Label(option.label, systemImage: "checkmark")
                                    } else {
                                        Text(option.label)
                                    }
                                }
                            }
                        }
                        Menu("Show") {
                            ForEach(MediaKindFilter.allCases) { option in
                                Button {
                                    filterRaw = option.rawValue
                                } label: {
                                    if kindFilter == option {
                                        Label(option.label, systemImage: "checkmark")
                                    } else {
                                        Text(option.label)
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Sort and Filter")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { isStoragePresented = true } label: {
                        Image(systemName: "internaldrive")
                    }
                    .accessibilityLabel("Storage Management")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { isCreatingPlaylist = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Playlist")
                }
            }
            .sheet(isPresented: $isCreatingPlaylist) {
                NavigationView {
                    Form {
                        TextField(musicoPrompt: "Playlist name", text: $playlistName)
                            .musicoFormTextField()
                    }
                    .navigationTitle("New Playlist")
                    .musicoInlineNavigationTitle()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { closePlaylistSheet() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Create") {
                                library.createPlaylist(named: playlistName)
                                closePlaylistSheet()
                            }
                            .disabled(playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .sheet(item: $editingItem) { item in
                EditItemSheet(item: item)
            }
            .sheet(isPresented: $isStoragePresented) {
                StorageManagementView()
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.audio, .movie],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    isImporting = true
                    Task {
                        await library.importFiles(urls)
                        isImporting = false
                    }
                case .failure(let error):
                    library.lastError = "The file picker failed: \(error.localizedDescription)"
                }
            }
            .fileImporter(
                isPresented: $isArtworkImporterPresented,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                guard let item = artworkTargetItem else { return }
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await library.setArtwork(for: item, from: url) }
                case .failure(let error):
                    library.lastError = "The image picker failed: \(error.localizedDescription)"
                }
                artworkTargetItem = nil
            }
            .alert("Musico", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { library.lastError = nil }
            } message: {
                Text(library.lastError ?? "Unknown error")
            }
        }
        .musicoStackNavigationStyle()
    }

    private var emptyResultsMessage: String {
        if !searchText.isEmpty {
            return "No matches for \"\(searchText)\"."
        }
        switch kindFilter {
        case .audio: return "No audio files in your library."
        case .video: return "No video files in your library."
        case .all: return "No media found."
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { library.lastError != nil },
            set: { if !$0 { library.lastError = nil } }
        )
    }

    private func closePlaylistSheet() {
        playlistName = ""
        isCreatingPlaylist = false
    }
}

private struct StorageManagementView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss
    @State private var report = StorageReport.empty
    @State private var isScanning = true
    @State private var isCleaning = false
    @State private var confirmsCleanup = false
    @State private var cleanupMessage: String?
    @State private var deletionTarget: StorageReport.ItemUsage?

    var body: some View {
        NavigationView {
            List {
                Section("Managed Storage") {
                    storageRow("Media", bytes: report.mediaBytes, icon: "music.note")
                    storageRow("Artwork", bytes: report.artworkBytes, icon: "photo")
                    storageRow("Library Data", bytes: report.metadataBytes, icon: "doc.text")
                    storageRow("Total", bytes: report.totalBytes, icon: "internaldrive")
                }

                Section {
                    HStack {
                        Label("Unused Files", systemImage: "trash")
                        Spacer()
                        Text("\(report.orphanedFiles.count)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Reclaimable")
                        Spacer()
                        Text(Self.bytes(report.reclaimableBytes))
                            .foregroundColor(.secondary)
                    }
                    Button(role: .destructive) {
                        confirmsCleanup = true
                    } label: {
                        Label(isCleaning ? "Cleaning…" : "Remove Unused Files", systemImage: "trash")
                    }
                    .disabled(report.orphanedFiles.isEmpty || isCleaning)

                    if let cleanupMessage {
                        Text(cleanupMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Cleanup")
                } footer: {
                    Text("Musico only offers files that are not referenced by the library and are at least one hour old. Active downloads and recently created artwork are protected.")
                }

                Section("Largest Files") {
                    if report.itemUsage.isEmpty {
                        Text(isScanning ? "Scanning library…" : "No media files found.")
                            .foregroundColor(.secondary)
                    }
                    ForEach(Array(report.itemUsage.prefix(20))) { usage in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(usage.title)
                                    .lineLimit(1)
                                Text(usage.artist)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(Self.bytes(usage.bytes))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                            Button(role: .destructive) {
                                deletionTarget = usage
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete \(usage.title)")
                        }
                    }
                }
            }
            .navigationTitle("Storage")
            .musicoInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isScanning || isCleaning)
                    .accessibilityLabel("Refresh Storage")
                }
            }
            .overlay {
                if isScanning && report == .empty {
                    ProgressView("Scanning…")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .confirmationDialog(
                "Remove unused files?",
                isPresented: $confirmsCleanup,
                titleVisibility: .visible
            ) {
                Button("Remove \(report.orphanedFiles.count) Files", role: .destructive) {
                    clean()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will reclaim approximately \(Self.bytes(report.reclaimableBytes)).")
            }
            .alert(item: $deletionTarget) { usage in
                Alert(
                    title: Text("Delete \(usage.title)?"),
                    message: Text("This removes the item and its media file, reclaiming approximately \(Self.bytes(usage.bytes))."),
                    primaryButton: .destructive(Text("Delete")) {
                        deleteItem(usage)
                    },
                    secondaryButton: .cancel()
                )
            }
            .task { await loadReport() }
        }
        .musicoStackNavigationStyle()
    }

    @ViewBuilder
    private func storageRow(_ title: String, bytes: Int64, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(Self.bytes(bytes))
                .foregroundColor(.secondary)
        }
    }

    private func refresh() {
        guard !isScanning else { return }
        isScanning = true
        Task { await loadReport() }
    }

    @MainActor
    private func loadReport() async {
        report = await library.storageReport()
        isScanning = false
    }

    private func clean() {
        guard !isCleaning else { return }
        isCleaning = true
        cleanupMessage = nil
        Task {
            let result = await library.cleanOrphanedStorage(report)
            cleanupMessage = result.removedFiles == 0
                ? "No files were removed."
                : "Removed \(result.removedFiles) files and reclaimed \(Self.bytes(result.reclaimedBytes))."
            report = await library.storageReport()
            isCleaning = false
        }
    }

    private func deleteItem(_ usage: StorageReport.ItemUsage) {
        guard let item = library.items.first(where: { $0.id == usage.id }) else {
            refresh()
            return
        }
        if playback.currentItem?.id == item.id { playback.stop() }
        library.delete(item)
        cleanupMessage = "Deleted \(usage.title) and reclaimed approximately \(Self.bytes(usage.bytes))."
        refresh()
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackController
    let playlistID: UUID
    @AppStorage("librarySort") private var sortRaw = LibrarySortOption.dateAdded.rawValue
    @State private var searchText = ""
    @State private var editingItem: LibraryItem?

    private var playlist: Playlist? {
        library.playlists.first { $0.id == playlistID }
    }

    private var items: [LibraryItem] {
        guard let playlist else { return [] }
        return library.items(in: playlist)
    }

    private var sortOption: LibrarySortOption {
        LibrarySortOption(rawValue: sortRaw) ?? .dateAdded
    }

    private var filteredItems: [LibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched: [LibraryItem]
        if query.isEmpty {
            searched = items
        } else {
            searched = items.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.artist.localizedCaseInsensitiveContains(query) ||
                ($0.album?.localizedCaseInsensitiveContains(query) ?? false) ||
                ($0.genre?.localizedCaseInsensitiveContains(query) ?? false) ||
                ($0.year.map(String.init)?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        return library.sortedItems(searched, by: sortOption, filter: .all)
    }

    var body: some View {
        List {
            if !items.isEmpty {
                Section {
                    Button {
                        guard let first = filteredItems.first ?? items.first else { return }
                        playback.play(first, from: filteredItems.isEmpty ? items : filteredItems, fileURL: library.fileURL)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        let pool = filteredItems.isEmpty ? items : filteredItems
                        guard let random = pool.randomElement() else { return }
                        if !playback.isShuffleEnabled { playback.toggleShuffle() }
                        playback.play(random, from: pool, fileURL: library.fileURL)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            Section {
                if items.isEmpty {
                    Text("Add media from the Library by touching and holding an item.")
                        .foregroundColor(.secondary)
                } else if filteredItems.isEmpty {
                    Text("No matches for \"\(searchText)\".")
                        .foregroundColor(.secondary)
                }
                ForEach(filteredItems) { item in
                    MediaRow(item: item)
                        .padding(.vertical, 8)
                        .musicoFullBleedSwipeRow()
                        .musicoLibraryRowTap {
                            playback.play(item, from: filteredItems, fileURL: library.fileURL)
                        }
                        .contextMenu {
                            Button {
                                editingItem = item
                            } label: {
                                Label("Edit Metadata", systemImage: "pencil")
                            }
                        }
                        .musicoMediaSwipeActions(
                            onEdit: { editingItem = item },
                            deleteLabel: "Remove",
                            onDelete: { library.remove(item, from: playlistID) }
                        )
                }
            }
        }
        .musicoPlainLibraryListStyle()
        .navigationTitle(playlist?.name ?? "Playlist")
        .searchable(text: $searchText, prompt: "Search title, artist, album, genre, or year")
        .sheet(item: $editingItem) { item in
            EditItemSheet(item: item)
        }
    }
}
