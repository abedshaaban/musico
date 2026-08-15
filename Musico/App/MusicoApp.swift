import SwiftUI
import UIKit

@main
struct MusicoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var library: LibraryStore
    @StateObject private var downloads: DownloadManager
    @StateObject private var playback: PlaybackController

    init() {
        Self.configureAppearance()

        // Wire services during launch rather than from a view callback. A background
        // URLSession relaunch may not display a scene before its delegate events arrive.
        let library = LibraryStore()
        let downloads = DownloadManager(library: library)
        let playback = PlaybackController()
        playback.configure(library: library)

        _library = StateObject(wrappedValue: library)
        _downloads = StateObject(wrappedValue: downloads)
        _playback = StateObject(wrappedValue: playback)
    }

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environmentObject(library)
                .environmentObject(downloads)
                .environmentObject(playback)
                .preferredColorScheme(.dark)
        }
    }

    private static func configureAppearance() {
        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = UIColor(MusicoTheme.background)
        navigationAppearance.shadowColor = UIColor(MusicoTheme.stroke)
        navigationAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navigationAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().tintColor = UIColor(MusicoTheme.magenta)

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(MusicoTheme.backgroundLifted)
        tabAppearance.shadowColor = UIColor(MusicoTheme.stroke)
        tabAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(MusicoTheme.magenta)
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(MusicoTheme.magenta)
        ]
        tabAppearance.stackedLayoutAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.52)
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor.white.withAlphaComponent(0.52)
        ]

        UITabBar.appearance().standardAppearance = tabAppearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        }

        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear
        UITableView.appearance().separatorColor = UIColor.white.withAlphaComponent(0.08)
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
