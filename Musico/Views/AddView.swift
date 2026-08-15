import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AddView: View {
    @EnvironmentObject private var downloads: DownloadManager
    @State private var isURLSheetPresented = false

    private var activeCount: Int {
        downloads.records.filter { $0.state.isActive }.count
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button {
                        isURLSheetPresented = true
                    } label: {
                        Label("Add from URL", systemImage: "link.badge.plus")
                            .frame(maxWidth: .infinity)
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(MusicoBrandButtonStyle())
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    headerView
                } footer: {
                    Text("Paste a direct https:// media link, a YouTube video, or a YouTube playlist. Musico lets you review titles and artists before downloading.")
                }

                if activeCount > 0 {
                    Section {
                        Label("\(activeCount) download\(activeCount == 1 ? "" : "s") in progress", systemImage: "arrow.down.circle")
                            .foregroundColor(.secondary)
                        Text("Track progress on the Downloads tab.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .musicoInsetGroupedListStyle()
            .musicoThemedListBackground()
            .navigationTitle("Add")
            .sheet(isPresented: $isURLSheetPresented) {
                AddByURLSheet()
            }
        }
        .musicoStackNavigationStyle()
    }

    private var headerView: some View {
        VStack(spacing: 8) {
            MusicoWaveMark(lineWidth: 10)
                .frame(width: 172, height: 72)
            Text("Add to Your Library")
                .font(.title2.bold())
                .foregroundColor(.white)
            Text("Your music, in motion.")
                .font(.subheadline)
                .foregroundColor(MusicoTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .textCase(nil)
    }
}

struct AddByURLSheet: View {
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.presentationMode) private var presentationMode

    @State private var urlText = ""
    @State private var isSubmitting = false
    @State private var preparedDownload: PreparedDownload?
    @State private var preparedPlaylist: YouTubePlaylistPreview?
    @State private var errorMessage = ""
    @State private var isShowingError = false

    private var trimmed: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmed.isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField(musicoPrompt: "https://example.com/song.m4a", text: $urlText)
                        .musicoFormTextField()
                        .textContentType(.URL)
                        .disableAutocorrection(true)
                        .musicoURLKeyboard()

                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                    }
                    .disabled(!clipboardHasText)
                } footer: {
                    Text("Direct file links, YouTube videos, and YouTube playlists are supported. The link must use https.")
                }
            }
            .musicoThemedListBackground()
            .navigationTitle("Add from URL")
            .musicoInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Review") { submit() }
                            .disabled(!canSubmit)
                    }
                }
            }
        }
        .musicoStackNavigationStyle()
        .sheet(item: $preparedDownload) { prepared in
            DownloadConfirmationSheet(prepared: prepared) { title, artist in
                downloads.startPreparedDownload(prepared, title: title, artist: artist)
                preparedDownload = nil
                dismiss()
            }
        }
        .sheet(item: $preparedPlaylist) { playlist in
            YouTubePlaylistReviewSheet(playlist: playlist) { name, requests in
                downloads.enqueueYouTubePlaylist(requests, playlistName: name)
                preparedPlaylist = nil
                dismiss()
            }
        }
        .alert("Couldn't Prepare Download", isPresented: $isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var clipboardHasText: Bool {
#if canImport(UIKit)
        UIPasteboard.general.hasStrings
#else
        false
#endif
    }

    private func pasteFromClipboard() {
#if canImport(UIKit)
        if let string = UIPasteboard.general.string {
            urlText = string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
#endif
    }

    private func submit() {
        let input = trimmed
        guard !input.isEmpty else { return }
        isSubmitting = true
        Task {
            do {
                if let url = URL(string: input), YouTubeResolver.playlistID(from: url) != nil {
                    preparedPlaylist = try await YouTubeResolver.resolvePlaylist(from: url)
                } else {
                    preparedDownload = try await downloads.prepareFromURL(input)
                }
            } catch {
                errorMessage = error.localizedDescription
                isShowingError = true
            }
            isSubmitting = false
        }
    }

    private func dismiss() {
        presentationMode.wrappedValue.dismiss()
    }
}

private struct PlaylistDraftItem: Identifiable {
    var id: String { videoID }
    let videoID: String
    let thumbnailURL: URL?
    var title: String
    var artist: String
    var isSelected: Bool
}

private struct YouTubePlaylistReviewSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    let onConfirm: (String, [YouTubePlaylistDownloadRequest]) -> Void

    @State private var playlistName: String
    @State private var items: [PlaylistDraftItem]
    @State private var editingItem: PlaylistDraftItem?
    @State private var isBulkArtistPresented = false

    init(
        playlist: YouTubePlaylistPreview,
        onConfirm: @escaping (String, [YouTubePlaylistDownloadRequest]) -> Void
    ) {
        self.onConfirm = onConfirm
        _playlistName = State(initialValue: playlist.title)
        _items = State(initialValue: playlist.items.map {
            PlaylistDraftItem(
                videoID: $0.videoID,
                thumbnailURL: $0.thumbnailURL,
                title: $0.title,
                artist: $0.artist ?? "",
                isSelected: true
            )
        })
    }

    private var selectedCount: Int { items.filter(\.isSelected).count }
    private var allAreSelected: Bool { !items.isEmpty && selectedCount == items.count }

    private var canConfirm: Bool {
        !playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedCount > 0
            && items.allSatisfy {
                !$0.isSelected
                    || !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Musico Playlist")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField(musicoPrompt: "Playlist name", text: $playlistName)
                            .musicoFormTextField()
                    }
                    HStack {
                        Label(
                            "\(selectedCount) selected",
                            systemImage: "checkmark.square.fill"
                        )
                        .foregroundColor(selectedCount > 0 ? MusicoTheme.magenta : .secondary)
                        Spacer()
                        Button(allAreSelected ? "Clear" : "Select All") {
                            let shouldSelect = !allAreSelected
                            for index in items.indices {
                                items[index].isSelected = shouldSelect
                            }
                        }
                    }
                } header: {
                    Text("Playlist")
                } footer: {
                    Text("Downloads are added to your library and to this playlist as they finish.")
                }

                Section {
                    Button {
                        isBulkArtistPresented = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.2.fill")
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Set Artist for Selected")
                                    .foregroundColor(.primary)
                                Text("Apply one artist to \(selectedCount) song\(selectedCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(selectedCount == 0)
                }

                Section {
                    ForEach(items) { item in
                        HStack(spacing: 11) {
                            Button {
                                toggleSelection(for: item.id)
                            } label: {
                                Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundColor(item.isSelected ? MusicoTheme.magenta : .secondary)
                                    .frame(width: 30, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.isSelected ? "Exclude \(item.title)" : "Include \(item.title)")

                            AsyncImage(url: item.thumbnailURL) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    ZStack {
                                        Color.secondary.opacity(0.16)
                                        Image(systemName: "music.note")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .frame(width: 72, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                            Button {
                                editingItem = item
                            } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.body.weight(.medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        Text(item.artist.isEmpty ? "Unknown Artist" : item.artist)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: "pencil")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.secondary)
                                        .frame(width: 28, height: 28)
                                        .background(Color.secondary.opacity(0.12))
                                        .clipShape(Circle())
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)
                        .opacity(item.isSelected ? 1 : 0.48)
                    }
                } header: {
                    HStack {
                        Text("Songs")
                        Spacer()
                        Text("\(selectedCount) of \(items.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    Text("Use the checkbox to include a song. Tap its details or pencil to edit the title and artist.")
                }
            }
            .musicoThemedListBackground()
            .navigationTitle("Review Playlist")
            .musicoInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selectedCount)") { confirm() }
                        .disabled(!canConfirm)
                }
            }
        }
        .musicoStackNavigationStyle()
        .sheet(item: $editingItem) { item in
            PlaylistSongEditSheet(item: item) { updated in
                guard let index = items.firstIndex(where: { $0.id == updated.id }) else { return }
                items[index].title = updated.title
                items[index].artist = updated.artist
                editingItem = nil
            }
        }
        .sheet(isPresented: $isBulkArtistPresented) {
            PlaylistBulkArtistSheet(selectedCount: selectedCount) { artist in
                for index in items.indices where items[index].isSelected {
                    items[index].artist = artist
                }
                isBulkArtistPresented = false
            }
        }
    }

    private func toggleSelection(for itemID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].isSelected.toggle()
    }

    private func confirm() {
        let requests = items.compactMap { item -> YouTubePlaylistDownloadRequest? in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard item.isSelected, !title.isEmpty else { return nil }
            return YouTubePlaylistDownloadRequest(
                videoID: item.videoID,
                title: title,
                artist: item.artist.trimmingCharacters(in: .whitespacesAndNewlines),
                thumbnailURL: item.thumbnailURL
            )
        }
        guard !requests.isEmpty else { return }
        onConfirm(playlistName.trimmingCharacters(in: .whitespacesAndNewlines), requests)
    }
}

