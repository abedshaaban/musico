import AVFoundation
import MediaPlayer

@MainActor
final class PlaybackController: ObservableObject {
    let player = AVPlayer()

    @Published private(set) var currentItem: LibraryItem?
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var isShuffleEnabled = false

    private var queue: [LibraryItem] = []
    private var currentIndex = 0
    private var timeObserver: Any?
    private var playbackEndObserver: NSObjectProtocol?

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
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
        }
    }

    func play(_ item: LibraryItem, from items: [LibraryItem], fileURL: @escaping (LibraryItem) -> URL) {
        queue = items
        currentIndex = items.firstIndex(of: item) ?? 0
        start(item, url: fileURL(item))
        cachedFileURL = fileURL
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
            var next = currentIndex
            while next == currentIndex { next = Int.random(in: queue.indices) }
            currentIndex = next
        } else {
            currentIndex = (currentIndex + 1) % queue.count
        }
        let item = queue[currentIndex]
        start(item, url: fileURL(item))
    }

    func playPrevious() {
        guard !queue.isEmpty, let fileURL = cachedFileURL else { return }
        if elapsed > 4 {
            seek(to: 0)
            return
        }
        currentIndex = currentIndex == 0 ? queue.count - 1 : currentIndex - 1
        let item = queue[currentIndex]
        start(item, url: fileURL(item))
    }

    func toggleShuffle() {
        isShuffleEnabled.toggle()
    }

    private var cachedFileURL: ((LibraryItem) -> URL)?

    private func start(_ item: LibraryItem, url: URL) {
        currentItem = item
        elapsed = 0
        duration = 0
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
