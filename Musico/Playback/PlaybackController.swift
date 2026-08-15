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
    @Published private(set) var lastPlaybackIssue: String?

    private weak var library: LibraryStore?
    private var cachedFileURL: ((LibraryItem) -> URL)?
    private var timeObserver: Any?
    private var playbackEndObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var errorObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var notificationObservers: [NSObjectProtocol] = []
    private var remoteCommandTargets: [(command: MPRemoteCommand, token: Any)] = []

    private var sleepTimerTask: Task<Void, Never>?
    private var sleepTimerDisplayTask: Task<Void, Never>?
    private var sleepTimerEndDate: Date?
    private var wasPlayingBeforeInterruption = false
    private var isApplicationActive = UIApplication.shared.applicationState == .active

    private var cachedNowPlayingArtworkKey: String?
    private var cachedNowPlayingArtwork: MPMediaItemArtwork?

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        configureAudioSession(activate: false)
        configureRemoteCommands()
        observePlayerState()
        observeSystemEvents()
        installTimeObserverIfNeeded()

        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self, notification.object as? AVPlayerItem === self.player.currentItem else { return }
                self.playNext()
            }
        }
        updateRemoteCommandAvailability()
    }

    deinit {
        sleepTimerTask?.cancel()
        sleepTimerDisplayTask?.cancel()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let playbackEndObserver { NotificationCenter.default.removeObserver(playbackEndObserver) }
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        remoteCommandTargets.forEach { $0.command.removeTarget($0.token) }
        statusObservation?.invalidate()
        errorObservation?.invalidate()
        timeControlObservation?.invalidate()
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
        isPlaying ? pausePlayback() : resumePlayback()
    }

    func resumePlayback() {
        guard currentItem != nil else { return }
        configureAudioSession(activate: true)
        player.play()
        setPlaying(true)
    }

    func pausePlayback() {
        guard currentItem != nil else { return }
        player.pause()
        refreshPlaybackProgress()
        setPlaying(false)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        statusObservation?.invalidate()
        errorObservation?.invalidate()
        currentItem = nil
        isPlaying = false
        elapsed = 0
        duration = 0
        queue = []
        currentQueueIndex = 0
        cachedFileURL = nil
        cachedNowPlayingArtworkKey = nil
        cachedNowPlayingArtwork = nil
        cancelSleepTimer()
        updateRemoteCommandAvailability()

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
        deactivateAudioSession()
    }

    func seek(to seconds: Double) {
        guard currentItem != nil else { return }
        let upperBound = duration > 0 ? duration : max(seconds, 0)
        let target = min(max(seconds, 0), upperBound)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        elapsed = target
        updateNowPlayingInfo()
    }

    func skip(by seconds: Double) {
        let current = player.currentTime().seconds
        seek(to: (current.isFinite ? current : elapsed) + seconds)
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
        let currentSeconds = player.currentTime().seconds
        if currentSeconds.isFinite, currentSeconds > 4 {
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
            updateRemoteCommandAvailability()
            return
        }
        queue.move(fromOffsets: source, toOffset: destination)
        currentQueueIndex = queue.firstIndex(of: current) ?? currentQueueIndex
        updateRemoteCommandAvailability()
        updateNowPlayingInfo()
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
        updateRemoteCommandAvailability()
        updateNowPlayingInfo()
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
        cachedNowPlayingArtworkKey = nil
        cachedNowPlayingArtwork = nil
        updateNowPlayingInfo()
    }

    func startSleepTimer(minutes: Int) {
        cancelSleepTimer()
        let endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerEndDate = endDate
        sleepTimerRemaining = endDate.timeIntervalSinceNow
        startSleepTimerDisplayUpdatesIfNeeded()

        sleepTimerTask = Task { [weak self] in
            let delay = max(endDate.timeIntervalSinceNow, 0)
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard let self, !Task.isCancelled, self.sleepTimerEndDate == endDate else { return }
            if self.currentItem != nil { self.pausePlayback() }
            self.clearSleepTimerState()
        }
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        clearSleepTimerState()
    }

    var sleepTimerLabel: String? {
        guard let remaining = sleepTimerRemaining, remaining > 0 else { return nil }
        let total = max(Int(remaining.rounded(.up)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Playback setup

    private func start(_ item: LibraryItem, url: URL) {
        configureAudioSession(activate: true)
        currentItem = item
        elapsed = 0
        duration = 0
        lastPlaybackIssue = nil
        statusObservation?.invalidate()
        errorObservation?.invalidate()
        cachedNowPlayingArtworkKey = nil
        cachedNowPlayingArtwork = nil

        library?.recordPlayed(item.id)
        let playerItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: playerItem)

        statusObservation = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, item === self.player.currentItem else { return }
                switch item.status {
                case .readyToPlay:
                    self.lastPlaybackIssue = nil
                    self.refreshPlaybackProgress()
                    self.updateNowPlayingInfo()
                case .failed:
                    self.lastPlaybackIssue = item.error?.localizedDescription ?? "Playback failed."
                    self.setPlaying(false)
                default:
                    break
                }
            }
        }
        errorObservation = playerItem.observe(\.error, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, item === self.player.currentItem else { return }
                self.lastPlaybackIssue = item.error?.localizedDescription
            }
        }

        player.play()
        isPlaying = true
        updateRemoteCommandAvailability()
        updateNowPlayingInfo()
    }

    private func configureAudioSession(activate: Bool) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            if activate { try session.setActive(true) }
        } catch {
            lastPlaybackIssue = "Audio session unavailable: \(error.localizedDescription)"
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Efficient progress and app lifecycle

    private func installTimeObserverIfNeeded() {
        guard timeObserver == nil, isApplicationActive else { return }
        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, self.isApplicationActive else { return }
                self.refreshPlaybackProgress(time: time)
            }
        }
    }

    private func removeTimeObserver() {
        guard let timeObserver else { return }
        player.removeTimeObserver(timeObserver)
        self.timeObserver = nil
    }

    private func refreshPlaybackProgress(time: CMTime? = nil) {
        let currentSeconds = (time ?? player.currentTime()).seconds
        if currentSeconds.isFinite { elapsed = max(currentSeconds, 0) }

        let newDuration = player.currentItem?.duration.seconds ?? 0
        guard newDuration.isFinite, newDuration > 0 else { return }
        if abs(duration - newDuration) > 0.5 {
            duration = newDuration
            updateNowPlayingInfo()
        } else {
            duration = newDuration
        }
    }

    private func observePlayerState() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self, self.currentItem != nil else { return }
                switch player.timeControlStatus {
                case .playing:
                    if !self.isPlaying { self.setPlaying(true) }
                case .paused:
                    if self.isPlaying {
                        self.refreshPlaybackProgress()
                        self.setPlaying(false)
                    }
                case .waitingToPlayAtSpecifiedRate:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    private func observeSystemEvents() {
        let center = NotificationCenter.default
        notificationObservers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] notification in
            Task { @MainActor in self?.handleAudioInterruption(notification) }
        })
        notificationObservers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] notification in
            Task { @MainActor in self?.handleRouteChange(notification) }
        })
        notificationObservers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleMediaServicesReset() }
        })
        notificationObservers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applicationDidEnterBackground() }
        })
        notificationObservers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applicationDidBecomeActive() }
        })
        notificationObservers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.cachedNowPlayingArtwork = nil
                self?.cachedNowPlayingArtworkKey = nil
                self?.library?.clearArtworkCache()
            }
        })
    }

    private func applicationDidEnterBackground() {
        refreshPlaybackProgress()
        updateNowPlayingInfo()
        isApplicationActive = false
        removeTimeObserver()
        sleepTimerDisplayTask?.cancel()
        sleepTimerDisplayTask = nil
    }

    private func applicationDidBecomeActive() {
        isApplicationActive = true
        refreshPlaybackProgress()
        installTimeObserverIfNeeded()
        startSleepTimerDisplayUpdatesIfNeeded()
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            player.pause()
            refreshPlaybackProgress()
            setPlaying(false)
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if wasPlayingBeforeInterruption, options.contains(.shouldResume) { resumePlayback() }
            else { setPlaying(false) }
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }
        if reason == .oldDeviceUnavailable, isPlaying { pausePlayback() }
    }

    private func handleMediaServicesReset() {
        let shouldResume = isPlaying
        configureAudioSession(activate: shouldResume)
        if shouldResume { player.play() }
        updateNowPlayingInfo()
    }

    // MARK: - Sleep timer

    private func startSleepTimerDisplayUpdatesIfNeeded() {
        sleepTimerDisplayTask?.cancel()
        guard isApplicationActive, let endDate = sleepTimerEndDate else { return }
        sleepTimerDisplayTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isApplicationActive, self.sleepTimerEndDate == endDate {
                self.sleepTimerRemaining = max(endDate.timeIntervalSinceNow, 0)
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { return }
            }
        }
    }

    private func clearSleepTimerState() {
        sleepTimerDisplayTask?.cancel()
        sleepTimerDisplayTask = nil
        sleepTimerEndDate = nil
        sleepTimerRemaining = nil
    }

    // MARK: - Remote controls and lock screen metadata

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]

        addRemoteTarget(center.playCommand) { [weak self] _ in
            guard self != nil else { return .noActionableNowPlayingItem }
            Task { @MainActor in self?.resumePlayback() }
            return .success
        }
        addRemoteTarget(center.pauseCommand) { [weak self] _ in
            guard self != nil else { return .noActionableNowPlayingItem }
            Task { @MainActor in self?.pausePlayback() }
            return .success
        }
        addRemoteTarget(center.togglePlayPauseCommand) { [weak self] _ in
            guard self != nil else { return .noActionableNowPlayingItem }
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }
        addRemoteTarget(center.nextTrackCommand) { [weak self] _ in
            guard self != nil else { return .noActionableNowPlayingItem }
            Task { @MainActor in self?.playNext() }
            return .success
        }
        addRemoteTarget(center.previousTrackCommand) { [weak self] _ in
            guard self != nil else { return .noActionableNowPlayingItem }
            Task { @MainActor in self?.playPrevious() }
            return .success
        }
        addRemoteTarget(center.changePlaybackPositionCommand) { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
        addRemoteTarget(center.skipForwardCommand) { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            Task { @MainActor in self?.skip(by: interval) }
            return self == nil ? .noActionableNowPlayingItem : .success
        }
        addRemoteTarget(center.skipBackwardCommand) { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            Task { @MainActor in self?.skip(by: -interval) }
            return self == nil ? .noActionableNowPlayingItem : .success
        }
    }

    private func addRemoteTarget(_ command: MPRemoteCommand, handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
        let token = command.addTarget(handler: handler)
        remoteCommandTargets.append((command, token))
    }

    private func updateRemoteCommandAvailability() {
        let center = MPRemoteCommandCenter.shared()
        let hasItem = currentItem != nil
        let hasQueueNavigation = hasItem && queue.count > 1
        center.playCommand.isEnabled = hasItem
        center.pauseCommand.isEnabled = hasItem
        center.togglePlayPauseCommand.isEnabled = hasItem
        center.changePlaybackPositionCommand.isEnabled = hasItem
        center.skipForwardCommand.isEnabled = hasItem
        center.skipBackwardCommand.isEnabled = hasItem
        center.nextTrackCommand.isEnabled = hasQueueNavigation
        center.previousTrackCommand.isEnabled = hasItem
    }

    private func setPlaying(_ playing: Bool) {
        guard isPlaying != playing else {
            updateNowPlayingInfo()
            return
        }
        isPlaying = playing
        updateNowPlayingInfo()
    }

    private func updateNowPlayingInfo() {
        guard let currentItem else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentItem.title,
            MPMediaItemPropertyArtist: currentItem.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: currentQueueIndex,
            MPNowPlayingInfoPropertyMediaType: currentItem.kind == .audio
                ? MPNowPlayingInfoMediaType.audio.rawValue
                : MPNowPlayingInfoMediaType.video.rawValue
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork = lockScreenArtwork(for: currentItem) { info[MPMediaItemPropertyArtwork] = artwork }

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }

    private func lockScreenArtwork(for item: LibraryItem) -> MPMediaItemArtwork? {
        let key = "\(item.id.uuidString)|\(item.artworkFilename ?? "")"
        if cachedNowPlayingArtworkKey == key { return cachedNowPlayingArtwork }
        cachedNowPlayingArtworkKey = key

        guard let image = library?.artworkImage(for: item, targetSize: 600) else {
            cachedNowPlayingArtwork = nil
            return nil
        }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        cachedNowPlayingArtwork = artwork
        return artwork
    }
}
