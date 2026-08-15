# Musico

Musico is a dependency-free SwiftUI media-library app for iPhone, targeting iOS 15. It keeps imported media and metadata locally on the device.

## Run on an iPhone 7

1. Open `Musico.xcodeproj` in Xcode.
2. Select the Musico target, then choose your Apple developer team under Signing & Capabilities.
3. Connect the iPhone 7, trust the Mac if prompted, and select the phone as the run destination.
4. Build and run. iOS may ask you to enable Developer Mode depending on its version and signing setup.

The target is iPhone-only, has an iOS 15.0 deployment target, and declares the Background Modes `audio` capability in `Info.plist`. Playback uses Apple's `AVPlayer`, `AVAudioSession`, and lock-screen `MediaPlayer` APIs.

## Background playback and external controls

- Audio keeps playing while the display is locked or the app is in the background.
- Lock Screen, Control Center, compatible headphones, and car controls support play/pause, next/previous, seeking, and 15-second skips.
- Now Playing shows the title, artist, duration, queue position, and downsampled cover artwork.
- Playback pauses when headphones are unplugged, responds to system interruptions such as calls, and resumes only when iOS indicates that it is appropriate.

For lower memory and battery use on older devices, artwork is downsampled and held in a bounded cache, background UI timers are suspended, animated player visuals are capped at 30 FPS and pause off-screen, and download-progress disk writes are coalesced.

## Tabs

- **Add** — paste a direct `https://` link to a media file (or a YouTube video link). Musico validates the link, then downloads it in the background.
- **Downloads** — live progress, cancel, retry, and clear for the background download queue.
- **Library** — import user-provided audio/video through the Files picker, browse all media, and manage playlists.
- **Now Playing** — play/pause, seek, skip, shuffle; shows video for video items.

## Add-by-URL flow

1. The URL must use `https` and point straight at an audio or video file, **or** be a YouTube video link.
2. For direct files, a `HEAD` (with ranged-`GET` fallback) probe validates the link is reachable and its `Content-Type` is a supported audio/video container.
3. For YouTube links, the internal player API resolves a playable stream, which is then downloaded like a direct file.
4. `URLSession` background configuration (`com.abedshaaban.Musico.downloads`) downloads the file even when the app is suspended; `AppDelegate` captures the background-session completion handler.
5. The completed file is moved into `Application Support/Musico/Media` and registered in the persistent library.

## Compliance

Musico only fetches URLs the user is authorized to save. YouTube links are resolved via YouTube's internal player API; download only content you have the right to save. Extension points (see `DownloadManager.swift`) allow adding providers for other services.

- Add a download provider only when a source's terms and the user's rights allow returning a direct file URL.
- Audio conversion — define a conversion protocol only after an approved, locally supported (e.g. AVFoundation) implementation is chosen.

## Persistence

Copied/downloaded media, library metadata, playlists (`library.json`), and the download queue (`downloads.json`) all live under Application Support. Downloads interrupted by app termination are surfaced as failed with a one-tap retry.
