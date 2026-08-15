import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackController
    @State private var isCreatingPlaylist = false
    @State private var playlistName = ""
    @State private var isImporterPresented = false
    @State private var isImporting = false

    var body: some View {
        NavigationView {
            List {
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
                        .swipeActions {
                            Button(role: .destructive) { library.deletePlaylist(playlist) } label: {
                                Label("Delete", systemImage: "trash")
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
                    }
                    ForEach(library.items) { item in
                        Button {
                            playback.play(item, from: library.items, fileURL: library.fileURL)
                        } label: {
                            MediaRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if !library.playlists.isEmpty {
                                Menu("Add to Playlist") {
                                    ForEach(library.playlists) { playlist in
                                        Button(playlist.name) { library.add(item, to: playlist) }
                                    }
                                }
                            }
                            Button(role: .destructive) {
                                if playback.currentItem?.id == item.id { playback.stop() }
                                library.delete(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                if playback.currentItem?.id == item.id { playback.stop() }
                                library.delete(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .musicoInsetGroupedListStyle()
            .navigationTitle("Library")
            .toolbar {
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
                        TextField("Playlist name", text: $playlistName)
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
            .alert("Musico", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { library.lastError = nil }
            } message: {
                Text(library.lastError ?? "Unknown error")
            }
        }
        .musicoStackNavigationStyle()
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

    private var playlist: Playlist? {
        library.playlists.first { $0.id == playlistID }
    }

    private var items: [LibraryItem] {
        guard let playlist else { return [] }
        return library.items(in: playlist)
    }

    var body: some View {
        List {
            if !items.isEmpty {
                Section {
                    Button {
                        guard let first = items.first else { return }
                        playback.play(first, from: items, fileURL: library.fileURL)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        guard let random = items.randomElement() else { return }
                        if !playback.isShuffleEnabled { playback.toggleShuffle() }
                        playback.play(random, from: items, fileURL: library.fileURL)
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
                }
                ForEach(items) { item in
                    Button {
                        playback.play(item, from: items, fileURL: library.fileURL)
                    } label: {
                        MediaRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            library.remove(item, from: playlistID)
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                    }
                }
            }
        }
        .musicoInsetGroupedListStyle()
        .navigationTitle(playlist?.name ?? "Playlist")
    }
}
