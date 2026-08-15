import CryptoKit
import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let musicoBackup = UTType(
        exportedAs: "com.abedshaaban.musico.backup",
        conformingTo: .data
    )
}

struct MusicoBackupPreview: Identifiable, Equatable {
    var id: String { fileURL.path }
    let fileURL: URL
    let createdAt: Date
    let itemCount: Int
    let mediaBytes: Int64
    let archiveBytes: Int64
    let appVersion: String
}

struct CreatedMusicoBackup {
    let fileURL: URL
    let preview: MusicoBackupPreview
}

enum MusicoBackupError: LocalizedError {
    case noLibrary
    case missingMedia(String)
    case invalidArchive(String)
    case unsupportedVersion(Int)
    case corruptedFile(String)
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .noLibrary:
            return "There is no saved library to back up."
        case .missingMedia(let name):
            return "The library references a missing media file: \(name)."
        case .invalidArchive(let reason):
            return "This is not a valid Musico backup. \(reason)"
        case .unsupportedVersion(let version):
            return "This backup uses unsupported format version \(version)."
        case .corruptedFile(let name):
            return "The backup is damaged or incomplete near \(name)."
        case .restoreFailed(let reason):
            return "The library could not be restored. \(reason)"
        }
    }
}

enum MusicoBackupService {
    struct Manifest: Codable, Equatable {
        let formatVersion: Int
        let createdAt: Date
        let appVersion: String
        let itemCount: Int
        let mediaBytes: Int64
        let preferences: [String: String]
        let files: [Entry]
    }

    struct Entry: Codable, Equatable {
        let path: String
        let byteCount: Int64
        let sha256: String
    }

    private enum Payload {
        case data(Data)
        case file(URL)
    }

    private struct Source {
        let entry: Entry
        let payload: Payload
    }

    static let currentFormatVersion = 1
    static let preferenceKeys = [
        "nowPlayingVisualStyle",
        "librarySort",
        "libraryKindFilter"
    ]

    private static let magic = Data("MUSICO-BACKUP\n".utf8)
    private static let manifestLengthBytes = 8
    private static let maximumManifestBytes = 16 * 1024 * 1024
    private static let maximumFileCount = 100_000
    private static let chunkSize = 1024 * 1024

    static func currentPreferences(defaults: UserDefaults = .standard) -> [String: String] {
        Dictionary(uniqueKeysWithValues: preferenceKeys.compactMap { key in
            guard let value = defaults.string(forKey: key) else { return nil }
            return (key, value)
        })
    }

    static func applyPreferences(
        _ preferences: [String: String],
        defaults: UserDefaults = .standard
    ) {
        for key in preferenceKeys {
            if let value = preferences[key] { defaults.set(value, forKey: key) }
        }
    }

    static func create(
        library: PersistedLibrary,
        mediaDirectory: URL,
        artworkDirectory: URL,
        preferences: [String: String],
        appVersion: String,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default
    ) throws -> CreatedMusicoBackup {
        guard !library.items.isEmpty else { throw MusicoBackupError.noLibrary }

        var sources: [Source] = []
        let libraryData = try JSONEncoder.musico.encode(library)
        sources.append(
            Source(
                entry: Entry(
                    path: "library.json",
                    byteCount: Int64(libraryData.count),
                    sha256: sha256(data: libraryData)
                ),
                payload: .data(libraryData)
            )
        )

        let mediaNames = Array(Set(library.items.map(\.localFilename))).sorted()
        for name in mediaNames {
            guard isSafeFilename(name) else {
                throw MusicoBackupError.invalidArchive("The library contains an unsafe filename.")
            }
            let url = mediaDirectory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path) else {
                throw MusicoBackupError.missingMedia(name)
            }
            sources.append(try source(path: "Media/\(name)", url: url))
        }

        let artworkNames = Array(Set(library.items.compactMap(\.artworkFilename))).sorted()
        for name in artworkNames where isSafeFilename(name) {
            let url = artworkDirectory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            sources.append(try source(path: "Artwork/\(name)", url: url))
        }

