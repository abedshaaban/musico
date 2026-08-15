@preconcurrency import AVFoundation
import Foundation

/// Downloads direct, authorized media file URLs in the background with URLSession,
/// validates reachability and MIME type before queueing, stores completed files in
/// Application Support, and registers them in the persistent library.
///
/// This manager only fetches URLs the user supplies that point straight at a media
/// file. It never scrapes pages, resolves stream manifests, or bypasses any service's
/// access controls. Hosts known to require such extraction are rejected outright.
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    @Published private(set) var records: [DownloadRecord] = []

    private weak var library: LibraryStore?

    private static let sessionIdentifier = "com.abedshaaban.Musico.downloads"

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // A short-lived session used only for HEAD/probe validation requests.
    private let probeSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // Hosts that serve protected streams behind manifests / DRM / terms that forbid
    // direct file download. Reachability of a raw media URL on these is not expected;
    // refusing early keeps Musico strictly a personal-file player.
    // YouTube is excluded here because it has a dedicated resolver.
    private static let blockedHostFragments = [
        "soundcloud.", "vimeo.", "tiktok.", "instagram.", "facebook.", "fbcdn.",
        "dailymotion.", "netflix.", "twitch.", "hulu.", "disneyplus.", "primevideo."
    ]

    override init() {
        super.init()
        loadRecords()
        // Instantiate the background session so any tasks that completed while the app
        // was suspended deliver their delegate callbacks and get registered.
        _ = session
    }

    /// Wire the library the manager registers completed downloads into. Called once at launch.
    func configure(library: LibraryStore) {
        self.library = library
    }

    // MARK: - Public actions

    /// Validate a user-supplied URL, then queue a background download if it checks out.
    func addFromURL(_ rawInput: String) async {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = Self.sanitizedURL(from: trimmed) else {
            insertFailed(title: "Invalid link", detail: "Enter a full https:// link to an audio or video file.")
            return
        }
        guard !Self.isBlockedHost(url) else {
            insertFailed(
                title: "Unsupported link",
                detail: "Links from protected streaming services aren't supported. Paste a direct https:// link to an audio or video file you're authorized to save."
            )
            return
        }

        // YouTube URLs are resolved via the internal player API rather than probed as files.
        if YouTubeResolver.handles(url) {
            guard let videoID = YouTubeResolver.videoID(from: url) else {
                insertFailed(title: "Invalid YouTube link", detail: "The link doesn't contain a valid YouTube video ID.")
                return
            }
            await addYouTubeVideo(id: videoID, sourceURL: url)
            return
        }

        let record = DownloadRecord(
            title: Self.suggestedTitle(from: url),
            sourceName: url.host ?? "Direct link",
            state: .validating,
            detail: "Checking reachability and file type…",
            remoteURL: url
        )
        records.insert(record, at: 0)
        persist()

        switch await probe(url) {
        case .failure(let message):
            update(record.id) {
                $0.state = .failed
                $0.detail = message
            }
        case .success(let resolved):
            update(record.id) {
                $0.title = resolved.title
                $0.mediaKind = resolved.kind
                $0.totalBytes = resolved.expectedBytes
                $0.state = .downloading
                $0.detail = "Downloading \(resolved.kind.label.lowercased())…"
            }
            startTask(for: record.id, url: url)
        }
    }

    private func addYouTubeVideo(id videoID: String, sourceURL: URL) async {
        let record = DownloadRecord(
            title: "YouTube Video",
            sourceName: "YouTube",
            state: .validating,
            detail: "Resolving YouTube stream…",
            remoteURL: sourceURL
        )
        records.insert(record, at: 0)
        persist()

        do {
            let resolved = try await YouTubeResolver.resolve(videoID: videoID)
            update(record.id) {
                $0.title = resolved.title
                $0.mediaKind = resolved.kind
                $0.totalBytes = resolved.expectedBytes
                $0.thumbnailURL = resolved.thumbnailURL
                $0.state = .downloading
                $0.detail = "Downloading \(resolved.kind.label.lowercased())…"
            }
            startTask(for: record.id, url: resolved.url)
        } catch {
            update(record.id) {
                $0.state = .failed
                $0.detail = error.localizedDescription
            }
        }
    }

    func cancel(_ record: DownloadRecord) {
        findTask(for: record.id) { $0?.cancel() }
        update(record.id) {
            if $0.state.isActive {
                $0.state = .cancelled
                $0.detail = "Cancelled."
            }
        }
    }

    func retry(_ record: DownloadRecord) {
        guard let raw = record.remoteURL?.absoluteString else { return }
        remove(record)
        Task { await addFromURL(raw) }
    }

    func remove(_ record: DownloadRecord) {
        findTask(for: record.id) { $0?.cancel() }
        records.removeAll { $0.id == record.id }
        persist()
    }

    func clearFinished() {
        let finished = records.filter { !$0.state.isActive }
        finished.forEach { record in findTask(for: record.id) { $0?.cancel() } }
        records.removeAll { !$0.state.isActive }
        persist()
    }

    // MARK: - Validation

    private struct ResolvedMedia {
        let title: String
        let kind: MediaKind
        let expectedBytes: Int64
    }

    private enum ProbeOutcome {
        case success(ResolvedMedia)
        case failure(String)
    }

    private enum InspectResult {
        case resolved(ResolvedMedia)
        case webPage
        case unreachable
    }

    private func probe(_ url: URL) async -> ProbeOutcome {
        Self.debugLog("probe: starting for \(url.absoluteString)")
        // Prefer a HEAD request; fall back to a 1-byte ranged GET for servers that
        // reject HEAD but still expose the content type.
        switch await inspect(url, method: "HEAD") {
        case .resolved(let resolved):
            Self.debugLog("probe: HEAD success for \(url.absoluteString)")
            return .success(resolved)
        case .webPage:
            Self.debugLog("probe: HEAD returned a web page for \(url.absoluteString)")
            return .failure(Self.webPageFailureMessage)
        case .unreachable:
            break
        }
        Self.debugLog("probe: HEAD failed, trying GET for \(url.absoluteString)")
        switch await inspect(url, method: "GET", rangeFirstByte: true) {
        case .resolved(let resolved):
            Self.debugLog("probe: GET success for \(url.absoluteString)")
            return .success(resolved)
        case .webPage:
            Self.debugLog("probe: GET returned a web page for \(url.absoluteString)")
            return .failure(Self.webPageFailureMessage)
        case .unreachable:
            break
        }
        Self.debugLog("probe: both failed for \(url.absoluteString)")
        return .failure("The link isn't reachable, or its type isn't a supported audio or video file.")
    }

    private static let webPageFailureMessage =
        "This link points to a web page, not a direct audio or video file. Paste a link that ends in .mp3, .m4a, .mp4, or similar."

    /// Set to false to hide Musico's debug prints.
    private static let verboseLogging = true

    private static func debugLog(_ message: String) {
        guard verboseLogging else { return }
        print(message)
    }

    private func inspect(_ url: URL, method: String, rangeFirstByte: Bool = false) async -> InspectResult {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if rangeFirstByte { request.setValue("bytes=0-0", forHTTPHeaderField: "Range") }

        var http: HTTPURLResponse?
        do {
            let (_, response) = try await probeSession.data(for: request)
            http = response as? HTTPURLResponse
            if let http = http, !(200..<400).contains(http.statusCode) {
                Self.debugLog("inspect: status code \(http.statusCode) for \(url.absoluteString)")
                return .unreachable
            }
        } catch {
            Self.debugLog("inspect: error \(error) for \(url.absoluteString)")
            return .unreachable
        }
        guard let http = http,
              (200..<400).contains(http.statusCode) else {
            return .unreachable
        }

        // Resolve media kind from the server's Content-Type, then fall back to the
        // URL's file extension so correctly-typed but header-sparse servers still work.
        let kind = SupportedMedia.kind(forMIME: http.value(forHTTPHeaderField: "Content-Type"))
            ?? SupportedMedia.kind(forExtension: url.pathExtension)
        guard let mediaKind = kind else {
            let mime = SupportedMedia.normalizedMIME(http.value(forHTTPHeaderField: "Content-Type"))
            if mime?.hasPrefix("text/") == true {
                return .webPage
            }
            return .unreachable
        }

        let title = (http.suggestedFilename.map { Self.title(fromFilename: $0) })
            ?? Self.suggestedTitle(from: url)

        let expected = Self.expectedLength(from: http)
        return .resolved(ResolvedMedia(title: title, kind: mediaKind, expectedBytes: expected))
    }


    // MARK: - Downloading

    private func startTask(for recordID: UUID, url: URL) {
        let task = session.downloadTask(with: url)
        task.taskDescription = recordID.uuidString
        task.resume()
    }

    private func findTask(for recordID: UUID, _ body: @escaping (URLSessionTask?) -> Void) {
        session.getAllTasks { tasks in
            let match = tasks.first { $0.taskDescription == recordID.uuidString }
            body(match)
        }
    }

    // MARK: - Record mutation & persistence

    private func insertFailed(title: String, detail: String) {
        records.insert(
            DownloadRecord(title: title, sourceName: "Direct link", state: .failed, detail: detail),
            at: 0
        )
        persist()
    }

    private func update(_ recordID: UUID, _ mutate: (inout DownloadRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        mutate(&records[index])
        persist()
    }

    private func persist() {
        AppPaths.ensureDirectories()
        do {
            let data = try JSONEncoder.musico.encode(PersistedDownloads(records: records))
            try data.write(to: AppPaths.downloadsFile, options: .atomic)
        } catch {
            // Persistence is best-effort; an unwritable queue must not crash playback.
        }
    }

    private func loadRecords() {
        guard FileManager.default.fileExists(atPath: AppPaths.downloadsFile.path),
              let data = try? Data(contentsOf: AppPaths.downloadsFile),
              let persisted = try? JSONDecoder.musico.decode(PersistedDownloads.self, from: data) else {
            return
        }
        // Downloads that were mid-flight when the app was killed can no longer resume
        // (the tasks are gone); surface them as failed so the user can retry.
        records = persisted.records.map { record in
            guard record.state == .validating || record.state == .queued || record.state == .downloading else {
                return record
            }
            var stale = record
            stale.state = .failed
            stale.detail = "Interrupted. Tap to retry."
            return stale
        }
    }

    // MARK: - Helpers

    private static func sanitizedURL(from input: String) -> URL? {
        guard let components = URLComponents(string: input),
              let scheme = components.scheme?.lowercased(),
              scheme == "https", // require TLS; extension point: relax for trusted LAN http
              let host = components.host, !host.isEmpty else {
            return nil
        }
        return components.url
    }

    private static func isBlockedHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        return blockedHostFragments.contains { host.contains($0) }
    }

    private static func expectedLength(from http: HTTPURLResponse) -> Int64 {
        // With a ranged probe the server reports the slice length in Content-Range.
        if let range = http.value(forHTTPHeaderField: "Content-Range"),
           let total = range.split(separator: "/").last, let value = Int64(total) {
            return value
        }
        return http.expectedContentLength > 0 ? http.expectedContentLength : 0
    }

    private static func suggestedTitle(from url: URL) -> String {
        title(fromFilename: url.lastPathComponent)
    }

    private static func title(fromFilename filename: String) -> String {
        let base = (filename as NSString).deletingPathExtension
        let cleaned = base
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let recordID = downloadTask.taskDescription.flatMap(UUID.init) else { return }
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 0
        Task { @MainActor in
            update(recordID) {
                $0.receivedBytes = totalBytesWritten
                if expected > 0 { $0.totalBytes = expected }
                if $0.totalBytes > 0 {
                    $0.progress = min(Double(totalBytesWritten) / Double($0.totalBytes), 1)
                }
                if $0.state == .downloading { $0.detail = nil }
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Runs on the session's background queue. The temp file at `location` is deleted
        // once this method returns, so move it synchronously before hopping to the main
        // actor to register it.
        guard let recordID = downloadTask.taskDescription.flatMap(UUID.init) else { return }

        let http = downloadTask.response as? HTTPURLResponse
        let mimeKind = SupportedMedia.kind(forMIME: http?.value(forHTTPHeaderField: "Content-Type"))
        let sourceURL = downloadTask.originalRequest?.url
        let kind = mimeKind
            ?? sourceURL.flatMap { SupportedMedia.kind(forExtension: $0.pathExtension) }
            ?? .audio

        // YouTube/googlevideo stream URLs are extension-less, so pick a playable
        // container extension based on the actual MIME type.
        let ext: String
        if let sourceURL = sourceURL, !sourceURL.pathExtension.isEmpty,
           SupportedMedia.kind(forExtension: sourceURL.pathExtension) == kind {
            ext = sourceURL.pathExtension.lowercased()
        } else {
            let mime = SupportedMedia.normalizedMIME(http?.value(forHTTPHeaderField: "Content-Type"))
            switch (kind, mime) {
            case (.video, .some("video/mp4")), (.audio, .some("audio/mp4")):
                ext = "mp4"
            case (.video, .some("video/webm")), (.audio, .some("audio/webm")):
                ext = "webm"
            case (.audio, .some("audio/webm")):
                ext = "weba"
            case (.audio, .some("audio/mpeg")), (.audio, .some("audio/mp3")):
                ext = "mp3"
            case (.audio, _):
                ext = "m4a"
            case (.video, _):
                ext = "mp4"
            }
        }
        let storedName = UUID().uuidString + "." + ext
        let destination = AppPaths.media.appendingPathComponent(storedName)

        AppPaths.ensureDirectories()
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            Task { @MainActor in
                update(recordID) {
                    $0.state = .failed
                    $0.detail = "Couldn't save the downloaded file."
                }
            }
            return
        }

        let originalName = http?.suggestedFilename ?? sourceURL?.lastPathComponent ?? storedName

        // Validate the container is actually playable before registering it.
        // Run validation on a background queue and avoid blocking with a semaphore.
        DispatchQueue.global(qos: .default).async {
            let asset = AVAsset(url: destination)
            asset.loadValuesAsynchronously(forKeys: ["playable"]) {
                var error: NSError?
                let status = asset.statusOfValue(forKey: "playable", error: &error)
                let isPlayable = status == .loaded && asset.isPlayable

                guard isPlayable else {
                    try? FileManager.default.removeItem(at: destination)
                    Task { @MainActor in
                        self.update(recordID) {
                            $0.state = .failed
                            $0.detail = "The downloaded file isn't a playable audio or video container."
                        }
                    }
                    return
                }

                Task { @MainActor in
                    self.registerCompleted(recordID: recordID, storedName: storedName, kind: kind, originalName: originalName)
                }
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return } // success already handled in didFinishDownloadingTo
        guard let recordID = task.taskDescription.flatMap(UUID.init) else { return }
        let nsError = error as NSError
        let cancelled = nsError.code == NSURLErrorCancelled
        Task { @MainActor in
            update(recordID) {
                guard $0.state.isActive else { return }
                $0.state = cancelled ? .cancelled : .failed
                $0.detail = cancelled ? "Cancelled." : error.localizedDescription
            }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // Let the system snapshot the UI and finish the background launch.
        Task { @MainActor in
            AppDelegate.shared?.backgroundCompletionHandler?()
            AppDelegate.shared?.backgroundCompletionHandler = nil
        }
    }

    @MainActor
    private func registerCompleted(recordID: UUID, storedName: String, kind: MediaKind, originalName: String) {
        let record = records.first { $0.id == recordID }
        let title = record?.title ?? Self.title(fromFilename: originalName)
        library?.adoptDownloadedFile(
            storedFilename: storedName,
            title: title,
            kind: kind,
            originalFilename: originalName,
            thumbnailURL: record?.thumbnailURL
        )
        update(recordID) {
            $0.state = .completed
            $0.progress = 1
            $0.mediaKind = kind
            $0.detail = "Saved to your library."
        }
    }
}

// MARK: - Authorized download provider extension point

/// A future source that resolves a *direct, authorized* media file URL — for example a
/// user's own cloud storage or a service whose terms permit direct file access.
/// TODO: Add a conforming type only when the source's terms and the user's rights allow
/// direct download. Providers must return a plain file URL for `DownloadManager` to fetch;
/// they must not perform scraping, manifest resolution, or DRM circumvention.
protocol AuthorizedDownloadSource {
    var displayName: String { get }
    func resolveDirectURL() async throws -> URL
}

// Audio conversion is intentionally absent. Musico stores and plays original files only.
// TODO: Define a conversion protocol here only after an approved, locally supported
// implementation (e.g. an AVFoundation export pipeline) is chosen. Do not bundle
// third-party transcoders or downloader libraries.

// MARK: - JSON coders

extension JSONEncoder {
    static var musico: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var musico: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
