import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadQueueStore

    var body: some View {
        NavigationView {
            Group {
                if downloads.records.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(.secondary)
                        Text("No Downloads")
                            .font(.title2.bold())
                        Text("Musico currently imports files you provide. A download provider can be added later for direct links you are authorized to save.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                        Button("Add Queue Placeholder") {
                            downloads.enqueuePlaceholder(title: "Future Download", sourceName: "Authorized Source")
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    List {
                        ForEach(downloads.records) { record in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(record.title)
                                        Text(record.sourceName)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(record.state.label)
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(stateColor(record.state))
                                }
                                ProgressView(value: record.progress)
                                if let detail = record.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .swipeActions {
                                Button(role: .destructive) { downloads.remove(record) } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                if record.state == .queued || record.state == .downloading {
                                    Button { downloads.cancel(record) } label: {
                                        Label("Cancel", systemImage: "xmark")
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                    }
                    .musicoInsetGroupedListStyle()
                }
            }
            .navigationTitle("Downloads")
        }
        .musicoStackNavigationStyle()
    }

    private func stateColor(_ state: DownloadState) -> Color {
        switch state {
        case .completed: return .green
        case .failed, .cancelled: return .red
        case .downloading: return .blue
        case .queued: return .secondary
        }
    }
}
