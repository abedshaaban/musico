import AVFoundation
import MediaPlayer
import MediaToolbox
import QuartzCore
import UIKit

@MainActor
final class PlaybackController: ObservableObject {
    let player = AVQueuePlayer()

    @Published private(set) var currentItem: LibraryItem?
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var isShuffleEnabled = false
    @Published var isAudioOnlyMode = false {
        didSet {
            guard isAudioOnlyMode != oldValue else { return }
            updateNowPlayingInfo()
        }
    }
    @Published var isNormalizationEnabled = UserDefaults.standard.object(forKey: "playbackNormalization") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isNormalizationEnabled, forKey: "playbackNormalization")
            applyPlaybackVolume()
        }
    }
    @Published var isGaplessEnabled = UserDefaults.standard.object(forKey: "playbackGapless") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isGaplessEnabled, forKey: "playbackGapless")
            prepareNextItemIfNeeded()
        }
    }
    @Published var crossfadeSeconds = UserDefaults.standard.double(forKey: "playbackCrossfade") {
        didSet {
            UserDefaults.standard.set(min(max(crossfadeSeconds, 0), 8), forKey: "playbackCrossfade")
            prepareNextItemIfNeeded()
        }
    }
    @Published private(set) var queue: [LibraryItem] = []
    @Published private(set) var currentQueueIndex = 0
    @Published private(set) var sleepTimerRemaining: TimeInterval?
    @Published private(set) var lastPlaybackIssue: String?
    @Published private(set) var waveformLevel: CGFloat = 0
    @Published private(set) var waveformFrequency: CGFloat = 220
    @Published private(set) var hasLiveWaveformData = false

    private weak var library: LibraryStore?
    private var cachedFileURL: ((LibraryItem) -> URL)?
    private var timeObserver: Any?
    private var playbackEndObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var errorObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var activePlayerItem: AVPlayerItem?
    private var preloadedPlayerItem: AVPlayerItem?
    private var preloadedLibraryItem: LibraryItem?
    private var preloadedQueueIndex: Int?
    private var notificationObservers: [NSObjectProtocol] = []
    private var remoteCommandTargets: [(command: MPRemoteCommand, token: Any)] = []

    private var sleepTimerTask: Task<Void, Never>?
    private var sleepTimerDisplayTask: Task<Void, Never>?
    private var sleepTimerEndDate: Date?
    private var wasPlayingBeforeInterruption = false
    private var isApplicationActive = UIApplication.shared.applicationState == .active

    private var cachedNowPlayingArtworkKey: String?
    private var cachedNowPlayingArtwork: MPMediaItemArtwork?
    private var lastResumeSaveAt: TimeInterval = 0
    private var crossfadeTask: Task<Void, Never>?
    private var secondaryPlayer: AVPlayer?
    private var isCrossfading = false

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
                guard let self, let ended = notification.object as? AVPlayerItem,
                      ended === self.activePlayerItem else { return }
                self.finishCurrentTrack()
            }
        }
        updateRemoteCommandAvailability()
    }

    deinit {
        sleepTimerTask?.cancel()
        sleepTimerDisplayTask?.cancel()
        crossfadeTask?.cancel()
        secondaryPlayer?.pause()
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
        cachedFileURL = library.fileURL
        restorePersistedPlaybackIfNeeded()
    }

    func reloadSettings() {
        isNormalizationEnabled = UserDefaults.standard.object(forKey: "playbackNormalization") as? Bool ?? true
        isGaplessEnabled = UserDefaults.standard.object(forKey: "playbackGapless") as? Bool ?? true
        crossfadeSeconds = min(max(UserDefaults.standard.double(forKey: "playbackCrossfade"), 0), 8)
    }

    func play(_ item: LibraryItem, from items: [LibraryItem], fileURL: @escaping (LibraryItem) -> URL) {
        queue = items
        currentQueueIndex = items.firstIndex(of: item) ?? 0
        cachedFileURL = fileURL
        start(item, url: fileURL(item), resumeAt: item.resumePosition)
    }

    func togglePlayback() {
        isPlaying ? pausePlayback() : resumePlayback()
    }

    func resumePlayback() {
        guard currentItem != nil else { return }
        configureAudioSession(activate: true)
        player.play()
        applyPlaybackVolume()
        setPlaying(true)
        persistPlaybackState()
    }

    func pausePlayback() {
        guard currentItem != nil else { return }
        cancelCrossfade()
        player.pause()
        refreshPlaybackProgress()
        saveResumePosition()
        setPlaying(false)
        persistPlaybackState()
    }

    func stop() {
        player.pause()
        saveResumePosition()
        player.removeAllItems()
        statusObservation?.invalidate()
        errorObservation?.invalidate()
        currentItem = nil
        isPlaying = false
        elapsed = 0
        duration = 0
        waveformLevel = 0
        waveformFrequency = 220
        hasLiveWaveformData = false
        queue = []
        currentQueueIndex = 0
        cachedFileURL = nil
        cachedNowPlayingArtworkKey = nil
        cachedNowPlayingArtwork = nil
        activePlayerItem = nil
        preloadedPlayerItem = nil
        preloadedLibraryItem = nil
        preloadedQueueIndex = nil
        crossfadeTask?.cancel()
        secondaryPlayer?.pause()
        secondaryPlayer = nil
        isCrossfading = false
        cancelSleepTimer()
        updateRemoteCommandAvailability()

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
        deactivateAudioSession()
        try? FileManager.default.removeItem(at: AppPaths.playbackFile)
    }

    func seek(to seconds: Double) {
        guard currentItem != nil else { return }
        cancelCrossfade()
        let upperBound = duration > 0 ? duration : max(seconds, 0)
        let target = min(max(seconds, 0), upperBound)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        elapsed = target
        updateNowPlayingInfo()
        persistPlaybackState()
    }

    func skip(by seconds: Double) {
        let current = player.currentTime().seconds
        seek(to: (current.isFinite ? current : elapsed) + seconds)
    }

    func playNext() {
        guard !queue.isEmpty, let fileURL = cachedFileURL else { return }
        saveResumePosition()
        if isShuffleEnabled, queue.count > 1 {
            var next = currentQueueIndex
            while next == currentQueueIndex { next = Int.random(in: queue.indices) }
            currentQueueIndex = next
        } else {
            currentQueueIndex = (currentQueueIndex + 1) % queue.count
        }
        let item = queue[currentQueueIndex]
        start(item, url: fileURL(item), resumeAt: item.resumePosition)
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
        start(item, url: fileURL(item), resumeAt: item.resumePosition)
    }

    func toggleShuffle() {
        isShuffleEnabled.toggle()
        persistPlaybackState()
    }

    func jumpToQueueItem(_ item: LibraryItem) {
        guard let index = queue.firstIndex(of: item), let fileURL = cachedFileURL else { return }
        currentQueueIndex = index
        start(item, url: fileURL(item), resumeAt: item.resumePosition)
    }

    func moveQueueItem(from source: IndexSet, to destination: Int) {
        guard let current = currentItem else {
            queue.move(fromOffsets: source, toOffset: destination)
            updateRemoteCommandAvailability()
            persistPlaybackState()
            return
        }
        queue.move(fromOffsets: source, toOffset: destination)
        currentQueueIndex = queue.firstIndex(of: current) ?? currentQueueIndex
        updateRemoteCommandAvailability()
        updateNowPlayingInfo()
        persistPlaybackState()
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
                    start(queue[currentQueueIndex], url: fileURL(queue[currentQueueIndex]), resumeAt: queue[currentQueueIndex].resumePosition)
                }
            } else if index < currentQueueIndex {
                currentQueueIndex -= 1
            }
        }
        updateRemoteCommandAvailability()
        updateNowPlayingInfo()
        persistPlaybackState()
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

    func reconcile(with library: LibraryStore) {
        let validIDs = Set(library.items.map(\.id))
        queue = queue.compactMap { queued in library.items.first(where: { $0.id == queued.id }) }
        guard let current = currentItem else { persistPlaybackState(); return }
        guard validIDs.contains(current.id), let updated = library.items.first(where: { $0.id == current.id }) else {
            stop()
            return
        }
        currentItem = updated
        currentQueueIndex = queue.firstIndex(where: { $0.id == updated.id }) ?? 0
        persistPlaybackState()
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

    private func start(
        _ item: LibraryItem,
        url: URL,
        autoplay: Bool = true,
        resumeAt: Double = 0,
        recordPlay: Bool = true
    ) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            lastPlaybackIssue = "The media file is missing. Open Library Maintenance to remove or repair its record."
            return
        }
        if autoplay { configureAudioSession(activate: true) }
        crossfadeTask?.cancel()
        secondaryPlayer?.pause()
        secondaryPlayer = nil
        isCrossfading = false
        player.volume = 1
        currentItem = item
        elapsed = 0
        duration = 0
        waveformLevel = 0
        waveformFrequency = 220
        hasLiveWaveformData = false
        lastPlaybackIssue = nil
        statusObservation?.invalidate()
        errorObservation?.invalidate()
        cachedNowPlayingArtworkKey = nil
        cachedNowPlayingArtwork = nil

        if recordPlay { library?.recordPlayed(item.id) }
        let playerItem = makePlayerItem(for: item, url: url)
        player.removeAllItems()
        player.insert(playerItem, after: nil)
        activePlayerItem = playerItem
        preloadedPlayerItem = nil
        preloadedLibraryItem = nil
        preloadedQueueIndex = nil
        observe(playerItem, for: item, resumeAt: resumeAt)
        applyPlaybackVolume()
        if autoplay { player.play() } else { player.pause() }
        isPlaying = autoplay
        updateRemoteCommandAvailability()
        updateNowPlayingInfo()
        persistPlaybackState()
    }

    private func makePlayerItem(for item: LibraryItem, url: URL) -> AVPlayerItem {
        let playerItem = AVPlayerItem(url: url)
        playerItem.audioMix = PlaybackAudioTap.makeAudioMix(for: playerItem.asset) { [weak self] level, frequency in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.currentItem?.id == item.id else { return }
                self.waveformLevel = CGFloat(level)
                self.waveformFrequency = CGFloat(frequency)
                self.hasLiveWaveformData = true
            }
        }
        return playerItem
    }

    private func observe(_ playerItem: AVPlayerItem, for item: LibraryItem, resumeAt: Double = 0) {
        statusObservation?.invalidate()
        errorObservation?.invalidate()
        statusObservation = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, item === self.activePlayerItem else { return }
                switch item.status {
                case .readyToPlay:
                    self.lastPlaybackIssue = nil
                    self.refreshPlaybackProgress()
                    if resumeAt > 0.1, resumeAt < self.duration - 5 {
                        self.player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600))
                        self.elapsed = resumeAt
                    }
                    self.prepareNextItemIfNeeded()
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
                guard let self, item === self.activePlayerItem else { return }
                self.lastPlaybackIssue = item.error?.localizedDescription
            }
        }
    }

    private func finishCurrentTrack() {
        if let currentItem {
            library?.updateResumePosition(itemID: currentItem.id, seconds: 0, duration: duration, completed: true)
        }
        if let preloadedPlayerItem,
           player.currentItem === preloadedPlayerItem,
           let next = preloadedLibraryItem,
           let nextIndex = preloadedQueueIndex {
            currentItem = next
            currentQueueIndex = nextIndex
            activePlayerItem = preloadedPlayerItem
            self.preloadedPlayerItem = nil
            preloadedLibraryItem = nil
            preloadedQueueIndex = nil
            elapsed = 0
            duration = 0
            library?.recordPlayed(next.id)
            observe(preloadedPlayerItem, for: next)
            applyPlaybackVolume()
            prepareNextItemIfNeeded()
            updateRemoteCommandAvailability()
            updateNowPlayingInfo()
            persistPlaybackState()
        } else if !isCrossfading {
            playNext()
        }
    }

    private func nextQueueIndex() -> Int? {
        guard queue.count > 1 else { return nil }
        if isShuffleEnabled {
            var index = currentQueueIndex
            while index == currentQueueIndex { index = Int.random(in: queue.indices) }
            return index
        }
        return (currentQueueIndex + 1) % queue.count
    }

    private func prepareNextItemIfNeeded() {
        if let preloadedPlayerItem {
            player.remove(preloadedPlayerItem)
            self.preloadedPlayerItem = nil
            preloadedLibraryItem = nil
            preloadedQueueIndex = nil
        }
        guard isGaplessEnabled, crossfadeSeconds == 0,
              currentItem?.kind == .audio,
              let nextIndex = nextQueueIndex(), queue.indices.contains(nextIndex),
              queue[nextIndex].kind == .audio,
              let fileURL = cachedFileURL else { return }
        let next = queue[nextIndex]
        let url = fileURL(next)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let item = makePlayerItem(for: next, url: url)
        player.insert(item, after: activePlayerItem)
        preloadedPlayerItem = item
        preloadedLibraryItem = next
        preloadedQueueIndex = nextIndex
    }

    private func beginCrossfadeIfNeeded() {
        guard !isCrossfading, crossfadeSeconds > 0, isPlaying,
              let currentItem, currentItem.kind == .audio,
              duration > crossfadeSeconds,
              duration - elapsed <= crossfadeSeconds + 0.25,
              let nextIndex = nextQueueIndex(), queue.indices.contains(nextIndex),
              queue[nextIndex].kind == .audio,
              let fileURL = cachedFileURL else { return }
        let next = queue[nextIndex]
        let url = fileURL(next)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        isCrossfading = true
        let outgoingGain = playbackVolume(for: currentItem)
        let incomingGain = playbackVolume(for: next)
        let incoming = AVPlayer(url: url)
        incoming.volume = 0
        secondaryPlayer = incoming
        incoming.play()

        let seconds = crossfadeSeconds
        crossfadeTask = Task { [weak self] in
            let steps = max(Int(seconds * 10), 1)
            for step in 1...steps {
                guard let self, !Task.isCancelled else { return }
                let progress = Float(step) / Float(steps)
                self.player.volume = outgoingGain * (1 - progress)
                incoming.volume = incomingGain * progress
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            let carriedTime = incoming.currentTime().seconds
            incoming.pause()
            self.secondaryPlayer = nil
            self.crossfadeTask = nil
            self.isCrossfading = false
            self.library?.updateResumePosition(itemID: currentItem.id, seconds: 0, duration: self.duration, completed: true)
            self.currentQueueIndex = nextIndex
            self.start(next, url: url, resumeAt: carriedTime.isFinite ? carriedTime : 0)
        }
    }

    private func playbackVolume(for item: LibraryItem) -> Float {
        guard isNormalizationEnabled, let gain = item.normalizationGainDB else { return 1 }
        return Float(min(max(pow(10, gain / 20), 0.2), 1))
    }

    private func applyPlaybackVolume() {
        guard let currentItem, !isCrossfading else { return }
        player.volume = playbackVolume(for: currentItem)
    }

    private func cancelCrossfade() {
        crossfadeTask?.cancel()
        crossfadeTask = nil
        secondaryPlayer?.pause()
        secondaryPlayer = nil
        isCrossfading = false
        applyPlaybackVolume()
    }

    private func saveResumePosition() {
        guard let currentItem else { return }
        library?.updateResumePosition(itemID: currentItem.id, seconds: elapsed, duration: duration)
    }

    private func persistPlaybackState() {
        guard let currentItem else { return }
        AppPaths.ensureDirectories()
        do {
            let state = PersistedPlaybackState(
                queueIDs: queue.map(\.id),
                currentItemID: currentItem.id,
                currentQueueIndex: currentQueueIndex,
                elapsed: elapsed,
                isShuffleEnabled: isShuffleEnabled
            )
            try JSONEncoder.musico.encode(state).write(to: AppPaths.playbackFile, options: .atomic)
        } catch {
            lastPlaybackIssue = "The playback queue could not be saved: \(error.localizedDescription)"
        }
    }

    private func restorePersistedPlaybackIfNeeded() {
        guard currentItem == nil, let library,
              let data = try? Data(contentsOf: AppPaths.playbackFile),
              let state = try? JSONDecoder.musico.decode(PersistedPlaybackState.self, from: data) else { return }
        let restoredQueue = state.queueIDs.compactMap { id in library.items.first(where: { $0.id == id && !library.isMissing($0) }) }
        guard !restoredQueue.isEmpty else {
            try? FileManager.default.removeItem(at: AppPaths.playbackFile)
            return
        }
        queue = restoredQueue
        isShuffleEnabled = state.isShuffleEnabled
        currentQueueIndex = restoredQueue.firstIndex(where: { $0.id == state.currentItemID })
            ?? min(max(state.currentQueueIndex, 0), restoredQueue.count - 1)
        let item = restoredQueue[currentQueueIndex]
        start(item, url: library.fileURL(for: item), autoplay: false,
              resumeAt: max(state.elapsed, item.resumePosition), recordPlay: false)
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
        let wholeSecond = floor(elapsed)
        if wholeSecond - lastResumeSaveAt >= 10 {
            lastResumeSaveAt = wholeSecond
            saveResumePosition()
            persistPlaybackState()
        }
        beginCrossfadeIfNeeded()
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
        isApplicationActive = false
        refreshPlaybackProgress()
        saveResumePosition()
        persistPlaybackState()
        updateRemoteCommandAvailability()
        updateNowPlayingInfo()
        removeTimeObserver()
        sleepTimerDisplayTask?.cancel()
        sleepTimerDisplayTask = nil
    }

    private func applicationDidBecomeActive() {
        isApplicationActive = true
        refreshPlaybackProgress()
        updateRemoteCommandAvailability()
        updateNowPlayingInfo()
        installTimeObserverIfNeeded()
        startSleepTimerDisplayUpdatesIfNeeded()
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            cancelCrossfade()
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
        if !playing { waveformLevel = 0 }
        updateNowPlayingInfo()
    }

    private func updateNowPlayingInfo() {
        guard let currentItem else { return }
        // Video items continue as audio when Musico is backgrounded. Advertising
        // them as audio keeps iOS's Lock Screen in the transport-control mode that
        // matches the app's actual background behavior.
        let isNowPlayingAudio = currentItem.kind == .audio
            || isAudioOnlyMode
            || !isApplicationActive
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentItem.title,
            MPMediaItemPropertyArtist: currentItem.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: currentQueueIndex,
            MPNowPlayingInfoPropertyMediaType: isNowPlayingAudio
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

// MARK: - Audio-reactive waveform analysis

/// Reads the decoded PCM that is already passing through `AVPlayer`, without
/// changing it, and publishes a lightweight level/frequency estimate for the UI.
private enum PlaybackAudioTap {
    static func makeAudioMix(
        for asset: AVAsset,
        onAnalysis: @escaping (Float, Float) -> Void
    ) -> AVAudioMix? {
        guard let track = asset.tracks(withMediaType: .audio).first else { return nil }

        let context = PlaybackAudioTapContext(onAnalysis: onAnalysis)
        let retainedContext = Unmanaged.passRetained(context).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: retainedContext,
            init: { _, clientInfo, storageOut in
                storageOut.pointee = clientInfo
            },
            finalize: { tap in
                let storage = MTAudioProcessingTapGetStorage(tap)
                Unmanaged<PlaybackAudioTapContext>.fromOpaque(storage).release()
            },
            prepare: { tap, _, format in
                let storage = MTAudioProcessingTapGetStorage(tap)
                let context = Unmanaged<PlaybackAudioTapContext>.fromOpaque(storage).takeUnretainedValue()
                context.prepare(format: format.pointee)
            },
            unprepare: nil,
            process: { tap, frameCount, _, bufferList, framesOut, flagsOut in
                let status = MTAudioProcessingTapGetSourceAudio(
                    tap,
                    frameCount,
                    bufferList,
                    flagsOut,
                    nil,
                    framesOut
                )
                guard status == noErr,
                      framesOut.pointee > 0 else { return }
                let storage = MTAudioProcessingTapGetStorage(tap)
                let context = Unmanaged<PlaybackAudioTapContext>.fromOpaque(storage).takeUnretainedValue()
                context.analyze(bufferList: bufferList, frameCount: framesOut.pointee)
            }
        )

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            &tap
        )
        guard status == noErr, let tap else {
            Unmanaged<PlaybackAudioTapContext>.fromOpaque(retainedContext).release()
            return nil
        }

        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }
}

