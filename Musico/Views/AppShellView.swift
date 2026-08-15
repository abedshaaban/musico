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
    @State private var dismissedMiniPlayerItemID: UUID?

    var body: some View {
        TabView(selection: $selectedTab) {
            tabContent(AddView())
                .tabItem { Label("Add", systemImage: "plus.circle") }
                .tag(AppTab.add)

            tabContent(DownloadsView())
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                .tag(AppTab.downloads)

            tabContent(LibraryView())
                .tabItem { Label("Library", systemImage: "music.note.list") }
                .tag(AppTab.library)

            NowPlayingView()
                .tabItem { Label("Now Playing", systemImage: "play.circle") }
                .tag(AppTab.nowPlaying)
        }
        .accentColor(MusicoTheme.magenta)
        .background(MusicoTheme.background.ignoresSafeArea())
        .onChange(of: playback.currentItem?.id) { itemID in
            if itemID == nil {
                dismissedMiniPlayerItemID = nil
            }
        }
    }

    @ViewBuilder
    private func tabContent<Content: View>(_ content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 8) {
            if let item = playback.currentItem,
               item.id != dismissedMiniPlayerItemID {
                MiniPlayerBar(
                    onOpenNowPlaying: { selectedTab = .nowPlaying },
                    onDismiss: { dismissedMiniPlayerItemID = item.id }
                )
                .padding(.horizontal, 10)
            }
        }
    }
}
