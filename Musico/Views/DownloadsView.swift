import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadManager

    private var hasFinished: Bool {
        downloads.records.contains { !$0.state.isActive }
    }

    var body: some View {
        NavigationView {
            Group {
                if downloads.records.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(downloads.records) { record in
                            DownloadRow(record: record)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if record.state.isActive {
                                        Button {
                                            downloads.cancel(record)
                                        } label: {
                                            Text("Cancel")
                                        }
                                        .tint(.orange)
                                    } else if record.state == .failed || record.state == .cancelled {
                                        Button {
                                            downloads.retry(record)
                                        } label: {
                                            Text("Retry")
                                        }
                                        .tint(.blue)
                                    }

                                    Button(role: .destructive) {
                                        downloads.remove(record)
                                    } label: {
                                        Text("Remove")
                                    }
                                }
                        }
                    }
                    .musicoInsetGroupedListStyle()
                }
            }
            .navigationTitle("Downloads")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if hasFinished {
                        Button("Clear") { downloads.clearFinished() }
                    }
                }
            }
        }
        .musicoStackNavigationStyle()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.secondary)
            Text("No Downloads")
                .font(.title2.bold())
            Text("Use the Add tab to download a direct audio or video link you're authorized to save.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }
}

private struct DownloadRow: View {
    let record: DownloadRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title)
                        .lineLimit(1)
                    Text(record.sourceName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(record.state.label)
                    .font(.caption.weight(.medium))
                    .foregroundColor(stateColor)
            }

            if record.state.isActive {
                ProgressView(value: record.state == .downloading ? record.progress : 0)
            }

            HStack {
                if let detail = record.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if let bytes = byteSummary {
                    Text(bytes)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var byteSummary: String? {
        guard record.state == .downloading, record.receivedBytes > 0 else { return nil }
        let received = ByteCountFormatter.string(fromByteCount: record.receivedBytes, countStyle: .file)
        if record.totalBytes > 0 {
            let total = ByteCountFormatter.string(fromByteCount: record.totalBytes, countStyle: .file)
            return "\(received) / \(total)"
        }
        return received
    }

    private var stateColor: Color {
        switch record.state {
        case .completed: return .green
        case .failed, .cancelled: return .red
        case .downloading: return .blue
        case .validating, .queued: return .secondary
        }
    }
}
