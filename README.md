# Musico

Musico is a dependency-free SwiftUI media-library app for iPhone, targeting iOS 15. It keeps imported media and metadata locally on the device.

## Run on an iPhone 7

1. Open `Musico.xcodeproj` in Xcode.
2. Select the Musico target, then choose your Apple developer team under Signing & Capabilities.
3. Connect the iPhone 7, trust the Mac if prompted, and select the phone as the run destination.
4. Build and run. iOS may ask you to enable Developer Mode depending on its version and signing setup.

The target is iPhone-only, has an iOS 15.0 deployment target, and declares the Background Modes `audio` capability in `Info.plist`. Playback uses Apple's `AVPlayer`, `AVAudioSession`, and lock-screen `MediaPlayer` APIs.

## First-version scope

- Search the local library and import user-provided audio/video through the system file picker.
- Persist copied media, library metadata, and playlists under Application Support.
- Create playlists, add/remove media, play a playlist, and shuffle.
- Play/pause, seek, skip, and view video on the Now Playing screen.
- Show queue and state UI for a future authorized download source.

There is intentionally no web search, extraction, scraping, conversion, FFmpeg, or command-line retrieval. `AuthorizedDownloadSource` in `DownloadQueueStore.swift` is the extension point for a future direct-download source. Conversion should be introduced behind a separate protocol only after an authorized local implementation is selected.
