import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationView {
            Group {
                if playback.queue.isEmpty {
                    VStack(spacing: 12) {
                        MusicoWaveMark(lineWidth: 8)
                            .frame(width: 150, height: 68)
                        Text("Nothing Queued")
                            .font(.headline)
                        Text("Play something from Library to build a queue.")
                            .font(.subheadline)
                            .foregroundColor(MusicoTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MusicoBackground().ignoresSafeArea())
                } else {
                    List {
                        ForEach(Array(playback.queue.enumerated()), id: \.element.id) { index, item in
                            Button {
                                playback.jumpToQueueItem(item)
                            } label: {
                                HStack(spacing: 12) {
                                    MediaArtworkView(item: item, size: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text(item.artist)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if index == playback.currentQueueIndex {
                                        Image(systemName: playback.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onMove(perform: playback.moveQueueItem)
                        .onDelete(perform: playback.removeFromQueue)
                    }
                    .musicoInsetGroupedListStyle()
                    .musicoThemedListBackground()
                }
            }
            .navigationTitle("Up Next")
            .musicoInlineNavigationTitle()
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !playback.queue.isEmpty {
                        EditButton()
                    }
                }
            }
        }
    }
}

struct SleepTimerSheet: View {
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss

    private let presets = [15, 30, 45, 60, 90]

    var body: some View {
        NavigationView {
            List {
                if playback.sleepTimerRemaining != nil {
                    Section {
                        HStack {
                            Text("Time Remaining")
                            Spacer()
                            Text(playback.sleepTimerLabel ?? "—")
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        Button("Cancel Timer", role: .destructive) {
                            playback.cancelSleepTimer()
                            dismiss()
                        }
                    }
                }

                Section("Stop playback after") {
                    ForEach(presets, id: \.self) { minutes in
                        Button("\(minutes) minutes") {
                            playback.startSleepTimer(minutes: minutes)
                            dismiss()
                        }
                    }
                }
            }
            .musicoInsetGroupedListStyle()
            .musicoThemedListBackground()
            .navigationTitle("Sleep Timer")
            .musicoInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