private struct PlaylistSongEditSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    let item: PlaylistDraftItem
    let onSave: (PlaylistDraftItem) -> Void

    @State private var title: String
    @State private var artist: String

    init(item: PlaylistDraftItem, onSave: @escaping (PlaylistDraftItem) -> Void) {
        self.item = item
        self.onSave = onSave
        _title = State(initialValue: item.title)
        _artist = State(initialValue: item.artist)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack(spacing: 12) {
                        AsyncImage(url: item.thumbnailURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                ZStack {
                                    Color.secondary.opacity(0.16)
                                    Image(systemName: "music.note")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(width: 96, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                        Text("Changes apply to this download only.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Song Details") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Title")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField(musicoPrompt: "Song title", text: $title)
                            .musicoFormTextField()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Artist")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ArtistComboField(artist: $artist)
                    }
                }
            }
            .musicoThemedListBackground()
            .navigationTitle("Edit Song")
            .musicoInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = item
                        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(updated)
                    }
                    .disabled(!canSave)
                }
            }
        }
        .musicoStackNavigationStyle()
    }
}

private struct PlaylistBulkArtistSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    let selectedCount: Int
    let onApply: (String) -> Void
    @State private var artist = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    ArtistComboField(artist: $artist)
                } header: {
                    Text("Artist")
                } footer: {
                    Text("This changes the artist for all \(selectedCount) selected songs.")
                }

                Section {
                    Button("Clear Artist on Selected Songs") {
                        onApply("")
                    }
                    .foregroundColor(.red)
                }
            }
            .musicoThemedListBackground()
            .navigationTitle("Set Artist")
            .musicoInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(artist.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .disabled(artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .musicoStackNavigationStyle()
    }
}

