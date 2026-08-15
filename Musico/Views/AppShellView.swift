import SwiftUI

struct AppShellView: View {
    var body: some View {
        TabView {
            AddView()
                .tabItem { Label("Add", systemImage: "plus.circle") }

            DownloadsView()
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }

            LibraryView()
                .tabItem { Label("Library", systemImage: "music.note.list") }

            NowPlayingView()
                .tabItem { Label("Now Playing", systemImage: "play.circle") }
        }
        .accentColor(.primary)
    }
}
