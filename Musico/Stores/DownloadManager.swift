import Foundation

@MainActor
final class DownloadQueueStore: ObservableObject {
    @Published private(set) var records: [DownloadRecord] = []

    func enqueuePlaceholder(title: String, sourceName: String) {
        records.insert(
            DownloadRecord(
                id: UUID(),
                title: title,
                sourceName: sourceName,
                state: .queued,
                progress: 0,
                createdAt: Date(),
                detail: "Waiting for an authorized download source implementation."
            ),
            at: 0
        )
    }

    func cancel(_ record: DownloadRecord) {
        update(record, state: .cancelled, progress: record.progress)
    }

    func remove(_ record: DownloadRecord) {
        records.removeAll { $0.id == record.id }
    }

    func update(_ record: DownloadRecord, state: DownloadState, progress: Double) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index].state = state
        records[index].progress = min(max(progress, 0), 1)
    }
}

// Extension point for future sources that provide direct, authorized media URLs.
// TODO: Add an implementation only when the source's terms and the user's rights allow it.
protocol AuthorizedDownloadSource {
    var displayName: String { get }
    func downloadMedia() async throws -> URL
}

// Conversion is intentionally absent. A future converter should be introduced behind a
// separate protocol only when an approved, locally supported implementation is selected.
// TODO: Define that conversion protocol only after its authorized implementation is chosen.