private struct DownloadConfirmationSheet: View {
    @Environment(\.presentationMode) private var presentationMode

    let prepared: PreparedDownload
    let onConfirm: (String, String) -> Void

    @State private var title: String
    @State private var artist: String

    init(prepared: PreparedDownload, onConfirm: @escaping (String, String) -> Void) {
        self.prepared = prepared
        self.onConfirm = onConfirm
        _title = State(initialValue: prepared.title)
        _artist = State(initialValue: prepared.artist ?? "")
    }

    private var canConfirm: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Title")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField(musicoPrompt: "Song title", text: $title)
                            .musicoFormTextField()
                    }
                    .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Artist")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ArtistComboField(artist: $artist)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Song Details")
                } footer: {
                    Text("Edit anything you want before downloading.")
                }

                Section {
                    HStack {
                        Label(prepared.kind.label, systemImage: prepared.kind.systemImage)
                        Spacer()
                        Text(prepared.sourceName)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Source")
                }

                Section {
                    Button {
                        onConfirm(title, artist)
                    } label: {
                        Label("Start Downloading", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(MusicoBrandButtonStyle())
                    .disabled(!canConfirm)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("The download starts only after you tap the button above.")
                }
            }
            .musicoThemedListBackground()
            .navigationTitle("Review")
            .musicoInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
        .musicoStackNavigationStyle()
    }
}
