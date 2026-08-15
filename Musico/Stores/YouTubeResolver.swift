import Foundation

struct YouTubePlaylistItem: Identifiable, Hashable {
    var id: String { videoID }
    let videoID: String
    let title: String
    let artist: String?
    let thumbnailURL: URL?

    var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
    }
}

struct YouTubePlaylistPreview: Identifiable {
    var id: String { playlistID }
    let playlistID: String
    let title: String
    let items: [YouTubePlaylistItem]
}

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

    /// Extracts the playlist identifier from both playlist links and watch links that
    /// carry a `list` query item.
    static func playlistID(from url: URL) -> String? {
        guard handles(url),
              let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "list" })?.value else {
            return nil
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard raw.count >= 10, raw.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return raw
    }

    /// Loads the complete, finite item list for a public or unlisted playlist. The
    /// initial page contains the playlist header and first batch; continuation pages
    /// are requested only for metadata. Stream URLs are deliberately resolved later,
    /// immediately before each queued download starts, because those URLs expire.
    static func resolvePlaylist(from url: URL) async throws -> YouTubePlaylistPreview {
        guard let playlistID = playlistID(from: url) else {
            throw playlistError("The link doesn't contain a valid YouTube playlist ID.")
        }

        var components = URLComponents(string: "https://www.youtube.com/playlist")!
        components.queryItems = [
            URLQueryItem(name: "list", value: playlistID),
            URLQueryItem(name: "hl", value: "en"),
            URLQueryItem(name: "gl", value: "US")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(webUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("CONSENT=YES+cb", forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw playlistError("The YouTube playlist page couldn't be loaded.")
        }

        let parsed = try playlistPage(fromHTML: html, playlistID: playlistID)
        var items = parsed.items
        var continuation = parsed.continuation
        var seenVideoIDs = Set(items.map(\.videoID))
        var seenContinuations: Set<String> = []

        if let apiKey = parsed.apiKey, let clientVersion = parsed.clientVersion {
            while let token = continuation,
                  seenContinuations.insert(token).inserted,
                  seenContinuations.count <= 100 {
                let page = try await continuationPage(
                    token: token,
                    apiKey: apiKey,
                    clientVersion: clientVersion
                )
                for item in page.items where seenVideoIDs.insert(item.videoID).inserted {
                    items.append(item)
                }
                continuation = page.continuation
            }
        }

        guard !items.isEmpty else {
            throw playlistError("No downloadable videos were found. The playlist may be private, empty, or unavailable.")
        }
        return YouTubePlaylistPreview(
            playlistID: playlistID,
            title: parsed.title,
            items: items
        )
    }

    /// Kept internal so deterministic HTML fixtures can exercise the fragile page
    /// boundary without making network requests.
    static func playlistPage(
        fromHTML html: String,
        playlistID: String
    ) throws -> (
        title: String,
        items: [YouTubePlaylistItem],
        continuation: String?,
        apiKey: String?,
        clientVersion: String?
    ) {
        guard let data = embeddedJSONObject(afterAny: [
            "var ytInitialData =",
            "window[\"ytInitialData\"] =",
            "ytInitialData ="
        ], in: html),
        let json = try? JSONSerialization.jsonObject(with: data) else {
            throw playlistError("YouTube returned a page Musico couldn't read. The playlist format may have changed.")
        }

        let items = playlistItems(in: json)
        let title = playlistTitle(in: json) ?? "YouTube Playlist"
        return (
            title,
            items,
            continuationToken(in: json),
            capturedValue(named: "INNERTUBE_API_KEY", in: html),
            capturedValue(named: "INNERTUBE_CLIENT_VERSION", in: html)
        )
    }

    /// Resolve a playable stream for a YouTube video.
    /// Returns the direct stream URL, title, inferred artist, media kind, expected size,
    /// and thumbnail.
    /// Throws a descriptive error when the video cannot be resolved.
    static func resolve(videoID: String) async throws -> (
        url: URL,
        title: String,
        artist: String?,
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

            let videoDetails = json["videoDetails"] as? [String: Any]
            let title = videoDetails?["title"] as? String ?? "YouTube Video"
            let description = videoDetails?["shortDescription"] as? String
            let artist = inferredArtist(title: title, description: description)
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
                return (streamURL, title, artist, kind, expected, thumbnailURL)
            }
        }

        throw NSError(domain: "YouTubeResolver", code: 2, userInfo: [NSLocalizedDescriptionKey: "No playable YouTube stream could be found for this video."])
    }

    /// YouTube does not provide a structured song-artist field for ordinary videos.
    /// Prefer an explicit description label, then common "artist - track" text in the
    /// description, and finally the video title. The channel author is intentionally not
    /// used because lyric and re-upload channels are often not the performing artist.
    static func inferredArtist(title: String, description: String?) -> String? {
        let descriptionLines = description?
            .components(separatedBy: .newlines)
            .map(cleanedMetadataLine) ?? []

        for line in descriptionLines {
            if let artist = explicitArtist(in: line) {
                return artist
            }
        }

        for line in descriptionLines.prefix(12) {
            guard let candidate = contentAfterPlaybackPrompt(in: line) else { continue }
            if let artist = artistBeforeTrackSeparator(in: candidate) {
                return artist
            }
        }

        return artistBeforeTrackSeparator(in: cleanedMetadataLine(title))
    }

    private static func explicitArtist(in line: String) -> String? {
        let labels = ["artist:", "artist -", "performed by:", "performed by ", "music by:", "music by "]
        let lowercase = line.lowercased()
        guard let label = labels.first(where: { lowercase.hasPrefix($0) }) else { return nil }
        let value = line.dropFirst(label.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func contentAfterPlaybackPrompt(in line: String) -> String? {
        let prompts = ["stream ", "listen to ", "listen: ", "play "]
        let lowercase = line.lowercased()
        guard let prompt = prompts.first(where: { lowercase.hasPrefix($0) }) else { return nil }
        return String(line.dropFirst(prompt.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func artistBeforeTrackSeparator(in text: String) -> String? {
        for separator in [" - ", " – ", " — "] {
            guard let range = text.range(of: separator) else { continue }
            let artist = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let track = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !artist.isEmpty && !track.isEmpty {
                return artist
            }
        }
        return nil
    }

    private static func cleanedMetadataLine(_ line: String) -> String {
        line.trimmingCharacters(
            in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "•·●▪◦"))
        )
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

    // MARK: - Playlist parsing

    // The mobile page currently serializes `ytInitialData` as a JavaScript string with
    // hex escapes. The desktop response keeps it as JSON and is therefore both smaller
    // to parse and less dependent on a JavaScript unescaper.
    private static let webUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126.0.0.0 Safari/537.36"

    private static func playlistError(_ message: String) -> NSError {
        NSError(
            domain: "YouTubeResolver.Playlist",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private static func continuationPage(
        token: String,
        apiKey: String,
        clientVersion: String
    ) async throws -> (items: [YouTubePlaylistItem], continuation: String?) {
        var components = URLComponents(string: "https://www.youtube.com/youtubei/v1/browse")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(webUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": clientVersion,
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "continuation": token
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            throw playlistError("Musico couldn't load the rest of the playlist.")
        }
        return (playlistItems(in: json), continuationToken(in: json))
    }

    private static func playlistItems(in root: Any) -> [YouTubePlaylistItem] {
        let legacyItems: [YouTubePlaylistItem] = dictionaries(
            named: "playlistVideoRenderer",
            in: root
        ).compactMap { renderer -> YouTubePlaylistItem? in
            guard let videoID = renderer["videoId"] as? String, videoID.count == 11 else {
                return nil
            }
            let title = text(from: renderer["title"])
            guard !title.isEmpty,
                  title.caseInsensitiveCompare("Deleted video") != .orderedSame,
                  title.caseInsensitiveCompare("Private video") != .orderedSame else {
                return nil
            }
            return YouTubePlaylistItem(
                videoID: videoID,
                title: title,
                artist: inferredArtist(title: title, description: nil),
                thumbnailURL: bestThumbnailURL(from: renderer["thumbnail"])
            )
        }
        let currentItems: [YouTubePlaylistItem] = dictionaries(
            named: "lockupViewModel",
            in: root
        ).compactMap { lockup -> YouTubePlaylistItem? in
            guard lockup["contentType"] as? String == "LOCKUP_CONTENT_TYPE_VIDEO",
                  let videoID = lockup["contentId"] as? String,
                  videoID.count == 11,
                  let metadata = lockup["metadata"] as? [String: Any],
                  let lockupMetadata = metadata["lockupMetadataViewModel"] as? [String: Any],
                  let titleContainer = lockupMetadata["title"] as? [String: Any],
                  let title = titleContainer["content"] as? String,
                  !title.isEmpty else {
                return nil
            }
            let thumbnailURL: URL?
            if let contentImage = lockup["contentImage"] as? [String: Any],
               let thumbnail = contentImage["thumbnailViewModel"] as? [String: Any],
               let image = thumbnail["image"] as? [String: Any],
               let sources = image["sources"] as? [[String: Any]] {
                thumbnailURL = bestThumbnailURL(fromSources: sources)
            } else {
                thumbnailURL = nil
            }
            return YouTubePlaylistItem(
                videoID: videoID,
                title: title,
                artist: inferredArtist(title: title, description: nil),
                thumbnailURL: thumbnailURL
            )
        }

        var seen: Set<String> = []
        return (legacyItems + currentItems).filter { seen.insert($0.videoID).inserted }
    }

    private static func playlistTitle(in root: Any) -> String? {
        if let metadata = dictionaries(named: "playlistMetadataRenderer", in: root).first,
           let title = metadata["title"] as? String,
           !title.isEmpty {
            return title
        }
        if let header = dictionaries(named: "playlistHeaderRenderer", in: root).first {
            let title = text(from: header["title"])
            if !title.isEmpty { return title }
        }
        return nil
    }

    private static func continuationToken(in root: Any) -> String? {
        for command in dictionaries(named: "continuationCommand", in: root) {
            if let token = command["token"] as? String, !token.isEmpty { return token }
        }
        return nil
    }

    private static func dictionaries(named key: String, in value: Any) -> [[String: Any]] {
        var matches: [[String: Any]] = []
        if let dictionary = value as? [String: Any] {
            if let match = dictionary[key] as? [String: Any] { matches.append(match) }
            for child in dictionary.values {
                matches.append(contentsOf: dictionaries(named: key, in: child))
            }
        } else if let array = value as? [Any] {
            for child in array {
                matches.append(contentsOf: dictionaries(named: key, in: child))
            }
        }
        return matches
    }

    private static func text(from value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return string }
        guard let dictionary = value as? [String: Any] else { return "" }
        if let simpleText = dictionary["simpleText"] as? String { return simpleText }
        if let runs = dictionary["runs"] as? [[String: Any]] {
            return runs.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }

    private static func bestThumbnailURL(from value: Any?) -> URL? {
        guard let dictionary = value as? [String: Any],
              let thumbnails = dictionary["thumbnails"] as? [[String: Any]] else {
            return nil
        }
        return bestThumbnailURL(fromSources: thumbnails)
    }

    private static func bestThumbnailURL(fromSources thumbnails: [[String: Any]]) -> URL? {
        let best = thumbnails.max {
            ($0["width"] as? Int ?? 0) < ($1["width"] as? Int ?? 0)
        }
        guard let raw = best?["url"] as? String else { return nil }
        return URL(string: raw.replacingOccurrences(of: "&amp;", with: "&"))
    }

    private static func capturedValue(named name: String, in html: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "\\\"\(escapedName)\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: html,
                range: NSRange(html.startIndex..., in: html)
              ),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range])
    }

    private static func embeddedJSONObject(afterAny markers: [String], in html: String) -> Data? {
        for marker in markers {
            guard let markerRange = html.range(of: marker),
                  let start = html[markerRange.upperBound...].firstIndex(of: "{") else {
                continue
            }
            var depth = 0
            var isInsideString = false
            var isEscaped = false
            var index = start
            while index < html.endIndex {
                let character = html[index]
                if isInsideString {
                    if isEscaped {
                        isEscaped = false
                    } else if character == "\\" {
                        isEscaped = true
                    } else if character == "\"" {
                        isInsideString = false
                    }
                } else if character == "\"" {
                    isInsideString = true
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(html[start...index]).data(using: .utf8)
                    }
                }
                index = html.index(after: index)
            }
        }
        return nil
    }
}
