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
        XCTAssertEqual(layout.sectionSpacing, 10)
        XCTAssertEqual(layout.playButtonSize, 50)
    }

    func testNowPlayingLayoutKeepsLargeScreenPresentation() {
        let layout = NowPlayingLayoutMetrics(width: 393, height: 760)

        XCTAssertFalse(layout.isCompact)
        XCTAssertEqual(layout.artworkWidth, 353)
        XCTAssertEqual(layout.sectionSpacing, 20)
        XCTAssertEqual(layout.playButtonSize, 58)
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
