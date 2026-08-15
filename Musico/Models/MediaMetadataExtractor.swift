import AVFoundation
import Foundation
import ImageIO
import UIKit

enum MediaMetadataExtractor {
    struct ExtractedMetadata {
        var title: String?
        var artist: String?
        var album: String?
        var genre: String?
        var year: Int?
        var trackNumber: Int?
        var replayGainDB: Double?
        var artworkData: Data?
    }

    static func extract(from url: URL) async -> ExtractedMetadata {
        let asset = AVURLAsset(url: url)
        var metadata = ExtractedMetadata()

        for item in asset.commonMetadata {
            guard let key = item.commonKey else { continue }
            switch key {
            case .commonKeyTitle where metadata.title == nil:
                metadata.title = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            case .commonKeyArtist where metadata.artist == nil:
                metadata.artist = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            case .commonKeyArtwork where metadata.artworkData == nil:
                metadata.artworkData = item.dataValue
            default:
                break
            }
        }

        for item in asset.metadata {
            let value = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            switch item.identifier {
            case .commonIdentifierAlbumName where metadata.album == nil:
                metadata.album = value
            case .commonIdentifierType where metadata.genre == nil:
                if let value, !value.isEmpty, Int(value) == nil { metadata.genre = value }
            case .commonIdentifierCreationDate where metadata.year == nil:
                metadata.year = value.flatMap(parseYear)
            default:
                break
            }

            let rawKey = (item.key as? String) ?? ""
            let normalizedKey = "\(rawKey) \(item.identifier?.rawValue ?? "")".lowercased()
            if metadata.replayGainDB == nil,
               normalizedKey.contains("replaygain"),
               normalizedKey.contains("gain"),
               let value {
                metadata.replayGainDB = parseReplayGain(value)
            }
            switch rawKey {
            case "TALB", "©alb":
                if metadata.album == nil { metadata.album = value }
            case "TCON", "©gen":
                if metadata.genre == nil { metadata.genre = value }
            case "TYER", "TDRC", "©day":
                if metadata.year == nil { metadata.year = value.flatMap(parseYear) }
            case "TRCK", "trkn":
                if metadata.trackNumber == nil {
                    metadata.trackNumber = value.flatMap(parseTrackNumber)
                        ?? item.numberValue?.intValue
                }
            default:
                break
            }
        }

        if metadata.artworkData == nil {
            metadata.artworkData = await videoThumbnail(from: asset)
        }

        return metadata
    }

    static func parseYear(_ raw: String) -> Int? {
        let groups = raw.split { !$0.isNumber }
        guard let candidate = groups.first(where: { $0.count == 4 }),
              let year = Int(candidate), (1000...9999).contains(year) else { return nil }
        return year
    }

    static func parseTrackNumber(_ raw: String) -> Int? {
        let first = raw.split(separator: "/", maxSplits: 1).first ?? Substring(raw)
        let digits = first.prefix { $0.isNumber }
        guard let number = Int(digits), number > 0 else { return nil }
        return number
    }

    static func parseReplayGain(_ raw: String) -> Double? {
        let allowed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { $0.isNumber || $0 == "." || $0 == "+" || $0 == "-" }
        guard !allowed.isEmpty, let value = Double(allowed), (-30...30).contains(value) else {
            return nil
        }
        return value
    }

    /// Uses AVFoundation's runtime decoder/container check rather than trusting a file
    /// extension or MIME type alone.
    static func isPlayable(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        return await withCheckedContinuation { continuation in
            asset.loadValuesAsynchronously(forKeys: ["playable"]) {
                var error: NSError?
                let status = asset.statusOfValue(forKey: "playable", error: &error)
                continuation.resume(returning: status == .loaded && asset.isPlayable)
            }
        }
    }

    static func saveArtwork(_ data: Data, to directory: URL) throws -> String {
        let normalized = normalizedJPEG(from: data) ?? data
        let filename = UUID().uuidString + ".jpg"
        let destination = directory.appendingPathComponent(filename)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try normalized.write(to: destination, options: .atomic)
        return filename
    }

    private static func normalizedJPEG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1_200
                ] as CFDictionary
              ) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.82)
    }

    private static func videoThumbnail(from asset: AVAsset) async -> Data? {
        guard asset.tracks(withMediaType: .video).isEmpty == false else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        return await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, _, _ in
                guard let image else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: UIImage(cgImage: image).jpegData(compressionQuality: 0.85))
            }
        }
    }
}
