import SwiftUI
import UniformTypeIdentifiers

struct SearchImportView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackController
    @State private var searchText = ""
    @State private var isImporterPresented = false
    @State private var isImporting = false

    private var filteredItems: [LibraryItem] {
        guard !searchText.isEmpty else { return library.items }
        return library.items.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText) ||
            $0.originalFilename.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if library.items.isEmpty {
                    VStack(spacing: 18) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(.secondary)
                        Text("Import Your Media")
                            .font(.title2.bold())
                        Text("Choose audio or video files already on this iPhone, in iCloud Drive, or from another Files location you can access.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                        importButton
                    }
                } else {
                    List {
                        Section {
                            importButton
                        }
                        Section("On This iPhone") {
                            ForEach(filteredItems) { item in
                                Button {
                                    playback.play(item, from: filteredItems, fileURL: library.fileURL)
                                } label: {
                                    MediaRow(item: item, trailingText: item.kind.label)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .musicoInsetGroupedListStyle()
                }
            }
            .navigationTitle("Search or Import")
            .searchable(text: $searchText, prompt: "Titles, artists, or filenames")
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

    private var importButton: some View {
        Button {
            isImporterPresented = true
        } label: {
            Label(isImporting ? "Importing…" : "Import Files", systemImage: "plus.circle")
                .frame(maxWidth: .infinity)
        }
        .disabled(isImporting)
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { library.lastError != nil },
            set: { if !$0 { library.lastError = nil } }
        )
    }
}
