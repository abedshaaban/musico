import SwiftUI

@main
struct MusicoApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var downloads = DownloadQueueStore()
    @StateObject private var playback = PlaybackController()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environmentObject(library)
                .environmentObject(downloads)
                .environmentObject(playback)
        }
    }
}
