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
                    Text("Paste a direct https:// link to an audio or video file, or a YouTube video link. Musico validates the link, then downloads it in the background.")
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

                Section("What Musico won't do") {
                    complianceRow("Never bypasses DRM or a service's access controls.")
                    complianceRow("Only download content you're authorized to save.")
                    complianceRow("Links from protected streaming hosts are refused.")
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

    private func complianceRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.shield")
            .font(.subheadline)
            .foregroundColor(.secondary)
    }
}

struct AddByURLSheet: View {
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.presentationMode) private var presentationMode

    @State private var urlText = ""
    @State private var isSubmitting = false

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
                    TextField("https://example.com/song.m4a", text: $urlText)
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
                    Button("Add") { submit() }
                        .disabled(!canSubmit)
                }
            }
        }
        .musicoStackNavigationStyle()
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
            await downloads.addFromURL(input)
            isSubmitting = false
            dismiss()
        }
    }

    private func dismiss() {
        presentationMode.wrappedValue.dismiss()
    }
}
