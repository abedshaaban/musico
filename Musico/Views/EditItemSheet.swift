import SwiftUI

struct EditItemSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss

    let item: LibraryItem
    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var genre: String
    @State private var year: String
    @State private var trackNumber: String

    init(item: LibraryItem) {
        self.item = item
        _title = State(initialValue: item.title)
        _artist = State(initialValue: item.artist)
        _album = State(initialValue: item.album ?? "")
        _genre = State(initialValue: item.genre ?? "")
        _year = State(initialValue: item.year.map(String.init) ?? "")
        _trackNumber = State(initialValue: item.trackNumber.map(String.init) ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Details") {
                    TextField(musicoPrompt: "Title", text: $title)
                        .musicoFormTextField()
                    ArtistComboField(artist: $artist)
                }

                Section("Album Information") {
                    TextField(musicoPrompt: "Album", text: $album)
                        .musicoFormTextField()
                    TextField(musicoPrompt: "Genre", text: $genre)
                        .musicoFormTextField()
                    HStack {
                        TextField(musicoPrompt: "Year", text: $year)
                            .keyboardType(.numberPad)
                            .musicoFormTextField()
                        TextField(musicoPrompt: "Track", text: $trackNumber)
                            .keyboardType(.numberPad)
                            .musicoFormTextField()
                    }
                }

                Section("File") {
                    HStack {
                        Text("Original Name")
                        Spacer()
                        Text(item.originalFilename)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    HStack {
                        Text("Type")
                        Spacer()
                        Text(item.kind.label)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .musicoThemedListBackground()
            .navigationTitle("Edit Track")
            .musicoInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let cleanedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        library.update(
            item,
            title: title,
            artist: cleanedArtist.isEmpty ? item.artist : cleanedArtist,
            album: album,
            genre: genre,
            year: parsedYear,
            trackNumber: parsedTrackNumber
        )
        playback.syncCurrentItem(with: library)
        dismiss()
    }

    private var parsedYear: Int? {
        let value = year.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : Int(value)
    }

    private var parsedTrackNumber: Int? {
        let value = trackNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : Int(value)
    }

    private var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let validYear = year.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || parsedYear.map { (1000...9999).contains($0) } == true
        let validTrack = trackNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || parsedTrackNumber.map { $0 > 0 } == true
        return validYear && validTrack
    }
}
