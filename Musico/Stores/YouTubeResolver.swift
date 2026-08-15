import Foundation

/// Resolves a YouTube watch or share URL to a playable media stream by calling YouTube's
/// internal player API (youtubei). Extracted streams are downloaded with URLSession and
/// stored locally like any other direct-file download.
///
/// This uses an undocumented API; it can change or stop working at any time.
/// Download only content you are authorized to save.
@MainActor
enum YouTubeResolver {

    /// Returns true if the URL belongs to a YouTube watch or share host.
    static func handles(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("youtube.com") || host.contains("youtu.be")
    }

    /// Extract the 11-character video ID from a YouTube URL.
    /// Returns nil if no valid ID can be found.
    static func videoID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        if host.contains("youtu.be") {
            let id = url.pathComponents.count > 1 ? url.pathComponents[1] : ""
            return id.count == 11 ? id : nil
        }
        if let queryID = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value,
           queryID.count == 11 {
            return queryID
        }
        return nil
    }

    /// Resolve a playable stream for a YouTube video.
    /// Returns the direct stream URL, title, and media kind.
    /// Throws a descriptive error when the video cannot be resolved.
    static func resolve(videoID: String) async throws -> (url: URL, title: String, kind: MediaKind, expectedBytes: Int64) {
        // Known public YouTube Innertube API key used by the web and mobile clients.
        let apiKey = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
        let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/player?key=\(apiKey)")!

        // Try multiple client configurations in order of reliability.
        let clientConfigs: [[String: Any]] = [
            ["clientName": "IOS", "clientVersion": "19.09.3", "deviceModel": "iPhone16,2", "userAgent": "com.google.ios.youtube/19.09.3 (iPhone16,2; U; CPU iOS 17_2 like Mac OS X;)", "hl": "en", "gl": "US"],
            ["clientName": "ANDROID", "clientVersion": "19.09.37", "androidSdkVersion": 30, "hl": "en", "gl": "US"],
            ["clientName": "WEB", "clientVersion": "2.20240201.01.00", "hl": "en", "gl": "US"]
        ]

        for clientConfig in clientConfigs {
            let payload: [String: Any] = [
                "videoId": videoID,
                "context": ["client": clientConfig],
                "contentCheckOk": true,
                "racyCheckOk": true
            ]

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("com.google.ios.youtube/19.09.3 (iPhone16,2; U; CPU iOS 17_2 like Mac OS X;)", forHTTPHeaderField: "User-Agent")
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let title = (json["videoDetails"] as? [String: Any])?["title"] as? String ?? "YouTube Video"

            // Some videos fail with a playability status; surface a useful message.
            if let playability = json["playabilityStatus"] as? [String: Any],
               let status = playability["status"] as? String, status != "OK" {
                let reason = playability["reason"] as? String ?? "This video is unavailable."
                throw NSError(domain: "YouTubeResolver", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
            }

            guard let streamingData = json["streamingData"] as? [String: Any] else { continue }

            // Collect all formats we can play.
            var formats: [[String: Any]] = []
            if let progressive = streamingData["formats"] as? [[String: Any]] {
                formats.append(contentsOf: progressive)
            }
            if let adaptive = streamingData["adaptiveFormats"] as? [[String: Any]] {
                formats.append(contentsOf: adaptive)
            }

            // Prefer a progressive MP4 (single file, easiest to save), then any MP4,
            // then any playable format.
            let playable = formats.filter { format in
                guard let mimeType = format["mimeType"] as? String else { return false }
                return SupportedMedia.kind(forMIME: mimeType) != nil && format["url"] != nil
            }

            let progressive = playable.filter { ($0["mimeType"] as? String)?.contains("video/mp4") == true && $0["audioQuality"] != nil }
            let anyMP4 = playable.filter { ($0["mimeType"] as? String)?.contains("mp4") == true }
            let best = progressive.first ?? anyMP4.first ?? playable.first

            if let best = best,
               let streamString = best["url"] as? String,
               let streamURL = URL(string: streamString),
               let mimeType = best["mimeType"] as? String,
               let kind = SupportedMedia.kind(forMIME: mimeType) {
                let expected = Int64(best["contentLength"] as? String ?? "") ?? 0
                return (streamURL, title, kind, expected)
            }
        }

        throw NSError(domain: "YouTubeResolver", code: 2, userInfo: [NSLocalizedDescriptionKey: "No playable YouTube stream could be found for this video."])
    }
}
