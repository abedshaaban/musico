import SwiftUI

@main
struct MusicoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var library = LibraryStore()
    @StateObject private var downloads = DownloadManager()
    @StateObject private var playback = PlaybackController()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environmentObject(library)
                .environmentObject(downloads)
                .environmentObject(playback)
                .onAppear {
                    downloads.configure(library: library)
                    playback.configure(library: library)
                }
        }
    }
}

/// Captures the completion handler iOS hands us when the app is relaunched in the
/// background to finish a URLSession background download. `DownloadManager` calls it
/// once the session reports all events are delivered.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static private(set) weak var shared: AppDelegate?
    var backgroundCompletionHandler: (() -> Void)?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        backgroundCompletionHandler = completionHandler
    }
}