        let mediaBytes = sources
            .filter { $0.entry.path.hasPrefix("Media/") }
            .reduce(Int64(0)) { $0 + $1.entry.byteCount }
        let manifest = Manifest(
            formatVersion: currentFormatVersion,
            createdAt: Date(),
            appVersion: appVersion,
            itemCount: library.items.count,
            mediaBytes: mediaBytes,
            preferences: preferences,
            files: sources.map(\.entry)
        )
        let manifestData = try JSONEncoder.musico.encode(manifest)
        guard manifestData.count <= maximumManifestBytes else {
            throw MusicoBackupError.invalidArchive("The backup index is too large.")
        }

        let directory = temporaryDirectory.appendingPathComponent("Musico Backups", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "Musico-\(backupTimestamp(manifest.createdAt))-\(UUID().uuidString.prefix(8)).musicobackup"
        let destination = directory.appendingPathComponent(filename)
        fileManager.createFile(atPath: destination.path, contents: nil)

        do {
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            try output.write(contentsOf: magic)
            try output.write(contentsOf: littleEndianData(UInt64(manifestData.count)))
            try output.write(contentsOf: manifestData)
            for source in sources {
                try write(source.payload, to: output)
            }
            try output.synchronize()
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }

        let archiveBytes = fileSize(destination)
        return CreatedMusicoBackup(
            fileURL: destination,
            preview: MusicoBackupPreview(
                fileURL: destination,
                createdAt: manifest.createdAt,
                itemCount: manifest.itemCount,
                mediaBytes: manifest.mediaBytes,
                archiveBytes: archiveBytes,
                appVersion: manifest.appVersion
            )
        )
    }

    static func inspect(_ fileURL: URL) throws -> MusicoBackupPreview {
        let manifest = try readManifest(fileURL).manifest
        return MusicoBackupPreview(
            fileURL: fileURL,
            createdAt: manifest.createdAt,
            itemCount: manifest.itemCount,
            mediaBytes: manifest.mediaBytes,
            archiveBytes: fileSize(fileURL),
            appVersion: manifest.appVersion
        )
    }

