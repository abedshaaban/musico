import SwiftUI

struct EditItemSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss

    let item: LibraryItem
    @State private var title: String
    @State private var artist: String

    init(item: LibraryItem) {
        self.item = item
        _title = State(initialValue: item.title)
        _artist = State(initialValue: item.artist)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Details") {
                    TextField(musicoPrompt: "Title", text: $title)
                        .musicoFormTextField()
                    ArtistComboField(artist: $artist)
                }
            }
            .navigationTitle("Edit Track")
            .musicoInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let cleanedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        library.update(item, title: title, artist: cleanedArtist.isEmpty ? item.artist : cleanedArtist)
        playback.syncCurrentItem(with: library)
        dismiss()
    }
}
