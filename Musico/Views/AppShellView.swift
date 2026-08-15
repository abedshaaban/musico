import SwiftUI

private enum AppTab: Hashable {
    case add
    case downloads
    case library
    case nowPlaying
}

struct AppShellView: View {
    @EnvironmentObject private var playback: PlaybackController
    @State private var selectedTab: AppTab = .library

    var body: some View {
        TabView(selection: $selectedTab) {
            AddView()
                .tabItem { Label("Add", systemImage: "plus.circle") }
                .tag(AppTab.add)

            DownloadsView()
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                .tag(AppTab.downloads)

            LibraryView()
                .tabItem { Label("Library", systemImage: "music.note.list") }
                .tag(AppTab.library)

            NowPlayingView()
                .tabItem { Label("Now Playing", systemImage: "play.circle") }
                .tag(AppTab.nowPlaying)
        }
        .accentColor(.primary)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if playback.currentItem != nil, selectedTab != .nowPlaying {
                MiniPlayerBar {
                    selectedTab = .nowPlaying
                }
            }
        }
    }
}
