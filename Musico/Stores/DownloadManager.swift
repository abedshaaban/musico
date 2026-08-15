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
    private var progressPersistenceTask: Task<Void, Never>?
    private var preferredTransport: DownloadTransport = .background
    private static let sandboxTransportPreferenceKey = "Musico.prefersSandboxCompatibleDownloads"

    static var sessionIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "com.abedshaaban.Musico") + ".downloads"
    }
    private nonisolated let postProcessingGate = BackgroundPostProcessingGate()

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// Troll-style sandboxed installers may not grant access to the system background
    /// session's staging container. This in-process session stages downloads inside the
    /// app's own sandbox, at the cost of requiring the app to remain open.
    private lazy var inAppSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // Hosts that serve protected streams behind manifests / DRM / terms that forbid
    // direct file download. Reachability of a raw media URL on these is not expected;
    // refusing early keeps Musico strictly a personal-file player.
    // YouTube is excluded here because it has a dedicated resolver.
    private static let blockedHostFragments = [
        "soundcloud.", "vimeo.", "tiktok.", "instagram.", "facebook.", "fbcdn.",
        "dailymotion.", "netflix.", "twitch.", "hulu.", "disneyplus.", "primevideo."
    ]

    init(library: LibraryStore) {
        self.library = library
        super.init()
        loadRecords()
        preferredTransport = DownloadTransport.preferredTransport(
            savedPreference: UserDefaults.standard.bool(forKey: Self.sandboxTransportPreferenceKey),
            records: records
        )
        if preferredTransport == .inApp {
            UserDefaults.standard.set(true, forKey: Self.sandboxTransportPreferenceKey)
        }
        // Instantiate the background session so any tasks that completed while the app
        // was suspended deliver their delegate callbacks and get registered.
        _ = session
        reconcilePersistedRecordsWithBackgroundTasks()
    }

    // MARK: - Public actions

    /// Validate a user-supplied URL, then queue a background download if it checks out.
    func addFromURL(_ rawInput: String) async {
        await addFromURL(rawInput, transport: preferredTransport)
    }

    private func addFromURL(_ rawInput: String, transport: DownloadTransport) async {
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
            await addYouTubeVideo(id: videoID, sourceURL: url, transport: transport)
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
                $0.detail = transport.progressDetail(for: resolved.kind)
            }
            startTask(for: record.id, url: url, transport: transport)
        }
    }

    private func addYouTubeVideo(
        id videoID: String,
        sourceURL: URL,
        transport: DownloadTransport
    ) async {
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
                $0.detail = transport.progressDetail(for: resolved.kind)
            }
            startTask(for: record.id, url: resolved.url, transport: transport)
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
        let transport = DownloadTransport.retryTransport(after: record.detail)
        remove(record)
        Task { await addFromURL(raw, transport: transport) }
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
    private nonisolated static let verboseLogging = true

    private nonisolated static func debugLog(_ message: String) {
        guard verboseLogging else { return }
        print(message)
    }

    private func inspect(_ url: URL, method: String, rangeFirstByte: Bool = false) async -> InspectResult {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if rangeFirstByte { request.setValue("bytes=0-0", forHTTPHeaderField: "Range") }

        do {
            let http = try await HeaderOnlyProbe.response(for: request)
            if !(200..<400).contains(http.statusCode) {
                Self.debugLog("inspect: status code \(http.statusCode) for \(url.absoluteString)")
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
        } catch {
            Self.debugLog("inspect: error \(error) for \(url.absoluteString)")
            return .unreachable
        }
    }


    // MARK: - Downloading

    private func startTask(
        for recordID: UUID,
        url: URL,
        transport: DownloadTransport
    ) {
        let task = transport == .background
            ? session.downloadTask(with: url)
            : inAppSession.downloadTask(with: url)
        task.taskDescription = recordID.uuidString
        task.resume()
    }

    private func findTask(for recordID: UUID, _ body: @escaping (URLSessionTask?) -> Void) {
        let inAppSession = inAppSession
        session.getAllTasks { tasks in
            let match = tasks.first { $0.taskDescription == recordID.uuidString }
            guard match == nil else {
                body(match)
                return
            }
            inAppSession.getAllTasks { inAppTasks in
                body(inAppTasks.first { $0.taskDescription == recordID.uuidString })
            }
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

    private func update(
        _ recordID: UUID,
        persistImmediately: Bool = true,
        _ mutate: (inout DownloadRecord) -> Void
    ) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        mutate(&records[index])
        if persistImmediately {
            progressPersistenceTask?.cancel()
            progressPersistenceTask = nil
            persist()
        } else {
            scheduleProgressPersist()
        }
    }

    /// Progress delegates can fire many times per second. Keep the published model live,
    /// but coalesce atomic JSON writes so downloads do not churn storage and CPU.
    private func scheduleProgressPersist() {
        progressPersistenceTask?.cancel()
        progressPersistenceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                return
            }
            guard let self else { return }
            self.persist()
            self.progressPersistenceTask = nil
        }
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
        records = persisted.records
    }

    /// Background URLSession tasks survive system termination. Reconcile persisted UI
    /// state with the recreated session before deciding that an active record is stale.
    private func reconcilePersistedRecordsWithBackgroundTasks() {
        let persistedActiveIDs = Set(records.filter(\.state.isActive).map(\.id))
        session.getAllTasks { [weak self] tasks in
            let activeIDs = Set(tasks.compactMap { task in
                task.taskDescription.flatMap(UUID.init)
            })
            Task { @MainActor [weak self] in
                guard let self else { return }
                var changed = false
                for index in records.indices
                where persistedActiveIDs.contains(records[index].id) && records[index].state.isActive {
                    if activeIDs.contains(records[index].id) {
                        if records[index].state != .downloading {
                            records[index].state = .downloading
                            records[index].detail = nil
                            changed = true
                        }
                    } else {
                        records[index].state = .failed
                        records[index].detail = "Interrupted. Tap to retry."
                        changed = true
                    }
                }
                if changed { persist() }
            }
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
            update(recordID, persistImmediately: false) {
                $0.receivedBytes = totalBytesWritten
                if expected > 0 { $0.totalBytes = expected }
                if $0.totalBytes > 0 {
                    $0.progress = min(Double(totalBytesWritten) / Double($0.totalBytes), 1)
                }
                if $0.state == .downloading,
                   $0.detail?.contains(DownloadTransport.keepOpenMarker) != true {
                    $0.detail = nil
                }
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
        postProcessingGate.begin()

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

        do {
            try AppPaths.createDirectories()
            let saveResult = try DownloadedFileStore.saveTemporaryFile(
                at: location,
                to: destination
            )
            if let moveFailure = saveResult.recoveredMoveFailure {
                Self.debugLog("download save: move failed; copy fallback succeeded: \(moveFailure)")
            }
        } catch {
            let failure = DownloadedFileStore.failureDescription(for: error)
            let isBackgroundTransport = session.configuration.identifier != nil
            let transport = !isBackgroundTransport
                ? "In-app sandbox-compatible session"
                : "Background URLSession (\(session.configuration.identifier ?? "unknown"))"
            let diagnostic = "Transport: \(transport)\n\(failure.diagnostic)"
            let needsSandboxFallback = isBackgroundTransport
                && DownloadTransport.isSandboxPermissionFailure(failure.userMessage)
            Self.debugLog("download save failed: \(diagnostic)")
            Task { @MainActor in
                if needsSandboxFallback {
                    preferredTransport = .inApp
                    UserDefaults.standard.set(true, forKey: Self.sandboxTransportPreferenceKey)
                }
                update(recordID) {
                    $0.state = .failed
                    $0.detail = needsSandboxFallback
                        ? "iOS blocked Musico from reading the background download file. Tap Retry to use sandbox-compatible mode."
                        : failure.userMessage
                    $0.diagnostic = diagnostic
                }
                finishPostProcessing()
            }
            return
        }

        let originalName = http?.suggestedFilename ?? sourceURL?.lastPathComponent ?? storedName

        // Keep the system's background completion handler gated until local validation
        // and durable library registration have both finished.
        Task { @MainActor in
            guard await MediaMetadataExtractor.isPlayable(destination) else {
                try? FileManager.default.removeItem(at: destination)
                update(recordID) {
                    $0.state = .failed
                    $0.detail = "The downloaded file isn't a playable audio or video container."
                    $0.diagnostic = "Stage: AVFoundation media validation\nFile: \(destination.path)\nThe completed download could not be opened as a playable media asset."
                }
                finishPostProcessing()
                return
            }
            await registerCompleted(
                recordID: recordID,
                storedName: storedName,
                kind: kind,
                originalName: originalName
            )
            finishPostProcessing()
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
        let transport = session.configuration.identifier == nil
            ? "In-app sandbox-compatible session"
            : "Background URLSession (\(session.configuration.identifier ?? "unknown"))"
        let diagnostic = DownloadDiagnostics.report(
            stage: "URLSession task completion",
            error: nsError,
            transport: transport,
            sourceURL: task.originalRequest?.url,
            taskIdentifier: task.taskIdentifier
        )
        Task { @MainActor in
            update(recordID) {
                guard $0.state.isActive else { return }
                $0.state = cancelled ? .cancelled : .failed
                $0.detail = cancelled ? "Cancelled." : error.localizedDescription
                if !cancelled { $0.diagnostic = diagnostic }
            }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        if postProcessingGate.markSystemEventsFinished() {
            Task { @MainActor in finishBackgroundEvents() }
        }
    }

    @MainActor
    private func registerCompleted(
        recordID: UUID,
        storedName: String,
        kind: MediaKind,
        originalName: String
    ) async {
        let record = records.first { $0.id == recordID }
        let title = record?.title ?? Self.title(fromFilename: originalName)
        guard let library else {
            update(recordID) {
                $0.state = .failed
                $0.detail = "The downloaded file couldn't be registered in the library."
                $0.diagnostic = "Stage: Library registration\nFile: \(storedName)\nThe LibraryStore reference was unavailable."
            }
            return
        }
        await library.adoptDownloadedFile(
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

    @MainActor
    private func finishPostProcessing() {
        if postProcessingGate.finishOne() {
            finishBackgroundEvents()
        }
    }

    @MainActor
    private func finishBackgroundEvents() {
        guard let completion = AppDelegate.shared?.backgroundCompletionHandler else { return }
        AppDelegate.shared?.backgroundCompletionHandler = nil
        completion()
    }
}

// MARK: - Downloaded file storage

/// Moves a URLSession temporary download into durable app storage. Some iOS versions
/// can reject a rename from the background-session staging area even though both URLs
/// are accessible, so a synchronous filesystem copy is used as a safe fallback before
/// the delegate returns and iOS removes the temporary file.
enum DownloadedFileStore {
    struct SaveResult {
        var recoveredMoveFailure: String?
    }

    struct SaveFailure: LocalizedError {
        let stage: String
        let errors: [NSError]
        let source: URL
        let destination: URL

        var diagnostic: String {
            let details = errors.enumerated().map { index, error in
                "Error \(index + 1): \(DownloadDiagnostics.describe(error))"
            }
            return ([
                "Stage: \(stage)",
                "Source: \(source.path)",
                "Destination: \(destination.path)"
            ] + details).joined(separator: "\n")
        }

        var errorDescription: String? { diagnostic }
    }

    static func saveTemporaryFile(
        at source: URL,
        to destination: URL,
        fileManager: FileManager = .default,
        moveItem: ((URL, URL) throws -> Void)? = nil
    ) throws -> SaveResult {
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw SaveFailure(
                stage: "Create media directory",
                errors: [error as NSError],
                source: source,
                destination: destination
            )
        }

        do {
            if let moveItem {
                try moveItem(source, destination)
            } else {
                try fileManager.moveItem(at: source, to: destination)
            }
            return SaveResult(recoveredMoveFailure: nil)
        } catch {
            let moveError = error as NSError
            do {
                try fileManager.copyItem(at: source, to: destination)
                try? fileManager.removeItem(at: source)
                return SaveResult(
                    recoveredMoveFailure: "\(moveError.domain) \(moveError.code): \(moveError.localizedDescription)"
                )
            } catch {
                let copyError = error as NSError
                // `copyItem` can leave a partial destination behind on failure. This
                // destination is UUID-named and belongs only to this callback.
                try? fileManager.removeItem(at: destination)
                throw SaveFailure(
                    stage: "Move and copy downloaded file",
                    errors: [moveError, copyError],
                    source: source,
                    destination: destination
                )
            }
        }
    }

    static func failureDescription(for error: Error) -> (userMessage: String, diagnostic: String) {
        let failure = error as? SaveFailure
        let errors = failure?.errors ?? [error as NSError]
        let diagnostic = failure?.diagnostic
            ?? "Save downloaded file: \((error as NSError).domain) \((error as NSError).code): \(error.localizedDescription)"

        if errors.contains(where: isOutOfSpace) {
            return (
                "Couldn't save the downloaded file because this iPhone is out of storage. Free some space, then retry.",
                diagnostic
            )
        }
        if errors.contains(where: isPermissionFailure) {
            let primary = errors.last ?? (error as NSError)
            return (
                "Couldn't save the downloaded file because iOS denied access to Musico's storage (\(primary.domain) \(primary.code)). Retry to use sandbox-compatible mode.",
                diagnostic
            )
        }
        if errors.contains(where: isMissingFile) {
            return (
                "Couldn't save the downloaded file because iOS removed its temporary copy before Musico could preserve it. Please retry.",
                diagnostic
            )
        }

        let primary = errors.last ?? (error as NSError)
        return (
            "Couldn't save the downloaded file. iOS reported: \(primary.localizedDescription) (\(primary.domain) \(primary.code)).",
            diagnostic
        )
    }

    private static func isOutOfSpace(_ error: NSError) -> Bool {
        (error.domain == NSCocoaErrorDomain
            && error.code == CocoaError.Code.fileWriteOutOfSpace.rawValue)
            || (error.domain == NSPOSIXErrorDomain && error.code == 28)
    }

    private static func isPermissionFailure(_ error: NSError) -> Bool {
        let cocoaCodes = [
            CocoaError.Code.fileReadNoPermission.rawValue,
            CocoaError.Code.fileWriteNoPermission.rawValue
        ]
        return (error.domain == NSCocoaErrorDomain && cocoaCodes.contains(error.code))
            || (error.domain == NSPOSIXErrorDomain && [1, 13].contains(error.code))
    }

    private static func isMissingFile(_ error: NSError) -> Bool {
        (error.domain == NSCocoaErrorDomain
            && error.code == CocoaError.Code.fileReadNoSuchFile.rawValue)
            || (error.domain == NSPOSIXErrorDomain && error.code == 2)
    }
}

enum DownloadTransport: Equatable {
    case background
    case inApp

    static let keepOpenMarker = "Keep Musico open"
    private static let legacyPermissionMarker = "iOS denied access to Musico's storage"
    private static let sandboxFallbackMarker = "sandbox-compatible mode"

    static func retryTransport(after detail: String?) -> DownloadTransport {
        guard let detail else { return .background }
        return isSandboxPermissionFailure(detail)
            ? .inApp
            : .background
    }

    static func preferredTransport(
        savedPreference: Bool,
        records: [DownloadRecord]
    ) -> DownloadTransport {
        if savedPreference || records.contains(where: { retryTransport(after: $0.detail) == .inApp }) {
            return .inApp
        }
        return .background
    }

    static func isSandboxPermissionFailure(_ detail: String) -> Bool {
        detail.contains(legacyPermissionMarker) || detail.contains(sandboxFallbackMarker)
    }

    func progressDetail(for kind: MediaKind) -> String {
        switch self {
        case .background:
            return "Downloading \(kind.label.lowercased())…"
        case .inApp:
            return "\(Self.keepOpenMarker) while the sandbox-compatible download finishes."
        }
    }
}

enum DownloadDiagnostics {
    static func report(
        stage: String,
        error: NSError,
        transport: String,
        sourceURL: URL?,
        taskIdentifier: Int
    ) -> String {
        [
            "Stage: \(stage)",
            "Transport: \(transport)",
            "Task identifier: \(taskIdentifier)",
            "Source URL: \(sourceURL?.absoluteString ?? "Unavailable")",
            "Error: \(describe(error))"
        ].joined(separator: "\n")
    }

    static func describe(_ error: NSError) -> String {
        var result = "\(error.domain) \(error.code): \(error.localizedDescription)"
        if let path = error.userInfo[NSFilePathErrorKey] as? String {
            result += " [path: \(path)]"
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            result += " [underlying: \(describe(underlying))]"
        }
        return result
    }
}

// MARK: - Background coordination

/// Thread-safe gate that delays the UIKit background-session completion callback until
/// all asynchronous local post-processing initiated by delegate callbacks has finished.
final class BackgroundPostProcessingGate: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingCount = 0
    private var systemEventsFinished = false

    func begin() {
        lock.lock()
        pendingCount += 1
        lock.unlock()
    }

    func markSystemEventsFinished() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if pendingCount == 0 {
            systemEventsFinished = false
            return true
        }
        systemEventsFinished = true
        return false
    }

    func finishOne() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard pendingCount > 0 else { return false }
        pendingCount -= 1
        guard pendingCount == 0, systemEventsFinished else { return false }
        systemEventsFinished = false
        return true
    }
}

/// Performs a request only through response headers. The task is cancelled before body
/// delivery, so a server that ignores a one-byte Range request cannot fill app memory.
enum HeaderOnlyProbe {
    static func response(
        for request: URLRequest,
        protocolClasses: [AnyClass]? = nil
    ) async throws -> HTTPURLResponse {
        try await withCheckedThrowingContinuation { continuation in
            let probe = HeaderProbeRequest(
                continuation: continuation,
                protocolClasses: protocolClasses
            )
            probe.start(request)
        }
    }
}

private final class HeaderProbeRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HTTPURLResponse, Error>?
    private var session: URLSession?
    private let protocolClasses: [AnyClass]?

    init(
        continuation: CheckedContinuation<HTTPURLResponse, Error>,
        protocolClasses: [AnyClass]?
    ) {
        self.continuation = continuation
        self.protocolClasses = protocolClasses
    }

    func start(_ request: URLRequest) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        session.dataTask(with: request).resume()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        completionHandler(.cancel)
        guard let http = response as? HTTPURLResponse else {
            finish(.failure(URLError(.badServerResponse)))
            return
        }
        finish(.success(http))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        finish(.failure(error ?? URLError(.badServerResponse)))
    }

    private func finish(_ result: Result<HTTPURLResponse, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let session = self.session
        self.session = nil
        lock.unlock()

        continuation.resume(with: result)
        session?.invalidateAndCancel()
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