private final class PlaybackAudioTapContext {
    private let onAnalysis: (Float, Float) -> Void
    private var format = AudioStreamBasicDescription()
    private var smoothedLevel: Float = 0
    private var smoothedFrequency: Float = 220
    private var lastPublishTime: CFTimeInterval = 0

    init(onAnalysis: @escaping (Float, Float) -> Void) {
        self.onAnalysis = onAnalysis
    }

    func prepare(format: AudioStreamBasicDescription) {
        self.format = format
        smoothedLevel = 0
        smoothedFrequency = 220
        lastPublishTime = 0
    }

    func analyze(bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: CMItemCount) {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard let buffer = buffers.first, let data = buffer.mData else { return }

        let isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let isSignedInteger = format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0
        let isInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        let channelStride = isInterleaved ? max(Int(buffer.mNumberChannels), 1) : 1
        let requestedFrames = max(Int(frameCount), 0)

        var sumSquares: Float = 0
        var crossingCount = 0
        var previousSample: Float = 0
        var analyzedFrames = 0

        if isFloat, format.mBitsPerChannel == 32 {
            let samples = data.assumingMemoryBound(to: Float.self)
            let availableSamples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            analyzedFrames = min(requestedFrames, availableSamples / channelStride)
            for frame in 0..<analyzedFrames {
                let sample = samples[frame * channelStride]
                sumSquares += sample * sample
                if frame > 0, (sample >= 0) != (previousSample >= 0) { crossingCount += 1 }
                previousSample = sample
            }
        } else if isSignedInteger, format.mBitsPerChannel == 16 {
            let samples = data.assumingMemoryBound(to: Int16.self)
            let availableSamples = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
            analyzedFrames = min(requestedFrames, availableSamples / channelStride)
            for frame in 0..<analyzedFrames {
                let sample = Float(samples[frame * channelStride]) / Float(Int16.max)
                sumSquares += sample * sample
                if frame > 0, (sample >= 0) != (previousSample >= 0) { crossingCount += 1 }
                previousSample = sample
            }
        }

        guard analyzedFrames > 0 else { return }
        let rms = sqrt(sumSquares / Float(analyzedFrames))
        let decibels = 20 * log10(max(rms, 0.000_1))
        let normalizedLevel = min(max((decibels + 48) / 42, 0), 1)
        smoothedLevel = (smoothedLevel * 0.68) + (normalizedLevel * 0.32)

        if crossingCount > 1, format.mSampleRate > 0 {
            let estimatedFrequency = Float(crossingCount) * Float(format.mSampleRate)
                / (2 * Float(analyzedFrames))
            let clampedFrequency = min(max(estimatedFrequency, 55), 4_000)
            smoothedFrequency = (smoothedFrequency * 0.82) + (clampedFrequency * 0.18)
        }

        let now = CACurrentMediaTime()
        guard now - lastPublishTime >= 1.0 / 20.0 else { return }
        lastPublishTime = now
        onAnalysis(smoothedLevel, smoothedFrequency)
    }
}
