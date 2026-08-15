import Foundation
import XCTest
@testable import Musico

final class CompatibilityTests: XCTestCase {
    func testAppDeclaresBackgroundAudioMode() {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        XCTAssertTrue(modes?.contains("audio") == true)
    }

    func testSupportedMediaAcceptsIPhoneCompatibleContainers() {
        XCTAssertEqual(SupportedMedia.kind(forMIME: "audio/mpeg"), .audio)
        XCTAssertEqual(SupportedMedia.kind(forMIME: "video/mp4; codecs=avc1"), .video)
        XCTAssertEqual(SupportedMedia.kind(forExtension: "M4A"), .audio)
        XCTAssertEqual(SupportedMedia.kind(forExtension: "MOV"), .video)
    }

    func testUnsupportedWebAndFlashContainersAreRejected() {
        XCTAssertNil(SupportedMedia.kind(forMIME: "video/webm"))
        XCTAssertNil(SupportedMedia.kind(forMIME: "audio/webm"))
        XCTAssertNil(SupportedMedia.kind(forMIME: "video/x-flv"))
        XCTAssertNil(SupportedMedia.kind(forExtension: "webm"))
        XCTAssertNil(SupportedMedia.kind(forExtension: "flv"))
    }

    func testAVFoundationRejectsMislabeledMediaBeforeImport() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        try Data("not a media container".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let playable = await MediaMetadataExtractor.isPlayable(url)
        XCTAssertFalse(playable)
    }

