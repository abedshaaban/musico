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
                                .musicoLibraryRowTap {
                                    playback.play(item, from: recentlyPlayed, fileURL: library.fileURL)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        editingItem = item
                                    } label: {
                                        Text("Edit")
                                    }
                                    .tint(.blue)

                                    Button(role: .destructive) {
                                        if playback.currentItem?.id == item.id { playback.stop() }
                                        library.delete(item)
                                    } label: {
                                        Text("Delete")
                                    }
                                }
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
                            .musicoLibraryRowTap {
                                playback.play(item, from: displayedItems, fileURL: library.fileURL)
                            }
                            .contextMenu {
                                Button {
                                    editingItem = item
                                } label: {
                                    Label("Edit Title & Artist", systemImage: "pencil")
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    editingItem = item
                                } label: {
                                    Text("Edit")
                                }
                                .tint(.blue)

                                Button(role: .destructive) {
                                    if playback.currentItem?.id == item.id { playback.stop() }
                                    library.delete(item)
                                } label: {
                                    Text("Delete")
                                }
                            }
                    }
                }
            }
            .musicoInsetGroupedListStyle()
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search by title or artist")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Sort By", selection: $sortRaw) {
                            ForEach(LibrarySortOption.allCases) { option in
                                Text(option.label).tag(option.rawValue)
                            }
                        }
                        Picker("Show", selection: $filterRaw) {
                            ForEach(MediaKindFilter.allCases) { option in
                                Text(option.label).tag(option.rawValue)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Sort and Filter")
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
                $0.artist.localizedCaseInsensitiveContains(query)
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
                        .musicoLibraryRowTap {
                            playback.play(item, from: filteredItems, fileURL: library.fileURL)
                        }
                        .contextMenu {
                            Button {
                                editingItem = item
                            } label: {
                                Label("Edit Title & Artist", systemImage: "pencil")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                editingItem = item
                            } label: {
                                Text("Edit")
                            }
                            .tint(.blue)

                            Button(role: .destructive) {
                                library.remove(item, from: playlistID)
                            } label: {
                                Text("Remove")
                            }
                        }
                }
            }
        }
        .musicoInsetGroupedListStyle()
        .navigationTitle(playlist?.name ?? "Playlist")
        .searchable(text: $searchText, prompt: "Search by title or artist")
        .sheet(item: $editingItem) { item in
            EditItemSheet(item: item)
        }
    }
}
