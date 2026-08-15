import SwiftUI
import UIKit

struct ArtistComboField: View {
    @EnvironmentObject private var library: LibraryStore
    @Binding var artist: String

    @State private var isShowingSuggestions = false

    private var trimmedArtist: String {
        artist.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredArtists: [String] {
        library.filteredArtists(matching: artist)
    }

    private var showsCustomOption: Bool {
        !trimmedArtist.isEmpty && !filteredArtists.contains {
            $0.localizedCaseInsensitiveCompare(trimmedArtist) == .orderedSame
        }
    }

    private var showsSuggestionList: Bool {
        isShowingSuggestions && (showsCustomOption || !filteredArtists.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(musicoPrompt: "Artist", text: $artist, onEditingChanged: { editing in
                isShowingSuggestions = editing
            })
            .musicoFormTextField()

            if showsSuggestionList {
                VStack(alignment: .leading, spacing: 0) {
                    if showsCustomOption {
                        suggestionButton(
                            title: "Use \"\(trimmedArtist)\"",
                            systemImage: "plus.circle.fill",
                            isSelected: false
                        ) {
                            artist = trimmedArtist
                            isShowingSuggestions = false
                        }
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredArtists, id: \.self) { name in
                                suggestionButton(
                                    title: name,
                                    systemImage: nil,
                                    isSelected: name.localizedCaseInsensitiveCompare(trimmedArtist) == .orderedSame
                                ) {
                                    artist = name
                                    isShowingSuggestions = false
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func suggestionButton(
        title: String,
        systemImage: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundColor(.accentColor)
                }
                Text(title)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