    func testHeaderProbeReturnsBeforeResponseBody() async throws {
        let request = URLRequest(url: URL(string: "musico-test://large-file/video.mp4")!)
        let startedAt = Date()
        let response = try await HeaderOnlyProbe.response(
            for: request,
            protocolClasses: [DelayedBodyURLProtocol.self]
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.mimeType, "video/mp4")
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1)
    }

    @MainActor
    func testYouTubeVideoIDParsing() {
        XCTAssertEqual(
            YouTubeResolver.videoID(from: URL(string: "https://youtu.be/aqz-KE-bpKQ")!),
            "aqz-KE-bpKQ"
        )
        XCTAssertEqual(
            YouTubeResolver.videoID(from: URL(string: "https://www.youtube.com/watch?v=aqz-KE-bpKQ")!),
            "aqz-KE-bpKQ"
        )
        XCTAssertNil(
            YouTubeResolver.videoID(from: URL(string: "https://www.youtube.com/watch?v=short")!)
        )
    }

    @MainActor
    func testYouTubePlaylistIDParsingFromPlaylistAndWatchLinks() {
        XCTAssertEqual(
            YouTubeResolver.playlistID(
                from: URL(string: "https://www.youtube.com/playlist?list=PL1234567890abc")!
            ),
            "PL1234567890abc"
        )
        XCTAssertEqual(
            YouTubeResolver.playlistID(
                from: URL(string: "https://www.youtube.com/watch?v=aqz-KE-bpKQ&list=PL1234567890abc")!
            ),
            "PL1234567890abc"
        )
        XCTAssertNil(
            YouTubeResolver.playlistID(
                from: URL(string: "https://example.com/playlist?list=PL1234567890abc")!
            )
        )
    }

    @MainActor
    func testYouTubePlaylistPageParsesEditableMetadataAndContinuation() throws {
        let html = #"""
        <script>
        var ytInitialData = {
          "metadata":{"playlistMetadataRenderer":{"title":"Night Mix"}},
          "contents":{
            "playlistVideoRenderer":{
              "videoId":"aqz-KE-bpKQ",
              "title":{"runs":[{"text":"Massive Attack – Teardrop"}]},
              "thumbnail":{"thumbnails":[
                {"url":"https://example.com/small.jpg","width":120},
                {"url":"https://example.com/large.jpg","width":640}
              ]}
            },
            "continuationItemRenderer":{
              "continuationEndpoint":{"continuationCommand":{"token":"NEXT_PAGE"}}
            }
          }
        };
        ytcfg.set({"INNERTUBE_API_KEY":"test-key","INNERTUBE_CLIENT_VERSION":"2.test"});
        </script>
        """#

        let page = try YouTubeResolver.playlistPage(
            fromHTML: html,
            playlistID: "PL1234567890abc"
        )

        XCTAssertEqual(page.title, "Night Mix")
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.videoID, "aqz-KE-bpKQ")
        XCTAssertEqual(page.items.first?.artist, "Massive Attack")
        XCTAssertEqual(page.items.first?.thumbnailURL?.absoluteString, "https://example.com/large.jpg")
        XCTAssertEqual(page.continuation, "NEXT_PAGE")
        XCTAssertEqual(page.apiKey, "test-key")
        XCTAssertEqual(page.clientVersion, "2.test")
    }

    @MainActor
    func testYouTubePlaylistPageParsesCurrentLockupViewModel() throws {
        let html = #"""
        <script>
        var ytInitialData = {
          "metadata":{"playlistMetadataRenderer":{"title":"Live Songs"}},
          "contents":{"lockupViewModel":{
            "contentId":"PXC_PYeB6F8",
            "contentType":"LOCKUP_CONTENT_TYPE_VIDEO",
            "contentImage":{"thumbnailViewModel":{"image":{"sources":[
              {"url":"https://example.com/168.jpg","width":168},
              {"url":"https://example.com/336.jpg","width":336}
            ]}}},
            "metadata":{"lockupMetadataViewModel":{
              "title":{"content":"Rick Astley - Angels On My Side"}
            }}
          }}
        };
        ytcfg.set({"INNERTUBE_API_KEY":"test-key","INNERTUBE_CLIENT_VERSION":"2.test"});
        </script>
        """#

        let page = try YouTubeResolver.playlistPage(
            fromHTML: html,
            playlistID: "PL1234567890abc"
        )

        XCTAssertEqual(page.items.first?.videoID, "PXC_PYeB6F8")
        XCTAssertEqual(page.items.first?.title, "Rick Astley - Angels On My Side")
        XCTAssertEqual(page.items.first?.artist, "Rick Astley")
        XCTAssertEqual(page.items.first?.thumbnailURL?.absoluteString, "https://example.com/336.jpg")
    }

    func testLegacyDownloadRecordsDecodeWithoutBulkImportFields() throws {
        let id = UUID()
        let json = """
        {
          "id":"\(id.uuidString)",
          "title":"Teardrop",
          "sourceName":"YouTube",
          "state":"completed",
          "progress":1,
          "createdAt":0,
          "receivedBytes":100,
          "totalBytes":100
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let record = try decoder.decode(DownloadRecord.self, from: Data(json.utf8))

        XCTAssertNil(record.targetPlaylistID)
        XCTAssertNil(record.targetPlaylistPosition)
    }

    func testBulkImportFieldsSurviveDownloadRecordRoundTrip() throws {
        let playlistID = UUID()
        let record = DownloadRecord(
            title: "Teardrop",
            sourceName: "YouTube",
            state: .queued,
            targetPlaylistID: playlistID,
            targetPlaylistPosition: 4
        )

        let data = try JSONEncoder.musico.encode(record)
        let restored = try JSONDecoder.musico.decode(DownloadRecord.self, from: data)

        XCTAssertEqual(restored.targetPlaylistID, playlistID)
        XCTAssertEqual(restored.targetPlaylistPosition, 4)
    }

    @MainActor
    func testYouTubeArtistIsReadFromDescriptionStreamLine() {
        let description = """
        • Stream tame impala - loser (lyrics)

        • Check out our Lo-Fi Friends
        """

        XCTAssertEqual(
            YouTubeResolver.inferredArtist(
                title: "tame impala - loser (lyrics)",
                description: description
            ),
            "tame impala"
        )
    }

    @MainActor
    func testYouTubeExplicitDescriptionArtistTakesPriority() {
        XCTAssertEqual(
            YouTubeResolver.inferredArtist(
                title: "Uploader - Ambiguous title",
                description: "Artist: The Smile\nListen now"
            ),
            "The Smile"
        )
    }

    @MainActor
    func testYouTubeArtistFallsBackToTitlePattern() {
        XCTAssertEqual(
            YouTubeResolver.inferredArtist(
                title: "Massive Attack – Teardrop (Official Video)",
                description: "Follow us - Spotify\nOfficial music video"
            ),
            "Massive Attack"
        )
    }

    @MainActor
    func testBackgroundSessionIdentifierTracksInstalledBundleIdentifier() {
        XCTAssertEqual(
            DownloadManager.sessionIdentifier,
            (Bundle.main.bundleIdentifier ?? "com.abedshaaban.Musico") + ".downloads"
        )
    }

    func testBackgroundGateWaitsForAllPostProcessing() {
        let gate = BackgroundPostProcessingGate()
        gate.begin()
        gate.begin()

        XCTAssertFalse(gate.markSystemEventsFinished())
        XCTAssertFalse(gate.finishOne())
        XCTAssertTrue(gate.finishOne())
    }

    func testBackgroundGateCompletesImmediatelyWithoutPostProcessing() {
        let gate = BackgroundPostProcessingGate()
        XCTAssertTrue(gate.markSystemEventsFinished())
    }

    func testBackgroundGateResetsBetweenEventBatches() {
        let gate = BackgroundPostProcessingGate()
        gate.begin()
        XCTAssertFalse(gate.markSystemEventsFinished())
        XCTAssertTrue(gate.finishOne())

        gate.begin()
        XCTAssertFalse(gate.finishOne())
        XCTAssertTrue(gate.markSystemEventsFinished())
    }

    func testDownloadedFileStoreCreatesDirectoryAndPreservesFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("download.tmp")
        let destination = root
            .appendingPathComponent("Library/Application Support/Musico/Media", isDirectory: true)
            .appendingPathComponent("saved.mp4")
        let expected = Data("downloaded media bytes".utf8)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try expected.write(to: source)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try DownloadedFileStore.saveTemporaryFile(at: source, to: destination)

        XCTAssertNil(result.recoveredMoveFailure)
        XCTAssertEqual(try Data(contentsOf: destination), expected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testDownloadedFileStoreReportsTheUnderlyingIOError() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let missingSource = root.appendingPathComponent("missing.tmp")
        let destination = root.appendingPathComponent("Media/saved.mp4")
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(
            try DownloadedFileStore.saveTemporaryFile(at: missingSource, to: destination)
        ) { error in
            let description = DownloadedFileStore.failureDescription(for: error)
            XCTAssertTrue(description.userMessage.contains("temporary copy"))
            XCTAssertTrue(description.diagnostic.contains("Move and copy downloaded file"))
            XCTAssertTrue(description.diagnostic.contains(NSCocoaErrorDomain))
            XCTAssertTrue(description.diagnostic.contains(missingSource.path))
            XCTAssertTrue(description.diagnostic.contains(destination.path))
            XCTAssertTrue(description.diagnostic.contains("Error 1:"))
            XCTAssertTrue(description.diagnostic.contains("Error 2:"))
        }
    }

    func testDownloadedFileStoreCopiesWhenSandboxDeniesMove() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("background-session.tmp")
        let destination = root.appendingPathComponent("Media/saved.mp4")
        let expected = Data("sandboxed download".utf8)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try expected.write(to: source)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try DownloadedFileStore.saveTemporaryFile(
            at: source,
            to: destination,
            moveItem: { _, _ in
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: CocoaError.Code.fileWriteNoPermission.rawValue
                )
            }
        )

        XCTAssertNotNil(result.recoveredMoveFailure)
        XCTAssertEqual(try Data(contentsOf: destination), expected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testPermissionFailureRetriesWithInAppTransport() {
        XCTAssertEqual(
            DownloadTransport.retryTransport(
                after: "Couldn't save because iOS denied access to Musico's storage."
            ),
            .inApp
        )
        XCTAssertEqual(
            DownloadTransport.retryTransport(after: "The connection was interrupted."),
            .background
        )
        XCTAssertEqual(
            DownloadTransport.retryTransport(
                after: "iOS blocked the background file. Tap Retry to use sandbox-compatible mode."
            ),
            .inApp
        )
        XCTAssertTrue(
            DownloadTransport.inApp.progressDetail(for: .video)
                .contains(DownloadTransport.keepOpenMarker)
        )
    }

    func testUnknownBackgroundYouTubeFailureRetriesInApp() {
        XCTAssertTrue(
            DownloadManager.shouldRetryYouTubeInApp(
                sourceName: "YouTube",
                receivedBytes: 0,
                error: NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown),
                isBackgroundTransport: true
            )
        )
        XCTAssertFalse(
            DownloadManager.shouldRetryYouTubeInApp(
                sourceName: "YouTube",
                receivedBytes: 0,
                error: NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown),
                isBackgroundTransport: false
            )
        )
        XCTAssertFalse(
            DownloadManager.shouldRetryYouTubeInApp(
                sourceName: "example.com",
                receivedBytes: 0,
                error: NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown),
                isBackgroundTransport: true
            )
        )
    }

    @MainActor
    func testRecordedUnknownYouTubeFailureUsesInAppRetry() {
        let record = DownloadRecord(
            title: "Loser",
            artist: "Tame Impala",
            sourceName: "YouTube",
            state: .failed,
            detail: "unknown error",
            diagnostic: "Error: NSURLErrorDomain -1: unknown error"
        )

        XCTAssertTrue(DownloadManager.shouldUseInAppForRetry(record))
    }

    func testExistingPermissionFailureMakesFutureDownloadsSandboxCompatible() {
        let failed = DownloadRecord(
            title: "Failed download",
            sourceName: "YouTube",
            state: .failed,
            detail: "Couldn't save because iOS denied access to Musico's storage."
        )

        XCTAssertEqual(
            DownloadTransport.preferredTransport(savedPreference: false, records: [failed]),
            .inApp
        )
        XCTAssertEqual(
            DownloadTransport.preferredTransport(savedPreference: true, records: []),
            .inApp
        )
        XCTAssertEqual(
            DownloadTransport.preferredTransport(savedPreference: false, records: []),
            .background
        )
    }

    func testDownloadRecordDecodesFailuresFromBeforeDiagnosticsWereAdded() throws {
        struct LegacyDownloadRecord: Encodable {
            let id = UUID()
            let title = "Legacy failure"
            let sourceName = "example.com"
            let state = DownloadState.failed
            let progress = 1.0
            let createdAt = Date()
            let detail: String? = "Couldn't save."
            let remoteURL = URL(string: "https://example.com/media.mp4")
            let mediaKind = MediaKind.video
            let receivedBytes: Int64 = 100
            let totalBytes: Int64 = 100
            let thumbnailURL: URL? = nil
        }

        let data = try JSONEncoder().encode(LegacyDownloadRecord())
        let record = try JSONDecoder().decode(DownloadRecord.self, from: data)

        XCTAssertEqual(record.state, .failed)
        XCTAssertNil(record.diagnostic)
        XCTAssertNil(record.artist)
    }

    func testDownloadRecordPersistsConfirmedArtist() throws {
        let record = DownloadRecord(
            title: "Loser",
            artist: "Tame Impala",
            sourceName: "YouTube",
            state: .downloading
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(DownloadRecord.self, from: data)

        XCTAssertEqual(decoded.title, "Loser")
        XCTAssertEqual(decoded.artist, "Tame Impala")
    }

    func testLibraryItemDecodesDataSavedBeforeExtendedMetadata() throws {
        struct LegacyLibraryItem: Encodable {
            let id = UUID()
            let title = "Teardrop"
            let artist = "Massive Attack"
            let kind = MediaKind.audio
            let localFilename = "teardrop.m4a"
            let originalFilename = "Teardrop.m4a"
            let addedAt = Date()
            let artworkFilename: String? = nil
        }

        let data = try JSONEncoder().encode(LegacyLibraryItem())
        let item = try JSONDecoder().decode(LibraryItem.self, from: data)

        XCTAssertEqual(item.title, "Teardrop")
        XCTAssertNil(item.album)
        XCTAssertNil(item.genre)
        XCTAssertNil(item.year)
        XCTAssertNil(item.trackNumber)
    }

    func testMetadataTagParsingHandlesCommonFormats() {
        XCTAssertEqual(MediaMetadataExtractor.parseYear("2024-10-18T00:00:00Z"), 2024)
        XCTAssertEqual(MediaMetadataExtractor.parseYear("Released 1998"), 1998)
        XCTAssertNil(MediaMetadataExtractor.parseYear("unknown"))
        XCTAssertEqual(MediaMetadataExtractor.parseTrackNumber("03/12"), 3)
        XCTAssertEqual(MediaMetadataExtractor.parseTrackNumber("7"), 7)
        XCTAssertNil(MediaMetadataExtractor.parseTrackNumber("0/12"))
    }

    func testCollectionSummaryOmitsBlankMetadata() {
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let item = LibraryItem(
            id: UUID(),
            title: "Teardrop",
            artist: "Massive Attack",
            album: "Mezzanine",
            genre: "Trip Hop",
            year: 1998,
            kind: .audio,
            localFilename: "teardrop.m4a",
            originalFilename: "Teardrop.m4a",
            addedAt: savedAt,
            artworkFilename: nil
        )

        XCTAssertEqual(item.collectionSummary, "Mezzanine · 1998 · Trip Hop")
    }

    func testStorageCleanupOnlyOffersOldUnreferencedFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let media = root.appendingPathComponent("Media", isDirectory: true)
        let artwork = root.appendingPathComponent("Artwork", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: artwork, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let referencedMedia = media.appendingPathComponent("referenced.m4a")
        let referencedArtwork = artwork.appendingPathComponent("referenced.jpg")
        let oldOrphanMedia = media.appendingPathComponent("old-orphan.m4a")
        let oldOrphanArtwork = artwork.appendingPathComponent("old-orphan.jpg")
        let recentOrphan = media.appendingPathComponent("active-download.tmp")
        for url in [referencedMedia, referencedArtwork, oldOrphanMedia, oldOrphanArtwork, recentOrphan] {
            try Data(repeating: 1, count: 128).write(to: url)
        }

        let now = Date()
        let oldDate = now.addingTimeInterval(-LibraryStorageScanner.orphanGraceInterval - 60)
        for url in [referencedMedia, referencedArtwork, oldOrphanMedia, oldOrphanArtwork] {
            try FileManager.default.setAttributes(
                [.modificationDate: oldDate],
                ofItemAtPath: url.path
            )
        }

        let item = LibraryItem(
            id: UUID(),
            title: "Referenced",
            artist: "Artist",
            kind: .audio,
            localFilename: referencedMedia.lastPathComponent,
            originalFilename: "Referenced.m4a",
            addedAt: now,
            artworkFilename: referencedArtwork.lastPathComponent
        )
        let report = LibraryStorageScanner.scan(
            items: [item],
            mediaDirectory: media,
            artworkDirectory: artwork,
            metadataFiles: [],
            now: now
        )

        XCTAssertEqual(Set(report.orphanedFiles.map { $0.url.lastPathComponent }), [
            oldOrphanMedia.lastPathComponent,
            oldOrphanArtwork.lastPathComponent
        ])
        XCTAssertEqual(report.itemUsage.map(\.id), [item.id])

        let result = LibraryStorageScanner.removeOrphans(report.orphanedFiles)
        XCTAssertEqual(result.removedFiles, 2)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: referencedMedia.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: referencedArtwork.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentOrphan.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldOrphanMedia.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldOrphanArtwork.path))
    }

    func testMusicoBackupRoundTripPreservesLibraryMediaArtworkAndPreferences() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let media = root.appendingPathComponent("Source/Media", isDirectory: true)
        let artwork = root.appendingPathComponent("Source/Artwork", isDirectory: true)
        let temporary = root.appendingPathComponent("Temporary", isDirectory: true)
        let destination = root.appendingPathComponent("Destination/Musico", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: artwork, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let mediaData = Data("portable media bytes".utf8)
        let artworkData = Data("portable artwork bytes".utf8)
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try mediaData.write(to: media.appendingPathComponent("track.m4a"))
        try artworkData.write(to: artwork.appendingPathComponent("cover.jpg"))
        let item = LibraryItem(
            id: UUID(),
            title: "Teardrop",
            artist: "Massive Attack",
            album: "Mezzanine",
            genre: "Trip Hop",
            year: 1998,
            trackNumber: 3,
            kind: .audio,
            localFilename: "track.m4a",
            originalFilename: "Teardrop.m4a",
            addedAt: savedAt,
            artworkFilename: "cover.jpg"
        )
        let playlist = Playlist(
            id: UUID(),
            name: "Night",
            itemIDs: [item.id],
            createdAt: savedAt
        )
        let library = PersistedLibrary(
            items: [item],
            playlists: [playlist],
            recentlyPlayedIDs: [item.id],
            knownArtists: [item.artist]
        )

        let backup = try MusicoBackupService.create(
            library: library,
            mediaDirectory: media,
            artworkDirectory: artwork,
            preferences: ["nowPlayingVisualStyle": "cassette"],
            appVersion: "1.0",
            temporaryDirectory: temporary
        )
        let preview = try MusicoBackupService.inspect(backup.fileURL)

        XCTAssertEqual(preview.itemCount, 1)
        XCTAssertEqual(preview.mediaBytes, Int64(mediaData.count))
        XCTAssertEqual(backup.fileURL.pathExtension, "musicobackup")

        let downloadHistory = Data("existing download history".utf8)
        try downloadHistory.write(to: destination.appendingPathComponent("downloads.json"))
        let manifest = try MusicoBackupService.restore(
            backup.fileURL,
            applicationSupport: destination
        )

        let restoredData = try Data(contentsOf: destination.appendingPathComponent("library.json"))
        let restored = try JSONDecoder.musico.decode(PersistedLibrary.self, from: restoredData)
        XCTAssertEqual(restored.items, [item])
        XCTAssertEqual(restored.playlists, [playlist])
        XCTAssertEqual(restored.recentlyPlayedIDs, [item.id])
        XCTAssertEqual(
            try Data(contentsOf: destination.appendingPathComponent("Media/track.m4a")),
            mediaData
        )
        XCTAssertEqual(
            try Data(contentsOf: destination.appendingPathComponent("Artwork/cover.jpg")),
            artworkData
        )
        XCTAssertEqual(
            try Data(contentsOf: destination.appendingPathComponent("downloads.json")),
            downloadHistory
        )
        XCTAssertEqual(manifest.preferences["nowPlayingVisualStyle"], "cassette")
    }

    func testMusicoBackupRejectsTruncatedArchive() throws {
        let fixture = try makeBackupFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let size = try fixture.backup.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize!
        let handle = try FileHandle(forWritingTo: fixture.backup.fileURL)
        try handle.truncate(atOffset: UInt64(size - 1))
        try handle.close()

        XCTAssertThrowsError(try MusicoBackupService.inspect(fixture.backup.fileURL)) { error in
            XCTAssertTrue(error.localizedDescription.contains("incomplete"))
        }
    }

    func testMusicoBackupDetectsAlteredPayloadBeforeReplacingLibrary() throws {
        let fixture = try makeBackupFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let destination = fixture.root.appendingPathComponent("Existing/Musico", isDirectory: true)
        try FileManager.default.createDirectory(
            at: destination.appendingPathComponent("Media", isDirectory: true),
            withIntermediateDirectories: true
        )
        let existingLibrary = Data("existing library".utf8)
        try existingLibrary.write(to: destination.appendingPathComponent("library.json"))

        let size = try fixture.backup.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize!
        let handle = try FileHandle(forWritingTo: fixture.backup.fileURL)
        try handle.seek(toOffset: UInt64(size - 1))
        try handle.write(contentsOf: Data([0xFF]))
        try handle.close()

        XCTAssertThrowsError(
            try MusicoBackupService.restore(
                fixture.backup.fileURL,
                applicationSupport: destination
            )
        )
        XCTAssertEqual(
            try Data(contentsOf: destination.appendingPathComponent("library.json")),
            existingLibrary
        )
    }

    func testMusicoBackupRejectsUnsafeLibraryFilename() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let item = LibraryItem(
            id: UUID(),
            title: "Unsafe",
            artist: "Artist",
            kind: .audio,
            localFilename: "../outside.m4a",
            originalFilename: "outside.m4a",
            addedAt: Date(),
            artworkFilename: nil
        )
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(
            try MusicoBackupService.create(
                library: PersistedLibrary(items: [item], playlists: []),
                mediaDirectory: root,
                artworkDirectory: root,
                preferences: [:],
                appVersion: "1.0",
                temporaryDirectory: root
            )
        )
    }

    @MainActor
    func testConfirmedDownloadMetadataOverridesEmbeddedTags() {
        XCTAssertEqual(
            LibraryStore.downloadedTitle(
                confirmed: "Loser",
                embedded: "tame impala - loser (lyrics)"
            ),
            "Loser"
        )
        XCTAssertEqual(
            LibraryStore.downloadedArtist(
                confirmed: "Tame Impala",
                embedded: "Lyrical Tunes"
            ),
            "Tame Impala"
        )
    }

    @MainActor
    func testBlankConfirmedArtistUsesAvailableFallback() {
        XCTAssertEqual(
            LibraryStore.downloadedArtist(confirmed: "", embedded: "Massive Attack"),
            "Massive Attack"
        )
        XCTAssertEqual(
            LibraryStore.downloadedArtist(confirmed: nil, embedded: nil),
            "Unknown Artist"
        )
    }

    func testDownloadDiagnosticsIncludesUnderlyingErrorAndPath() {
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: 13)
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.Code.fileReadNoPermission.rawValue,
            userInfo: [
                NSFilePathErrorKey: "/private/var/mobile/staged-download.tmp",
                NSUnderlyingErrorKey: underlying
            ]
        )

        let report = DownloadDiagnostics.report(
            stage: "Saving",
            error: error,
            transport: "In-app sandbox-compatible session",
            sourceURL: URL(string: "https://example.com/media.mp4"),
            taskIdentifier: 7
        )

        XCTAssertTrue(report.contains("Saving"))
        XCTAssertTrue(report.contains("In-app sandbox-compatible session"))
        XCTAssertTrue(report.contains("/private/var/mobile/staged-download.tmp"))
        XCTAssertTrue(report.contains("NSPOSIXErrorDomain 13"))
    }

    func testNowPlayingLayoutCompactsForIPhone7Height() {
        let layout = NowPlayingLayoutMetrics(width: 375, height: 570)

        XCTAssertTrue(layout.isCompact)
        XCTAssertLessThanOrEqual(layout.artworkWidth, 250)
        XCTAssertEqual(layout.videoWidth, 359)
        XCTAssertEqual(layout.sectionSpacing, 10)
        XCTAssertEqual(layout.playButtonSize, 50)
    }

    func testNowPlayingLayoutKeepsLargeScreenPresentation() {
        let layout = NowPlayingLayoutMetrics(width: 393, height: 760)

        XCTAssertFalse(layout.isCompact)
        XCTAssertEqual(layout.artworkWidth, 353)
        XCTAssertEqual(layout.videoWidth, 369)
        XCTAssertEqual(layout.sectionSpacing, 20)
        XCTAssertEqual(layout.playButtonSize, 58)
    }

    private func makeBackupFixture() throws -> (root: URL, backup: CreatedMusicoBackup) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let media = root.appendingPathComponent("Media", isDirectory: true)
        let artwork = root.appendingPathComponent("Artwork", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: artwork, withIntermediateDirectories: true)
        try Data("fixture payload".utf8).write(to: media.appendingPathComponent("fixture.m4a"))
        let item = LibraryItem(
            id: UUID(),
            title: "Fixture",
            artist: "Artist",
            kind: .audio,
            localFilename: "fixture.m4a",
            originalFilename: "Fixture.m4a",
            addedAt: Date(),
            artworkFilename: nil
        )
        let backup = try MusicoBackupService.create(
            library: PersistedLibrary(items: [item], playlists: []),
            mediaDirectory: media,
            artworkDirectory: artwork,
            preferences: [:],
            appVersion: "1.0",
            temporaryDirectory: root.appendingPathComponent("Temporary")
        )
        return (root, backup)
    }
}

private final class DelayedBodyURLProtocol: URLProtocol {
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "musico-test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "video/mp4",
                "Content-Length": "104857600"
            ]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !stopped else { return }
            client?.urlProtocol(self, didLoad: Data(repeating: 0, count: 1_048_576))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        stopped = true
    }
}
