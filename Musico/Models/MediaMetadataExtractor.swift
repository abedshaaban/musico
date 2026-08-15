import AVFoundation
import Foundation
import ImageIO
import UIKit

enum MediaMetadataExtractor {
    struct ExtractedMetadata {
        var title: String?
        var artist: String?
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

        if metadata.artworkData == nil {
            metadata.artworkData = await videoThumbnail(from: asset)
        }

        return metadata
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
