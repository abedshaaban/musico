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
    /// Returns the direct stream URL, title, media kind, expected size, and thumbnail.
    /// Throws a descriptive error when the video cannot be resolved.
    static func resolve(videoID: String) async throws -> (
        url: URL,
        title: String,
        kind: MediaKind,
        expectedBytes: Int64,
        thumbnailURL: URL?
    ) {
        let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/player")!

        // Try multiple client configurations in order of reliability.
        let clientConfigs: [[String: Any]] = [
            ["clientName": "IOS", "clientVersion": "20.10.4", "deviceModel": "iPhone17,1", "userAgent": "com.google.ios.youtube/20.10.4 (iPhone17,1; U; CPU iOS 18_3_2 like Mac OS X;)", "hl": "en", "gl": "US"],
            ["clientName": "ANDROID", "clientVersion": "20.10.38", "androidSdkVersion": 34, "hl": "en", "gl": "US"],
            ["clientName": "WEB", "clientVersion": "2.20250618.01.00", "hl": "en", "gl": "US"],
            ["clientName": "TVHTML5", "clientVersion": "7.20250618.10.00", "hl": "en", "gl": "US"]
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
            request.setValue("com.google.ios.youtube/20.10.4 (iPhone17,1; U; CPU iOS 18_3_2 like Mac OS X;)", forHTTPHeaderField: "User-Agent")
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let title = (json["videoDetails"] as? [String: Any])?["title"] as? String ?? "YouTube Video"
            let thumbnailURL = thumbnailURL(from: json)

            // Some videos fail with a playability status; surface a useful message.
            if let playability = json["playabilityStatus"] as? [String: Any],
               let status = playability["status"] as? String, status != "OK" {
                let reason = playability["reason"] as? String ?? "This video is unavailable."
                print("YouTubeResolver: playability status '\(status)' for \(videoID): \(reason)")
                // Try the next client config before giving up.
                continue
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

            // Prefer muxed progressive MP4 (audio+video in one file). Avoid adaptive
            // video-only or audio-only formats because AVPlayer cannot play them alone.
            let playable = formats.filter { format in
                guard let mimeType = format["mimeType"] as? String,
                      mimeType.contains("video/mp4"),
                      format["audioQuality"] != nil,
                      format["url"] != nil else { return false }
                return true
            }

            // Sort by bitrate (highest first) for best quality.
            let sorted = playable.sorted { lhs, rhs in
                let lhsBitrate = (lhs["bitrate"] as? Int) ?? 0
                let rhsBitrate = (rhs["bitrate"] as? Int) ?? 0
                return lhsBitrate > rhsBitrate
            }

            for format in sorted {
                guard let streamString = format["url"] as? String,
                      let streamURL = URL(string: streamString),
                      let mimeType = format["mimeType"] as? String,
                      let kind = SupportedMedia.kind(forMIME: mimeType) else { continue }

                let expected = Int64(format["contentLength"] as? String ?? "") ?? 0
                print("YouTubeResolver: selected format \(format["itag"] ?? "?") \(mimeType) bitrate=\(format["bitrate"] ?? 0)")
                return (streamURL, title, kind, expected, thumbnailURL)
            }
        }

        throw NSError(domain: "YouTubeResolver", code: 2, userInfo: [NSLocalizedDescriptionKey: "No playable YouTube stream could be found for this video."])
    }

    private static func thumbnailURL(from json: [String: Any]) -> URL? {
        guard let videoDetails = json["videoDetails"] as? [String: Any],
              let thumbnail = videoDetails["thumbnail"] as? [String: Any],
              let thumbnails = thumbnail["thumbnails"] as? [[String: Any]] else {
            return nil
        }

        let best = thumbnails.max {
            ($0["width"] as? Int ?? 0) < ($1["width"] as? Int ?? 0)
        }
        guard let urlString = best?["url"] as? String else { return nil }
        return URL(string: urlString)
    }
}