    @discardableResult
    static func restore(
        _ fileURL: URL,
        applicationSupport: URL,
        fileManager: FileManager = .default
    ) throws -> Manifest {
        let parsed = try readManifest(fileURL)
        let manifest = parsed.manifest
        let parent = applicationSupport.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".MusicoRestore-\(UUID().uuidString)", isDirectory: true)
        let rollback = parent.appendingPathComponent(".MusicoPrevious-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        do {
            try extract(
                fileURL,
                manifest: manifest,
                payloadOffset: parsed.payloadOffset,
                destination: staging,
                fileManager: fileManager
            )
            try validateExtractedLibrary(at: staging, manifest: manifest, fileManager: fileManager)
            try install(
                staged: staging,
                applicationSupport: applicationSupport,
                rollback: rollback,
                fileManager: fileManager
            )
            return manifest
        } catch let error as MusicoBackupError {
            throw error
        } catch {
            throw MusicoBackupError.restoreFailed(error.localizedDescription)
        }
    }

    static func removeTemporaryFile(_ url: URL?, fileManager: FileManager = .default) {
        guard let url else { return }
        try? fileManager.removeItem(at: url)
    }

    private static func source(path: String, url: URL) throws -> Source {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw MusicoBackupError.corruptedFile(url.lastPathComponent)
        }
        let size = fileSize(url)
        guard size >= 0 else { throw MusicoBackupError.corruptedFile(url.lastPathComponent) }
        return Source(
            entry: Entry(path: path, byteCount: size, sha256: try sha256(file: url)),
            payload: .file(url)
        )
    }

    private static func write(_ payload: Payload, to output: FileHandle) throws {
        switch payload {
        case .data(let data):
            try output.write(contentsOf: data)
        case .file(let url):
            let input = try FileHandle(forReadingFrom: url)
            defer { try? input.close() }
            while let data = try input.read(upToCount: chunkSize), !data.isEmpty {
                try output.write(contentsOf: data)
            }
        }
    }

    private static func readManifest(_ fileURL: URL) throws -> (manifest: Manifest, payloadOffset: UInt64) {
        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        guard try readExactly(input, count: magic.count) == magic else {
            throw MusicoBackupError.invalidArchive("The file signature does not match.")
        }
        let lengthData = try readExactly(input, count: manifestLengthBytes)
        let manifestLength = decodeLittleEndianUInt64(lengthData)
        guard manifestLength > 0, manifestLength <= UInt64(maximumManifestBytes) else {
            throw MusicoBackupError.invalidArchive("The backup index length is invalid.")
        }
        let manifestData = try readExactly(input, count: Int(manifestLength))
        let manifest: Manifest
        do {
            manifest = try JSONDecoder.musico.decode(Manifest.self, from: manifestData)
        } catch {
            throw MusicoBackupError.invalidArchive("The backup index could not be read.")
        }
        guard manifest.formatVersion == currentFormatVersion else {
            throw MusicoBackupError.unsupportedVersion(manifest.formatVersion)
        }
        try validate(manifest: manifest)

        let payloadOffset = UInt64(magic.count + manifestLengthBytes) + manifestLength
        let payloadBytes = try manifest.files.reduce(UInt64(0)) { partial, entry in
            let (sum, overflow) = partial.addingReportingOverflow(UInt64(entry.byteCount))
            if overflow { throw MusicoBackupError.invalidArchive("The backup size is invalid.") }
            return sum
        }
        let (expectedSize, sizeOverflow) = payloadOffset.addingReportingOverflow(payloadBytes)
        let actualSize = fileSize(fileURL)
        guard !sizeOverflow, actualSize >= 0, UInt64(actualSize) == expectedSize else {
            throw MusicoBackupError.invalidArchive("The file is incomplete or contains unexpected data.")
        }
        return (manifest, payloadOffset)
    }

    private static func validate(manifest: Manifest) throws {
        guard manifest.itemCount >= 0,
              manifest.mediaBytes >= 0,
              !manifest.files.isEmpty,
              manifest.files.count <= maximumFileCount,
              manifest.files.first?.path == "library.json" else {
            throw MusicoBackupError.invalidArchive("Required library information is missing.")
        }
        var paths = Set<String>()
        for entry in manifest.files {
            guard entry.byteCount >= 0,
                  entry.sha256.count == 64,
                  paths.insert(entry.path).inserted,
                  isAllowedArchivePath(entry.path) else {
                throw MusicoBackupError.invalidArchive("The backup index contains an unsafe entry.")
            }
        }
    }

    private static func extract(
        _ fileURL: URL,
        manifest: Manifest,
        payloadOffset: UInt64,
        destination: URL,
        fileManager: FileManager
    ) throws {
        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        try input.seek(toOffset: payloadOffset)
        try fileManager.createDirectory(
            at: destination.appendingPathComponent("Media", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: destination.appendingPathComponent("Artwork", isDirectory: true),
            withIntermediateDirectories: true
        )

        for entry in manifest.files {
            let outputURL = destination.appendingPathComponent(entry.path)
            try fileManager.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            fileManager.createFile(atPath: outputURL.path, contents: nil)
            let output = try FileHandle(forWritingTo: outputURL)
            var remaining = entry.byteCount
            var hasher = SHA256()
            do {
                while remaining > 0 {
                    let count = Int(min(Int64(chunkSize), remaining))
                    let data = try readExactly(input, count: count)
                    hasher.update(data: data)
                    try output.write(contentsOf: data)
                    remaining -= Int64(data.count)
                }
                try output.close()
            } catch {
                try? output.close()
                throw error
            }
            guard hex(hasher.finalize()) == entry.sha256 else {
                throw MusicoBackupError.corruptedFile(entry.path)
            }
        }
    }

    private static func validateExtractedLibrary(
        at staging: URL,
        manifest: Manifest,
        fileManager: FileManager
    ) throws {
        let data = try Data(contentsOf: staging.appendingPathComponent("library.json"))
        let library: PersistedLibrary
        do {
            library = try JSONDecoder.musico.decode(PersistedLibrary.self, from: data)
        } catch {
            throw MusicoBackupError.invalidArchive("The saved library metadata is unreadable.")
        }
        guard library.items.count == manifest.itemCount else {
            throw MusicoBackupError.invalidArchive("The item count does not match the backup index.")
        }
        guard Set(library.items.map(\.id)).count == library.items.count else {
            throw MusicoBackupError.invalidArchive("The library contains duplicate item identifiers.")
        }
        for item in library.items {
            guard isSafeFilename(item.localFilename),
                  fileManager.fileExists(
                    atPath: staging
                        .appendingPathComponent("Media", isDirectory: true)
                        .appendingPathComponent(item.localFilename)
                        .path
                  ) else {
                throw MusicoBackupError.invalidArchive("A library media file is missing.")
            }
            if let artwork = item.artworkFilename, !isSafeFilename(artwork) {
                throw MusicoBackupError.invalidArchive("An artwork filename is unsafe.")
            }
        }
    }

    private static func install(
        staged: URL,
        applicationSupport: URL,
        rollback: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rollback, withIntermediateDirectories: true)
        let names = ["Media", "Artwork", "library.json"]
        var movedOld: [String] = []
        var installedNew: [String] = []

        do {
            for name in names {
                let current = applicationSupport.appendingPathComponent(name)
                guard fileManager.fileExists(atPath: current.path) else { continue }
                try fileManager.moveItem(at: current, to: rollback.appendingPathComponent(name))
                movedOld.append(name)
            }
            for name in names {
                let replacement = staged.appendingPathComponent(name)
                try fileManager.moveItem(
                    at: replacement,
                    to: applicationSupport.appendingPathComponent(name)
                )
                installedNew.append(name)
            }
            try? fileManager.removeItem(at: rollback)
        } catch {
            for name in installedNew {
                try? fileManager.removeItem(at: applicationSupport.appendingPathComponent(name))
            }
            var rollbackSucceeded = true
            for name in movedOld {
                do {
                    try fileManager.moveItem(
                        at: rollback.appendingPathComponent(name),
                        to: applicationSupport.appendingPathComponent(name)
                    )
                } catch {
                    rollbackSucceeded = false
                }
            }
            if rollbackSucceeded {
                try? fileManager.removeItem(at: rollback)
            } else {
                throw MusicoBackupError.restoreFailed(
                    "The previous library was preserved at \(rollback.lastPathComponent) after rollback could not finish."
                )
            }
            throw error
        }
    }

    private static func isAllowedArchivePath(_ path: String) -> Bool {
        if path == "library.json" { return true }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0] == "Media" || parts[0] == "Artwork" else { return false }
        return isSafeFilename(String(parts[1]))
    }

    private static func isSafeFilename(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && URL(fileURLWithPath: name).lastPathComponent == name
    }

    private static func readExactly(_ handle: FileHandle, count: Int) throws -> Data {
        guard count >= 0, let data = try handle.read(upToCount: count), data.count == count else {
            throw MusicoBackupError.invalidArchive("The file ended unexpectedly.")
        }
        return data
    }

    private static func sha256(data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    private static func sha256(file url: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var hasher = SHA256()
        while let data = try input.read(upToCount: chunkSize), !data.isEmpty {
            hasher.update(data: data)
        }
        return hex(hasher.finalize())
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func littleEndianData(_ value: UInt64) -> Data {
        var littleEndian = value.littleEndian
        return Data(bytes: &littleEndian, count: MemoryLayout<UInt64>.size)
    }

    private static func decodeLittleEndianUInt64(_ data: Data) -> UInt64 {
        data.withUnsafeBytes { raw in
            UInt64(littleEndian: raw.loadUnaligned(as: UInt64.self))
        }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return -1 }
        return size.int64Value
    }

    private static func backupTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: date)
    }
}
