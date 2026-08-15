import SwiftUI
import UIKit

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

                                        Button(role: .destructive) {
                                            downloads.remove(record)
                                        } label: {
                                            Text("Remove")
                                        }
                                    } else if record.state == .failed || record.state == .cancelled {
                                        Button {
                                            downloads.retry(record)
                                        } label: {
                                            Text("Retry")
                                        }
                                        .tint(MusicoTheme.violet)

                                        Button(role: .destructive) {
                                            downloads.remove(record)
                                        } label: {
                                            Text("Remove")
                                        }
                                    } else {
                                        Button(role: .destructive) {
                                            downloads.remove(record)
                                        } label: {
                                            Text("Remove")
                                        }
                                    }
                                }
                        }
                    }
                    .musicoInsetGroupedListStyle()
                    .musicoThemedListBackground()
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
            ZStack {
                Circle()
                    .fill(MusicoTheme.brandGradient)
                    .frame(width: 76, height: 76)
                    .shadow(color: MusicoTheme.magenta.opacity(0.34), radius: 18)
                Image(systemName: "arrow.down")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
            }
            Text("No Downloads")
                .font(.title2.bold())
            Text("Use the Add tab to download a direct audio or video link you're authorized to save.")
                .font(.subheadline)
                .foregroundColor(MusicoTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MusicoBackground().ignoresSafeArea())
    }
}

private struct DownloadRow: View {
    let record: DownloadRecord
    @State private var showingFailureDetails = false

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
                HStack(spacing: 8) {
                    Text(record.state.label)
                        .font(.caption.weight(.medium))
                        .foregroundColor(stateColor)

                    if record.state == .failed {
                        Button {
                            showingFailureDetails = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.body)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(MusicoTheme.magenta)
                        .accessibilityLabel("Failure details")
                    }
                }
            }

            if record.state.isActive {
                ProgressView(value: record.state == .downloading ? record.progress : 0)
                    .accentColor(MusicoTheme.magenta)
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
        .sheet(isPresented: $showingFailureDetails) {
            DownloadFailureDetailsView(record: record)
        }
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
        case .downloading: return MusicoTheme.magenta
        case .validating, .queued: return .secondary
        }
    }
}

private struct DownloadFailureDetailsView: View {
    let record: DownloadRecord
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationView {
            List {
                Section("What happened") {
                    Text(record.detail ?? "The download failed without a summary.")
                        .textSelection(.enabled)
                }

                Section("Download") {
                    detailRow("Title", record.title)
                    detailRow("Source", record.sourceName)
                    if let url = record.remoteURL {
                        detailRow("URL", url.absoluteString)
                    }
                    detailRow("Started", Self.dateFormatter.string(from: record.createdAt))
                    detailRow("Record ID", record.id.uuidString)
                    if record.receivedBytes > 0 {
                        detailRow("Received", Self.bytes(record.receivedBytes))
                    }
                    if record.totalBytes > 0 {
                        detailRow("Expected", Self.bytes(record.totalBytes))
                    }
                }

                Section("Technical details") {
                    Text(record.diagnostic ?? "No technical details were recorded. This can happen for failures created by an older Musico build. Retry once with this build to capture them.")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                if record.remoteURL != nil {
                    Section {
                        Button {
                            downloads.retry(record)
                            dismiss()
                        } label: {
                            Label(retryLabel, systemImage: "arrow.clockwise")
                        }
                    } footer: {
                        if DownloadTransport.retryTransport(after: record.detail) == .inApp {
                            Text("Keep Musico open until the sandbox-compatible download finishes.")
                        }
                    }
                }

                Section {
                    Button {
                        UIPasteboard.general.string = report
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy Failure Report", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
            .musicoThemedListBackground()
            .navigationTitle("Failure Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .musicoStackNavigationStyle()
    }

    @ViewBuilder
    private func detailRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }

    private var report: String {
        [
            "Musico download failure",
            "Summary: \(record.detail ?? "Unavailable")",
            "Title: \(record.title)",
            "Source: \(record.sourceName)",
            "URL: \(record.remoteURL?.absoluteString ?? "Unavailable")",
            "Started: \(Self.dateFormatter.string(from: record.createdAt))",
            "Record ID: \(record.id.uuidString)",
            "Received bytes: \(record.receivedBytes)",
            "Expected bytes: \(record.totalBytes)",
            "Technical details:",
            record.diagnostic ?? "Unavailable (failure may predate diagnostic capture)."
        ].joined(separator: "\n")
    }

    private var retryLabel: String {
        DownloadTransport.retryTransport(after: record.detail) == .inApp
            ? "Retry in Sandbox-Compatible Mode"
            : "Retry Download"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
