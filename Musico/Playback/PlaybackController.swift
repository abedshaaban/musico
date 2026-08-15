import AVFoundation
import MediaPlayer
import UIKit

@MainActor
final class PlaybackController: ObservableObject {
    let player = AVPlayer()

    @Published private(set) var currentItem: LibraryItem?
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var isShuffleEnabled = false
    @Published var isAudioOnlyMode = false
    @Published private(set) var queue: [LibraryItem] = []
    @Published private(set) var currentQueueIndex = 0
    @Published private(set) var sleepTimerRemaining: TimeInterval?

    /// Last playback error or warning, if any, for UI/debugging.
    @Published private(set) var lastPlaybackIssue: String?

    private weak var library: LibraryStore?
    private var cachedFileURL: ((LibraryItem) -> URL)?
    private var timeObserver: Any?
    private var playbackEndObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var errorObservation: NSKeyValueObservation?
    private var sleepTimerTask: Task<Void, Never>?

    init() {
        configureAudioSession()
        configureRemoteCommands()
        observePlayerTime()
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.playNext() }
        }
    }

    deinit {
        sleepTimerTask?.cancel()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
        }
    }

    func configure(library: LibraryStore) {
        self.library = library
    }

    func play(_ item: LibraryItem, from items: [LibraryItem], fileURL: @escaping (LibraryItem) -> URL) {
        queue = items
        currentQueueIndex = items.firstIndex(of: item) ?? 0
        cachedFileURL = fileURL
        start(item, url: fileURL(item))
    }

    func togglePlayback() {
        guard currentItem != nil else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlayingInfo()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentItem = nil
        isPlaying = false
        elapsed = 0
        duration = 0
        queue = []
        currentQueueIndex = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        elapsed = seconds
        updateNowPlayingInfo()
    }

    func playNext() {
        guard !queue.isEmpty, let fileURL = cachedFileURL else { return }
        if isShuffleEnabled, queue.count > 1 {
            var next = currentQueueIndex
            while next == currentQueueIndex { next = Int.random(in: queue.indices) }
            currentQueueIndex = next
        } else {
            currentQueueIndex = (currentQueueIndex + 1) % queue.count
        }
        let item = queue[currentQueueIndex]
        start(item, url: fileURL(item))
    }

    func playPrevious() {
        guard !queue.isEmpty, let fileURL = cachedFileURL else { return }
        if elapsed > 4 {
            seek(to: 0)
            return
        }
        currentQueueIndex = currentQueueIndex == 0 ? queue.count - 1 : currentQueueIndex - 1
        let item = queue[currentQueueIndex]
        start(item, url: fileURL(item))
    }

    func toggleShuffle() {
        isShuffleEnabled.toggle()
    }

    func jumpToQueueItem(_ item: LibraryItem) {
        guard let index = queue.firstIndex(of: item), let fileURL = cachedFileURL else { return }
        currentQueueIndex = index
        start(item, url: fileURL(item))
    }

    func moveQueueItem(from source: IndexSet, to destination: Int) {
        guard let current = currentItem else {
            queue.move(fromOffsets: source, toOffset: destination)
            return
        }
        queue.move(fromOffsets: source, toOffset: destination)
        currentQueueIndex = queue.firstIndex(of: current) ?? currentQueueIndex
    }

    func removeFromQueue(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            guard queue.indices.contains(index) else { continue }
            let removingCurrent = index == currentQueueIndex
            queue.remove(at: index)

            if removingCurrent {
                if queue.isEmpty {
                    stop()
                    return
                }
                currentQueueIndex = min(index, queue.count - 1)
                if let fileURL = cachedFileURL {
                    start(queue[currentQueueIndex], url: fileURL(queue[currentQueueIndex]))
                }
            } else if index < currentQueueIndex {
                currentQueueIndex -= 1
            }
        }
    }

    func syncCurrentItem(with library: LibraryStore) {
        guard let current = currentItem,
              let updated = library.items.first(where: { $0.id == current.id }) else { return }
        currentItem = updated
        if currentQueueIndex < queue.count, queue[currentQueueIndex].id == updated.id {
            queue[currentQueueIndex] = updated
        }
        if let index = queue.firstIndex(where: { $0.id == updated.id }) {
            queue[index] = updated
        }
        updateNowPlayingInfo()
    }

    func startSleepTimer(minutes: Int) {
        cancelSleepTimer()
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerRemaining = end.timeIntervalSinceNow

        sleepTimerTask = Task {
            while !Task.isCancelled {
                let remaining = end.timeIntervalSinceNow
                if remaining <= 0 {
                    if isPlaying { togglePlayback() }
                    cancelSleepTimer()
                    return
                }
                sleepTimerRemaining = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerRemaining = nil
    }

    var sleepTimerLabel: String? {
        guard let remaining = sleepTimerRemaining, remaining > 0 else { return nil }
        let total = max(Int(remaining.rounded(.up)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func start(_ item: LibraryItem, url: URL) {
        currentItem = item
        elapsed = 0
        duration = 0
        lastPlaybackIssue = nil
        statusObservation?.invalidate()
        errorObservation?.invalidate()

        library?.recordPlayed(item.id)

        let playerItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: playerItem)

        statusObservation = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.lastPlaybackIssue = nil
                case .failed:
                    self.lastPlaybackIssue = item.error?.localizedDescription ?? "Playback failed."
                    self.isPlaying = false
                default:
                    break
                }
            }
        }
        errorObservation = playerItem.observe(\.error, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.lastPlaybackIssue = item.error?.localizedDescription
            }
        }

        player.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    private func configureAudioSession() {
#if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            // Playback can still be attempted; failures are device/session dependent.
        }
#endif
    }

    private func observePlayerTime() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                self.elapsed = seconds.isFinite ? max(seconds, 0) : 0
                if let itemDuration = self.player.currentItem?.duration.seconds,
                   itemDuration.isFinite {
                    self.duration = max(itemDuration, 0)
                }
                self.updateNowPlayingInfo()
            }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.isPlaying { self.togglePlayback() }
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isPlaying { self.togglePlayback() }
            }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPrevious() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let currentItem else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentItem.title,
            MPMediaItemPropertyArtist: currentItem.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork = lockScreenArtwork(for: currentItem) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func lockScreenArtwork(for item: LibraryItem) -> MPMediaItemArtwork? {
        guard let filename = item.artworkFilename else { return nil }
        let url = AppPaths.artwork.appendingPathComponent(filename)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
