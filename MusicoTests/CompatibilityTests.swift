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
