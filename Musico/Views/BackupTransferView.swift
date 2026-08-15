import SwiftUI
import UIKit

struct BackupTransferView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss

    @State private var isWorking = false
    @State private var isImporterPresented = false
    @State private var exportRequest: BackupExportRequest?
    @State private var exportedTemporaryURL: URL?
    @State private var pendingRestore: MusicoBackupPreview?
    @State private var confirmsRestore = false
    @State private var securityScopedImportURL: URL?
    @State private var isAccessingSecurityScopedImport = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var hasActiveDownloads: Bool {
        downloads.records.contains { $0.state.isActive }
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Button {
                        createBackup()
                    } label: {
                        Label("Export Musico Backup", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isWorking || library.items.isEmpty)

                    HStack {
                        Text("Library Items")
                        Spacer()
                        Text("\(library.items.count)")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Create Backup")
                } footer: {
                    Text("Exports music, videos, artwork, playlists, metadata, play history, and appearance preferences into one portable file. Backups are not encrypted, so keep them private.")
                }

                Section {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Choose Backup to Restore", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isWorking || hasActiveDownloads)

                    if hasActiveDownloads {
                        Label("Finish or cancel active downloads before restoring.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                } header: {
                    Text("Transfer or Restore")
                } footer: {
                    Text("Restoring replaces the current library, media, artwork, playlists, and metadata. Download history is left unchanged.")
                }

                if let statusMessage {
                    Section("Last Operation") {
                        Text(statusMessage)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Backup & Transfer")
            .musicoInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .disabled(isWorking)
                }
            }
            .overlay {
                if isWorking {
                    ProgressView("Working…")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.musicoBackup],
                allowsMultipleSelection: false,
                onCompletion: handleImport
            )
            .confirmationDialog(
                pendingRestore.map { "Restore \($0.itemCount) items?" } ?? "Restore backup?",
                isPresented: $confirmsRestore,
                titleVisibility: .visible
            ) {
                Button("Replace Current Library", role: .destructive) {
                    beginRestore()
                }
                Button("Cancel", role: .cancel) {
                    cancelPendingRestore()
                }
            } message: {
                if let preview = pendingRestore {
                    Text("Created \(preview.createdAt.formatted(date: .abbreviated, time: .shortened)) with \(preview.itemCount) items and approximately \(Self.bytes(preview.mediaBytes)) of media. This cannot be undone unless you first export the current library.")
                }
            }
            .alert("Backup & Transfer", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
        .musicoStackNavigationStyle()
        .interactiveDismissDisabled(isWorking)
        .sheet(item: $exportRequest, onDismiss: cleanupExport) { request in
            BackupExportPicker(fileURL: request.fileURL) {
                exportRequest = nil
            }
        }
        .onDisappear {
            endImportAccess()
            MusicoBackupService.removeTemporaryFile(exportedTemporaryURL)
        }
    }

    private func createBackup() {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = nil
        let snapshot = library.backupSnapshot()
        let preferences = MusicoBackupService.currentPreferences()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"

        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try MusicoBackupService.create(
                        library: snapshot,
                        mediaDirectory: AppPaths.media,
                        artworkDirectory: AppPaths.artwork,
                        preferences: preferences,
                        appVersion: appVersion
                    )
                }.value
                exportedTemporaryURL = result.fileURL
                statusMessage = "Created a \(Self.bytes(result.preview.archiveBytes)) backup containing \(result.preview.itemCount) items."
                exportRequest = BackupExportRequest(fileURL: result.fileURL)
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let source = urls.first else {
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
            return
        }
        isWorking = true
        statusMessage = nil
        let accessed = source.startAccessingSecurityScopedResource()
        Task {
            do {
                let preview = try await Task.detached(priority: .userInitiated) {
                    try MusicoBackupService.inspect(source)
                }.value
                endImportAccess()
                securityScopedImportURL = source
                isAccessingSecurityScopedImport = accessed
                pendingRestore = preview
                confirmsRestore = true
            } catch {
                if accessed { source.stopAccessingSecurityScopedResource() }
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func beginRestore() {
        guard let preview = pendingRestore, !hasActiveDownloads else {
            if hasActiveDownloads {
                errorMessage = "Finish or cancel active downloads before restoring a backup."
            }
            return
        }
        confirmsRestore = false
        pendingRestore = nil
        isWorking = true
        playback.stop()

        Task {
            defer {
                endImportAccess()
                isWorking = false
            }
            do {
                let manifest = try await Task.detached(priority: .userInitiated) {
                    try MusicoBackupService.restore(
                        preview.fileURL,
                        applicationSupport: AppPaths.applicationSupport
                    )
                }.value
                MusicoBackupService.applyPreferences(manifest.preferences)
                playback.reloadSettings()
                library.reloadAfterRestore()
                statusMessage = "Restored \(library.items.count) items from \(manifest.createdAt.formatted(date: .abbreviated, time: .shortened))."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelPendingRestore() {
        confirmsRestore = false
        pendingRestore = nil
        endImportAccess()
    }

    private func endImportAccess() {
        if isAccessingSecurityScopedImport, let url = securityScopedImportURL {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedImportURL = nil
        isAccessingSecurityScopedImport = false
    }

    private func cleanupExport() {
        MusicoBackupService.removeTemporaryFile(exportedTemporaryURL)
        exportedTemporaryURL = nil
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

private struct BackupExportRequest: Identifiable {
    let id = UUID()
    let fileURL: URL
}

private struct BackupExportPicker: UIViewControllerRepresentable {
    let fileURL: URL
    let onComplete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onComplete: () -> Void

        init(onComplete: @escaping () -> Void) {
            self.onComplete = onComplete
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onComplete()
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            onComplete()
        }
    }
}
