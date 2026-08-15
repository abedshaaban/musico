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
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    headerView
                } footer: {
                    Text("Paste a direct https:// link to an audio or video file, or a YouTube video link. Musico validates the link and lets you review the title and artist before downloading.")
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
            .navigationTitle("Add")
            .sheet(isPresented: $isURLSheetPresented) {
                AddByURLSheet()
            }
        }
        .musicoStackNavigationStyle()
    }

    private var headerView: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 42, weight: .light))
                .foregroundColor(.accentColor)
            Text("Add to Your Library")
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .textCase(nil)
    }
}

struct AddByURLSheet: View {
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.presentationMode) private var presentationMode

    @State private var urlText = ""
    @State private var isSubmitting = false
    @State private var preparedDownload: PreparedDownload?
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
                    Text("Direct file links (for example .mp3, .m4a, .mp4, or .mov) and YouTube video links are supported. The link must use https.")
                }
            }
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
                preparedDownload = try await downloads.prepareFromURL(input)
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
                    .buttonStyle(.borderedProminent)
                    .disabled(!canConfirm)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("The download starts only after you tap the button above.")
                }
            }
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
